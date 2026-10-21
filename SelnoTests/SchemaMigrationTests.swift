import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct SchemaMigrationTests {
    @Test func originalPhase01DiskStoreMigratesWithoutLosingExistingData() throws {
        let original = try Phase01Fixture.data()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelnoMigration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Selno.store")
        try original.write(to: url)
        let originalDate = Date(timeIntervalSince1970: 1_790_000_000)
        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext
            let tasks = try context.fetch(FetchDescriptor<TodoTask>())
            let task = try #require(tasks.first)
            #expect(tasks.count == 1)
            #expect(task.id.uuidString == "02000000-0000-0000-0000-000000000002")
            #expect(task.title == "Phase 01 保留的任务")
            #expect(task.notes == "迁移不能丢失")
            #expect(task.status == .completed)
            #expect(task.importance == .high)
            #expect(task.completedAt == originalDate)
            #expect(task.plannedAt == originalDate)
            #expect(task.plannedStartAt == originalDate.addingTimeInterval(-3600))
            #expect(task.dueAt == originalDate.addingTimeInterval(86400))
            #expect(task.project?.name == "Phase 01 原有项目")
            #expect(task.project?.tasks?.first?.id == task.id)
            #expect(task.category != nil)
            #expect(task.orderedSteps.first?.title == "保留子任务")
            #expect(task.orderedSteps.first?.isCompleted == true)
            try DefaultDataSeeder.seedIfNeeded(in: context)
            #expect(try context.fetchCount(FetchDescriptor<TaskCategory>()) == 5)
            #expect(try context.fetchCount(FetchDescriptor<SeedRecord>()) == 1)
            var draft = CalendarEventDraft(date: originalDate, calendar: .current)
            draft.title = "V2 新增日程"
            try CalendarEventService(context: context, calendar: .current).create(draft: draft)
        }
        try autoreleasepool {
            let reopened = try PersistenceController.makeContainer(storage: .disk(url))
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<TodoTask>()) == 1)
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<CalendarEvent>()) == 1)
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<TaskCategory>()) == 5)
        }
    }
}
