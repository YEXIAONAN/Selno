import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct Phase05FilterTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        value.locale = Locale(identifier: "zh_CN")
        value.firstWeekday = 2
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21,
                                           hour: 12, minute: 30))!
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        return (container, container.mainContext)
    }

    private func ids(_ tasks: [TodoTask]) -> Set<UUID> {
        Set(tasks.map(\.id))
    }

    private func matched(_ filter: TaskFilterExpression, _ tasks: [TodoTask]) -> [TodoTask] {
        tasks.filter { filter.matches($0, now: now, calendar: calendar) }
    }

    // MARK: - Set dimensions

    @Test func valuesWithinOneDimensionAreOredAndDimensionsAreAnded() throws {
        let (container, context) = try makeContext()
        _ = container
        let pendingHigh = TodoTask(title: "待开始高", status: .pending, importance: .high)
        let pendingLow = TodoTask(title: "待开始低", status: .pending, importance: .low)
        let activeHigh = TodoTask(title: "进行中高", status: .inProgress, importance: .high)
        let doneHigh = TodoTask(title: "完成高", status: .completed, importance: .high)
        let doneLow = TodoTask(title: "完成低", status: .completed, importance: .low)
        let all = [pendingHigh, pendingLow, activeHigh, doneHigh, doneLow]
        for task in all { context.insert(task) }
        try context.save()

        let active = TaskFilterExpression(statuses: [
            TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue
        ])
        #expect(ids(matched(active, all)) == ids([pendingHigh, pendingLow, activeHigh]))

        let important = TaskFilterExpression(importances: [
            TaskImportance.high.rawValue, TaskImportance.low.rawValue
        ])
        #expect(ids(matched(important, all)) == ids(all))

        let lowOrHighPending = TaskFilterExpression(
            statuses: [TaskStatus.pending.rawValue, TaskStatus.completed.rawValue],
            importances: [TaskImportance.low.rawValue]
        )
        #expect(ids(matched(lowOrHighPending, all)) == ids([pendingLow, doneLow]))

        // An empty dimension is unrestricted; it never excludes everything.
        #expect(matched(.unrestricted, all).count == all.count)
    }

    @Test func projectAndTagDimensionsCombineWithUnassignedAndLegacyCategory() throws {
        let (container, context) = try makeContext()
        _ = container
        let projectA = TodoProject(name: "项目 A")
        let projectB = TodoProject(name: "项目 B")
        let tagA = TaskCategory(name: "标签 A", symbolName: "tag", colorHex: "#3F6852", sortOrder: 1)
        let tagB = TaskCategory(name: "标签 B", symbolName: "tag", colorHex: "#A33E3C", sortOrder: 2)
        let legacy = TaskCategory(name: "旧分类", symbolName: "book", colorHex: "#808080", sortOrder: 3)
        context.insert(projectA)
        context.insert(projectB)
        context.insert(tagA)
        context.insert(tagB)
        context.insert(legacy)

        let inA = TodoTask(title: "A", importance: .high)
        inA.project = projectA
        inA.tags = [tagA]
        inA.category = tagA
        let inB = TodoTask(title: "B", importance: .normal)
        inB.project = projectB
        inB.tags = [tagB]
        inB.category = tagB
        let unassigned = TodoTask(title: "无项目", importance: .low)
        unassigned.category = legacy
        let all = [inA, inB, unassigned]
        for task in all { context.insert(task) }
        try context.save()

        let bothProjects = TaskFilterExpression(projectIDs: [projectA.id, projectB.id])
        #expect(ids(matched(bothProjects, all)) == ids([inA, inB]))

        let withUnassigned = TaskFilterExpression(
            projectIDs: [projectA.id, projectB.id], includeUnassignedProject: true
        )
        #expect(ids(matched(withUnassigned, all)) == ids(all))

        let onlyUnassigned = TaskFilterExpression(includeUnassignedProject: true)
        #expect(ids(matched(onlyUnassigned, all)) == [unassigned.id])

        let bothTags = TaskFilterExpression(tagIDs: [tagA.id, tagB.id])
        #expect(ids(matched(bothTags, all)) == ids([inA, inB]))

        let legacyTag = TaskFilterExpression(tagIDs: [legacy.id])
        #expect(ids(matched(legacyTag, all)) == [unassigned.id])

        let projectAndTag = TaskFilterExpression(
            importances: [TaskImportance.high.rawValue],
            projectIDs: [projectA.id, projectB.id],
            tagIDs: [tagA.id]
        )
        #expect(ids(matched(projectAndTag, all)) == [inA.id])
    }

    @Test func searchCoversTitleNotesProjectTagsAndLegacyCategory() throws {
        let (container, context) = try makeContext()
        _ = container
        let project = TodoProject(name: "毕业设计", notes: "论文与答辩")
        let tag = TaskCategory(name: "学习", symbolName: "book", colorHex: "#3F6852", sortOrder: 1)
        tag.emoji = "📚"
        let legacy = TaskCategory(name: "旧分类", symbolName: "tag", colorHex: "#808080", sortOrder: 2)
        context.insert(project)
        context.insert(tag)
        context.insert(legacy)

        let paper = TodoTask(title: "撰写论文")
        paper.notes = "检查引用格式"
        paper.project = project
        paper.tags = [tag]
        paper.category = tag
        let groceries = TodoTask(title: "买菜")
        groceries.category = legacy
        context.insert(paper)
        context.insert(groceries)
        try context.save()

        func search(_ text: String) -> Set<UUID> {
            ids(matched(TaskFilterExpression(searchText: text), [paper, groceries]))
        }
        #expect(search("论文") == [paper.id])
        #expect(search("引用") == [paper.id])
        #expect(search("毕业") == [paper.id])
        #expect(search("📚") == [paper.id])
        #expect(search("旧分类") == [groceries.id])
        #expect(search("  ") == ids([paper, groceries]))
        #expect(search("不存在的词").isEmpty)
    }

    // MARK: - Dates

    @Test func dateRangesUseTheProvidedCalendarAndTimeZone() throws {
        let (container, context) = try makeContext()
        _ = container
        let todayStart = calendar.startOfDay(for: now)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: todayStart))

        let plannedToday = TodoTask(title: "今天计划")
        plannedToday.plannedAt = todayStart.addingTimeInterval(9 * 3_600)
        let dueTomorrow = TodoTask(title: "明天截止")
        dueTomorrow.dueAt = tomorrow.addingTimeInterval(9 * 3_600)
        let both = TodoTask(title: "两者都有")
        both.plannedAt = todayStart.addingTimeInterval(10 * 3_600)
        both.dueAt = tomorrow.addingTimeInterval(18 * 3_600)
        let all = [plannedToday, dueTomorrow, both]
        for task in all { context.insert(task) }
        try context.save()

        let todayByDue = TaskFilterExpression(dateField: .due, dateRange: .today)
        #expect(matched(todayByDue, all).isEmpty)

        let todayByPlanned = TaskFilterExpression(dateField: .planned, dateRange: .today)
        #expect(ids(matched(todayByPlanned, all)) == ids([plannedToday, both]))

        let todayByAny = TaskFilterExpression(dateField: .any, dateRange: .today)
        #expect(ids(matched(todayByAny, all)) == ids([plannedToday, both]))

        let nextThree = TaskFilterExpression(dateField: .due, dateRange: .next3Days)
        #expect(ids(matched(nextThree, all)) == ids([dueTomorrow, both]))

        let nextSeven = TaskFilterExpression(dateField: .due, dateRange: .next7Days)
        #expect(ids(matched(nextSeven, all)) == ids([dueTomorrow, both]))

        let custom = TaskFilterExpression(
            dateField: .due, dateRange: .custom,
            customStart: todayStart, customEnd: tomorrow
        )
        #expect(ids(matched(custom, all)) == ids([dueTomorrow, both]))

        // The same absolute instant belongs to a different local day in UTC.
        let shanghai = calendar
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        utc.locale = Locale(identifier: "en_US_POSIX")
        let lateNight = try #require(shanghai.date(from: DateComponents(
            year: 2026, month: 10, day: 22, hour: 0, minute: 30
        )))
        let edge = TodoTask(title: "跨时区")
        edge.dueAt = lateNight
        context.insert(edge)
        try context.save()

        let filter = TaskFilterExpression(dateField: .due, dateRange: .today)
        #expect(!filter.matches(edge, now: now, calendar: shanghai))
        #expect(filter.matches(edge, now: now, calendar: utc))
    }

    @Test func dueAndPlannedStatesUseActiveStatusAndHalfOpenBoundaries() throws {
        let (container, context) = try makeContext()
        _ = container
        let today = calendar.startOfDay(for: now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let threeDays = try #require(calendar.date(byAdding: .day, value: 3, to: today))

        let overdue = TodoTask(title: "逾期")
        overdue.dueAt = yesterday
        let completedOverdue = TodoTask(title: "完成但过期", status: .completed)
        completedOverdue.dueAt = yesterday
        let dueNow = TodoTask(title: "今天截止")
        dueNow.dueAt = today
        let noDue = TodoTask(title: "没有截止")
        let planned = TodoTask(title: "有计划")
        planned.plannedAt = today
        let plannedRange = TodoTask(title: "计划区间")
        plannedRange.plannedStartAt = today.addingTimeInterval(3_600)
        let unplannedCompleted = TodoTask(title: "完成无计划", status: .completed)
        let backlog = [overdue, completedOverdue, dueNow, noDue, planned,
                       plannedRange, unplannedCompleted]
        for task in backlog { context.insert(task) }
        try context.save()

        #expect(ids(matched(TaskFilterExpression(dueState: .hasDue), backlog))
                == ids([overdue, completedOverdue, dueNow]))
        #expect(ids(matched(TaskFilterExpression(dueState: .noDue), backlog))
                == ids([noDue, planned, plannedRange, unplannedCompleted]))
        #expect(ids(matched(TaskFilterExpression(dueState: .overdue), backlog))
                == [overdue.id])
        #expect(ids(matched(TaskFilterExpression(dueState: .notOverdue), backlog))
                == ids([dueNow]))

        #expect(ids(matched(TaskFilterExpression(plannedState: .has), backlog))
                == ids([planned, plannedRange]))
        #expect(ids(matched(TaskFilterExpression(plannedState: .missing), backlog))
                == ids([overdue, completedOverdue, dueNow, noDue, unplannedCompleted]))

        // The 3-day window is [today, today + 3), so an item exactly on the
        // boundary is excluded and intervals never overlap.
        let atBoundary = TodoTask(title: "边界")
        atBoundary.dueAt = threeDays
        let inside = TodoTask(title: "窗口内")
        inside.dueAt = threeDays.addingTimeInterval(-1)
        context.insert(atBoundary)
        context.insert(inside)
        try context.save()
        let window = TaskFilterExpression(dateField: .due, dateRange: .next3Days)
        #expect(ids(matched(window, [atBoundary, inside])) == [inside.id])
    }

    @Test func archivedTasksAreHiddenUntilExplicitlyIncluded() throws {
        let (container, context) = try makeContext()
        _ = container
        let active = TodoTask(title: "活动")
        active.dueAt = now
        let archived = TodoTask(title: "归档", status: .completed)
        archived.archivedAt = now
        archived.dueAt = now
        context.insert(active)
        context.insert(archived)
        try context.save()

        let filter = TaskFilterExpression(dateField: .due, dateRange: .today)
        #expect(ids(matched(filter, [active, archived])) == [active.id])
        var included = filter
        included.includeArchived = true
        #expect(ids(matched(included, [active, archived])) == ids([active, archived]))
    }

    // MARK: - Sanitizing and validation

    @Test func sanitizationDropsUnknownValuesAndRepairsIncompleteRanges() {
        let reversed = TaskFilterExpression(
            statuses: [TaskStatus.pending.rawValue, "futureStatus"],
            importances: [TaskImportance.high.rawValue, "futureImportance"],
            dateField: .due, dateRange: .custom,
            customStart: now.addingTimeInterval(86_400),
            customEnd: now,
            searchText: "  报告  "
        )
        let sanitized = reversed.sanitized()
        #expect(sanitized.statuses == [TaskStatus.pending.rawValue])
        #expect(sanitized.importances == [TaskImportance.high.rawValue])
        #expect(sanitized.dateRange == .any)
        #expect(sanitized.customStart == nil)
        #expect(sanitized.customEnd == nil)
        #expect(sanitized.searchText == "报告")
        #expect(sanitized.isUnrestricted == false)

        let nonCustom = TaskFilterExpression(
            dateRange: .today, customStart: now, customEnd: now.addingTimeInterval(10)
        )
        #expect(nonCustom.sanitized().customStart == nil)
        #expect(nonCustom.sanitized().customEnd == nil)

        let empty = TaskFilterExpression(searchText: "   ").sanitized()
        #expect(empty.isUnrestricted)
    }

    @Test func validationRejectsMissingOrReversedCustomRanges() {
        #expect(throws: TaskFilterError.incompleteCustomRange) {
            try TaskFilterExpression(dateRange: .custom, customStart: now).validated()
        }
        #expect(throws: TaskFilterError.incompleteCustomRange) {
            try TaskFilterExpression(dateRange: .custom, customEnd: now).validated()
        }
        #expect(throws: TaskFilterError.reversedCustomRange) {
            try TaskFilterExpression(dateRange: .custom,
                                     customStart: now.addingTimeInterval(10),
                                     customEnd: now).validated()
        }
        let valid = TaskFilterExpression(dateRange: .custom, customStart: now, customEnd: now)
        #expect((try? valid.validated())?.dateRange == .custom)
        // Non-custom ranges ignore stale dates instead of failing.
        let stale = TaskFilterExpression(dateRange: .today, customStart: now.addingTimeInterval(10))
        #expect((try? stale.validated())?.dateRange == .today)
    }

    @Test func codableRoundTripsDeterministicallyAndToleratesUnknownFields() throws {
        let filter = TaskFilterExpression(
            statuses: [TaskStatus.cancelled.rawValue, TaskStatus.pending.rawValue],
            importances: [TaskImportance.low.rawValue, TaskImportance.high.rawValue],
            projectIDs: [UUID(), UUID()],
            includeUnassignedProject: true,
            tagIDs: [UUID()],
            dateField: .planned, dateRange: .custom,
            customStart: now, customEnd: now.addingTimeInterval(86_400),
            dueState: .notOverdue, plannedState: .has,
            includeArchived: true, searchText: "材料"
        )
        let first = try #require(WorkspaceCoding.encode(filter))
        let second = try #require(WorkspaceCoding.encode(filter))
        #expect(first == second)
        #expect(WorkspaceCoding.decode(TaskFilterExpression.self, from: first) == filter)

        let json = """
        {
          "statuses": ["pending", "futureStatus"],
          "importances": ["futureImportance"],
          "dateField": "futureField",
          "dateRange": "futureRange",
          "dueState": "futureDue",
          "plannedState": "futurePresence",
          "unknownDimension": [1, 2, 3]
        }
        """
        let decoded = try #require(WorkspaceCoding.decode(TaskFilterExpression.self,
                                                          from: Data(json.utf8)))
        #expect(decoded.statuses == ["pending", "futureStatus"])
        #expect(decoded.importances == ["futureImportance"])
        #expect(decoded.dateField == .any)
        #expect(decoded.dateRange == .any)
        #expect(decoded.dueState == .any)
        #expect(decoded.plannedState == .any)

        let sanitized = decoded.sanitized()
        #expect(sanitized.statuses == ["pending"])
        #expect(sanitized.importances.isEmpty)
        #expect(WorkspaceCoding.filter(from: nil).isUnrestricted)
    }

    @Test func intervalConstructionIsInclusiveOfTheEndDateOnlyInsideTheDay() throws {
        let today = calendar.startOfDay(for: now)
        let week = try #require(TaskFilterEngine.interval(
            for: .thisWeek, customStart: nil, customEnd: nil, now: now, calendar: calendar
        ))
        let month = try #require(TaskFilterEngine.interval(
            for: .thisMonth, customStart: nil, customEnd: nil, now: now, calendar: calendar
        ))
        #expect(calendar.component(.day, from: week.start) == 19)
        #expect(calendar.component(.day, from: week.end) == 26)
        #expect(calendar.component(.day, from: month.start) == 1)
        #expect(calendar.component(.month, from: month.end) == 11)
        #expect(TaskFilterEngine.interval(for: .any, customStart: nil, customEnd: nil,
                                          now: now, calendar: calendar) == nil)

        let end = today.addingTimeInterval(86_400 * 2)
        let custom = try #require(TaskFilterEngine.interval(
            for: .custom, customStart: today, customEnd: end,
            now: now, calendar: calendar
        ))
        #expect(custom.start == today)
        #expect(calendar.dateComponents([.day], from: custom.start, to: custom.end).day == 3)
        #expect(TaskFilterEngine.contains(custom, today))
        #expect(TaskFilterEngine.contains(custom, custom.end.addingTimeInterval(-1)))
        #expect(!TaskFilterEngine.contains(custom, custom.end))

        #expect(TaskFilterEngine.requestedInterval(for: TaskFilterExpression(dateRange: .next7Days),
                                                   now: now, calendar: calendar) != nil)
        #expect(TaskFilterEngine.requestedInterval(for: .unrestricted,
                                                   now: now, calendar: calendar) == nil)
    }

    @Test func summariesDescribeEveryActiveDimension() {
        let projectID = UUID()
        let tagID = UUID()
        let filter = TaskFilterExpression(
            statuses: [TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue],
            importances: [TaskImportance.high.rawValue],
            projectIDs: [projectID], includeUnassignedProject: true,
            tagIDs: [tagID],
            dateField: .due, dateRange: .next3Days,
            dueState: .hasDue, plannedState: .missing,
            includeArchived: true, searchText: "报告"
        )
        let summary = filter.summary(projectNames: [projectID: "毕业设计"],
                                     tagNames: [tagID: "学习"])
        #expect(summary.contains("待开始、进行中"))
        #expect(summary.contains("重要"))
        #expect(summary.contains("毕业设计"))
        #expect(summary.contains("含未归属项目"))
        #expect(summary.contains("学习"))
        #expect(summary.contains("截止日期 · 未来 3 天"))
        #expect(summary.contains("有截止日期"))
        #expect(summary.contains("无计划日期"))
        #expect(summary.contains("包含已归档"))
        #expect(summary.contains("搜索“报告”"))
        #expect(TaskFilterExpression.unrestricted.summary() == "全部数据")
    }
}