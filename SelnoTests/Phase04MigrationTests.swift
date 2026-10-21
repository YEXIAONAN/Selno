import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct Phase04MigrationTests {
    private let base = Date(timeIntervalSince1970: 1_790_004_000.125)

    /// Builds a genuine Phase 03 store with the frozen V3 model definitions, then
    /// opens it through the shipping V4 container so SwiftData performs a real
    /// V3→V4 lightweight migration rather than a same-schema reopen.
    @Test func frozenV3DiskStoreMigratesToV4WithoutLosingDataAndAcceptsReminders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase04Migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Selno.store")

        let taskID = UUID()
        let projectID = UUID()
        let categoryID = UUID()
        let stepID = UUID()
        let milestoneID = UUID()
        let eventID = UUID()
        let templateID = UUID()

        try autoreleasepool {
            let schema = Schema(versionedSchema: SelnoSchemaV3.self)
            let configuration = ModelConfiguration("Selno", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.autosaveEnabled = false
            let context = container.mainContext

            let project = SelnoSchemaV3.TodoProject(id: projectID, name: "V3 项目 🌿", notes: "迁移保留", now: base)
            let category = SelnoSchemaV3.TaskCategory(id: categoryID, name: "V3 分类", symbolName: "book",
                                                      colorHex: "#3F6852", sortOrder: 1, now: base)
            category.emoji = "📚"
            let task = SelnoSchemaV3.TodoTask(id: taskID, title: "V3 任务", notes: "不能丢失",
                                              status: .pending, importance: .high, now: base)
            task.plannedAt = base.addingTimeInterval(3_600)
            task.dueAt = base.addingTimeInterval(86_400)
            task.project = project
            task.category = category
            task.tags = [category]

            let step = SelnoSchemaV3.TaskStep(id: stepID, title: "V3 子任务", sortOrder: 0, now: base)
            step.isCompleted = true
            step.completedAt = base.addingTimeInterval(600)
            let milestone = SelnoSchemaV3.TaskMilestone(fieldID: UUID(), title: "报名截止",
                                                       semantic: MilestoneSemantic.registrationEnds.rawValue,
                                                       date: base.addingTimeInterval(86_400))
            milestone.id = milestoneID
            milestone.isOnCalendar = true
            milestone.reminderLeadMinutes = 1_440
            milestone.reminderStateRaw = TaskReminderState.scheduled.rawValue

            let template = SelnoSchemaV3.TaskTemplate(name: "V3 模板 🏫", emoji: "🏫")
            template.id = templateID
            let instance = try SelnoSchemaV3.TaskTemplateInstance(
                templateID: templateID, name: template.name, revision: 2,
                payload: TemplatePayload(definition: .init())
            )
            task.templateInstance = instance

            let event = SelnoSchemaV3.CalendarEvent(id: eventID, title: "V3 日程", notes: "保留",
                                                   startsAt: base.addingTimeInterval(10_000),
                                                   endsAt: base.addingTimeInterval(13_600),
                                                   isAllDay: false, location: "南宁", now: base)

            context.insert(project)
            context.insert(category)
            context.insert(task)
            context.insert(step)
            context.insert(milestone)
            context.insert(template)
            context.insert(instance)
            context.insert(event)
            step.parentTask = task
            milestone.task = task
            try context.save()
        }

        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext

            let tasks = try context.fetch(FetchDescriptor<TodoTask>())
            #expect(tasks.count == 1)
            let task = try #require(tasks.first)
            #expect(task.id == taskID)
            #expect(task.title == "V3 任务")
            #expect(task.notes == "不能丢失")
            #expect(task.importance == .high)
            #expect(task.plannedAt == base.addingTimeInterval(3_600))
            #expect(task.dueAt == base.addingTimeInterval(86_400))
            #expect(task.archivedAt == nil)
            #expect(task.project?.id == projectID)
            #expect(task.project?.name == "V3 项目 🌿")
            #expect(task.category?.id == categoryID)
            #expect(task.tags?.map(\.id) == [categoryID])
            #expect(task.orderedSteps.map(\.id) == [stepID])
            #expect(task.orderedSteps[0].isCompleted)
            #expect(task.orderedSteps[0].completedAt == base.addingTimeInterval(600))
            #expect(task.milestones?.map(\.id) == [milestoneID])
            #expect(task.milestones?.first?.reminderLeadMinutes == 1_440)
            #expect(task.templateInstance?.templateRevision == 2)
            #expect(task.templateInstance?.templateName == "V3 模板 🏫")

            #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskReminder>()) == 0)

            let reminder = TaskReminder(taskID: taskID, kind: .due, leadMinutes: 1_440, now: base)
            context.insert(reminder)
            try context.save()
            #expect(reminder.notificationID.hasPrefix("selno.task."))
        }

        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext
            let reminder = try #require(try context.fetch(FetchDescriptor<TaskReminder>()).first)
            #expect(reminder.taskID == taskID)
            #expect(reminder.kind == .due)
            #expect(reminder.leadMinutes == 1_440)
            let task = try #require(try context.fetch(FetchDescriptor<TodoTask>()).first)
            #expect(task.title == "V3 任务")
            #expect(task.isArchived == false)
        }
    }

    @Test func migratedV3StoreExportsAndRestoresToACleanV4Store() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase04MigrationBackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("V3.store")
        let targetURL = root.appendingPathComponent("V4.store")

        try autoreleasepool {
            let schema = Schema(versionedSchema: SelnoSchemaV3.self)
            let configuration = ModelConfiguration("Selno", schema: schema, url: sourceURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.autosaveEnabled = false
            let task = SelnoSchemaV3.TodoTask(title: "从 V3 导出的任务", now: base)
            container.mainContext.insert(task)
            try container.mainContext.save()
        }

        var document: BackupDocument!
        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(sourceURL))
            document = try BackupExportService(context: container.mainContext).makeDocument(now: base)
            #expect(document.counts.tasks == 1)
        }

        #expect(document.backup.data.tasks.first?.title == "从 V3 导出的任务")

        try autoreleasepool {
            let target = try PersistenceController.makeContainer(storage: .disk(targetURL))
            _ = try BackupImportService(context: target.mainContext,
                                        backupDirectory: root.appendingPathComponent("Backups"))
                .apply(document: document, mode: .replace, now: base)
        }

        try autoreleasepool {
            let reopened = try PersistenceController.makeContainer(storage: .disk(targetURL))
            let task = try #require(try reopened.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
            #expect(task.title == "从 V3 导出的任务")
            #expect(task.archivedAt == nil)
        }
    }
}