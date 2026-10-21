import Foundation
import SwiftData
import XCTest
@testable import Selno

/// Phase 05.5 performance baseline.
///
/// These tests use only synthetic in-memory data. They do not touch the real
/// Application Support store, do not write backups, and do not measure the
/// window server. Their purpose is to make algorithmic and SwiftData query
/// costs repeatable so later changes can be compared on the same machine.
@MainActor
final class Phase055PerformanceTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_003_000)

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3_600) ?? .gmt
        value.locale = Locale(identifier: "zh_CN")
        return value
    }

    // MARK: Layout engine

    func testWorkspaceLayoutEngineScalability() {
        for count in [10, 30, 100] {
            let items = (0..<count).map { index in
                ModuleLayoutItem(
                    id: UUID(),
                    size: [ModuleSize.small, .medium, .large][index % 3]
                )
            }
            for width in [400.0, 800.0, 1200.0] {
                measureMilliseconds("layout modules=\(count) width=\(Int(width))") {
                    _ = WorkspaceLayoutEngine.placements(for: items, availableWidth: width)
                }
            }
        }
    }

    // MARK: Query + filter costs on a 10,000-task store

    func testSwiftDataAndFilterScalability() throws {
        let now = base.addingTimeInterval(86_400 * 30)
        let today = calendar.startOfDay(for: now)
        let month = CalendarMath.window(containing: today, mode: .month, listRange: .month, calendar: calendar)
        let unrestricted = TaskFilterExpression.unrestricted
        let restricted = TaskFilterExpression(
            statuses: [TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue],
            dateField: .any,
            dateRange: .next7Days,
            dueState: .hasDue
        )
        let searched = TaskFilterExpression(
            statuses: [TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue],
            searchText: "论文"
        )
        let unrestrictedContext = unrestricted.evaluationContext(now: now, calendar: calendar)
        let restrictedContext = restricted.evaluationContext(now: now, calendar: calendar)
        let searchedContext = searched.evaluationContext(now: now, calendar: calendar)

        for count in [100, 1_000, 10_000] {
            let container = try makeContainer(taskCount: count)
            let context = container.mainContext
            let allTasks = try context.fetch(FetchDescriptor<TodoTask>())

            measureMilliseconds("fetch active tasks n=\(count)") {
                _ = try? context.fetch(WorkspaceDataQuery.activeTasks())
            }
            measureMilliseconds("fetch month window tasks n=\(count)") {
                _ = try? context.fetch(CalendarDataQuery.tasks(in: month.range))
            }
            measureMilliseconds("fetch overdue tasks n=\(count)") {
                _ = try? context.fetch(DashboardDataQuery.overdue(before: today))
            }
            measureMilliseconds("fetch unbounded inbox n=\(count)") {
                _ = try? context.fetch(DashboardDataQuery.inbox())
            }
            measureMilliseconds("fetch inbox limit 4 n=\(count)") {
                _ = try? context.fetch(DashboardDataQuery.inbox(limit: 4))
            }
            measureMilliseconds("count inbox matches n=\(count)") {
                _ = try? context.fetchCount(DashboardDataQuery.inbox())
            }
            measureMilliseconds("filter unrestricted n=\(count)") {
                _ = allTasks.filter { unrestricted.matches($0, now: now, calendar: calendar) }
            }
            measureMilliseconds("filter status+date n=\(count)") {
                _ = allTasks.filter { restricted.matches($0, now: now, calendar: calendar) }
            }
            measureMilliseconds("filter with search n=\(count)") {
                _ = allTasks.filter { searched.matches($0, now: now, calendar: calendar) }
            }
            measureMilliseconds("filter unrestricted prepared n=\(count)") {
                _ = allTasks.filter { unrestricted.matches($0, context: unrestrictedContext) }
            }
            measureMilliseconds("filter status+date prepared n=\(count)") {
                _ = allTasks.filter { restricted.matches($0, context: restrictedContext) }
            }
            measureMilliseconds("filter with search prepared n=\(count)") {
                _ = allTasks.filter { searched.matches($0, context: searchedContext) }
            }
            measureMilliseconds("task list scope all n=\(count)") {
                _ = TaskListScope.all.tasks(from: allTasks, on: today, calendar: calendar)
            }
            measureMilliseconds("fetch task workspace inbox n=\(count)") {
                _ = try? context.fetch(TaskWorkspaceQuery.tasks(for: .inbox))
            }
            measureMilliseconds("fetch task workspace all n=\(count)") {
                _ = try? context.fetch(TaskWorkspaceQuery.tasks(for: .all))
            }
        }

        let container = try makeContainer(taskCount: 10_000)
        let context = container.mainContext
        let allTasks = try context.fetch(FetchDescriptor<TodoTask>())
        let events = (0..<200).map { index in
            CalendarEvent(
                title: "Synthetic event \(index)",
                startsAt: today.addingTimeInterval(Double(index % 20) * 86_400),
                endsAt: today.addingTimeInterval(Double(index % 20) * 86_400 + 3_600),
                now: base
            )
        }
        measureMilliseconds("dashboard projection 10k tasks + 200 events") {
            _ = DashboardProjection.build(
                tasks: allTasks,
                events: events,
                now: now,
                days: 7,
                monthWindow: month,
                calendar: calendar
            )
        }

        measureMilliseconds("workspace projection 10k tasks + 200 events without month") {
            _ = DashboardProjection.build(
                tasks: allTasks,
                events: events,
                now: now,
                days: 3,
                monthWindow: month,
                calendar: calendar,
                includeMonth: false
            )
        }

        measureMilliseconds("calendar agenda 10k tasks + 200 events") {
            _ = CalendarAgendaBuilder.build(
                tasks: allTasks,
                events: events,
                window: month,
                calendar: calendar
            )
        }
    }

    func testBackupCodecScalability() throws {
        let container = try makeContainer(taskCount: 10_000)
        let context = container.mainContext
        let export = BackupExportService(context: context)

        var backup: SelnoBackup?
        measureMilliseconds("backup export map 10k tasks", iterations: 2) {
            backup = try? export.makeBackup(now: base)
        }
        guard let backup else {
            XCTFail("backup export failed")
            return
        }

        var data: Data?
        measureMilliseconds("backup JSON encode 10k tasks") {
            data = try? BackupCodec.encode(backup)
        }
        guard let data else {
            XCTFail("backup encode failed")
            return
        }
        print("SELNO_PERF backup bytes=\(data.count)")

        measureMilliseconds("backup JSON decode + validate 10k tasks") {
            if let decoded = try? BackupCodec.decode(data) {
                _ = try? BackupCodec.validate(decoded)
            }
        }
    }

    // MARK: Helpers

    private func makeContainer(taskCount: Int) throws -> ModelContainer {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        for index in 0..<taskCount {
            let status: TaskStatus
            if index % 10 == 0 {
                status = .completed
            } else if index % 7 == 0 {
                status = .inProgress
            } else {
                status = .pending
            }
            let task = TodoTask(
                title: "Synthetic task \(index) 论文",
                notes: index % 11 == 0 ? "Synthetic notes \(index)" : "",
                status: status,
                importance: index % 5 == 0 ? .high : .normal,
                now: base.addingTimeInterval(Double(index))
            )
            if index % 2 == 0 {
                task.plannedAt = base.addingTimeInterval(Double(index % 60) * 3_600 + 86_400)
            }
            if index % 3 == 0 {
                task.dueAt = base.addingTimeInterval(Double(index % 45) * 86_400 + 43_200)
            }
            if index % 97 == 0 {
                task.archivedAt = base.addingTimeInterval(86_400)
            }
            context.insert(task)
        }
        try context.save()
        return container
    }

    private func measureMilliseconds(
        _ label: String,
        iterations: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () -> Void
    ) {
        body() // warm-up
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let formatted = samples.map { String(format: "%.2f", $0) }.joined(separator: ",")
        print("SELNO_PERF \(label) median_ms=\(String(format: "%.2f", median)) samples=[\(formatted)]")
        XCTAssertLessThan(median, 30_000, "\(label) exceeded a catastrophic 30 s ceiling", file: file, line: line)
    }
}