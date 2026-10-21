import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct Phase05MigrationTests {
    private let base = Date(timeIntervalSince1970: 1_790_004_000.125)

    /// Builds a genuine Phase 04 store using the frozen V4 schema. V5 is purely
    /// additive, so opening the same file through the shipping container makes
    /// SwiftData perform a real V4→V5 lightweight migration.
    @Test func frozenV4DiskStoreMigratesAndSeedsOneGlobalWorkspaceWithoutLosingData() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase05Migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Selno.store")

        let taskID = UUID()
        let projectID = UUID()
        let categoryID = UUID()
        let eventID = UUID()
        let reminderID = UUID()
        let templateID = UUID()
        let milestoneID = UUID()
        let due = base.addingTimeInterval(2 * 86_400)

        try autoreleasepool {
            let schema = Schema(versionedSchema: SelnoSchemaV4.self)
            let configuration = ModelConfiguration("Selno", schema: schema, url: url,
                                                   cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.autosaveEnabled = false
            let context = container.mainContext

            let project = TodoProject(id: projectID, name: "V4 项目 🌿", notes: "迁移保留", now: base)
            let category = TaskCategory(id: categoryID, name: "V4 分类", symbolName: "book",
                                        colorHex: "#3F6852", sortOrder: 1, now: base)
            category.emoji = "📚"
            let task = TodoTask(id: taskID, title: "V4 任务", notes: "不能丢失",
                                status: .inProgress, importance: .high, now: base)
            task.updatedAt = base.addingTimeInterval(120)
            task.plannedStartAt = base.addingTimeInterval(3_600)
            task.plannedAt = base.addingTimeInterval(7_200)
            task.dueAt = due
            task.project = project
            task.category = category
            task.tags = [category]

            let template = TaskTemplate(name: "V4 模板", emoji: "🏫")
            template.id = templateID
            let milestone = TaskMilestone(fieldID: UUID(), title: "V4 节点",
                                          semantic: MilestoneSemantic.date.rawValue,
                                          date: due)
            milestone.id = milestoneID
            milestone.isOnCalendar = true
            milestone.reminderLeadMinutes = 1_440

            let event = CalendarEvent(id: eventID, title: "V4 日程", notes: "保留",
                                      startsAt: base.addingTimeInterval(10_000),
                                      endsAt: base.addingTimeInterval(13_600),
                                      isAllDay: false, location: "南宁", now: base)
            let reminder = TaskReminder(id: reminderID, taskID: taskID, kind: .due,
                                        leadMinutes: 120, now: base)

            context.insert(project)
            context.insert(category)
            context.insert(template)
            context.insert(task)
            context.insert(milestone)
            context.insert(event)
            context.insert(reminder)
            milestone.task = task
            try context.save()
        }

        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext

            // Migration itself must not invent user configuration; the app's
            // launch path is responsible for seeding once.
            #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<WorkspaceModule>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<SavedTaskView>()) == 0)

            let tasks = try context.fetch(FetchDescriptor<TodoTask>())
            #expect(tasks.count == 1)
            let task = try #require(tasks.first)
            #expect(task.id == taskID)
            #expect(task.title == "V4 任务")
            #expect(task.notes == "不能丢失")
            #expect(task.status == .inProgress)
            #expect(task.importance == .high)
            #expect(task.createdAt == base)
            #expect(task.updatedAt == base.addingTimeInterval(120))
            #expect(task.plannedStartAt == base.addingTimeInterval(3_600))
            #expect(task.plannedAt == base.addingTimeInterval(7_200))
            #expect(task.dueAt == due)
            #expect(task.project?.id == projectID)
            #expect(task.tags?.map(\.id) == [categoryID])
            #expect(task.category?.id == categoryID)
            #expect(task.milestones?.map(\.id) == [milestoneID])
            #expect(task.milestones?.first?.isOnCalendar == true)
            #expect(task.milestones?.first?.reminderLeadMinutes == 1_440)
            #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskReminder>()) == 1)

            try WorkspaceSeeder.seedIfNeeded(in: context, now: base)
            let global = try #require(try WorkspaceService(context: context).globalWorkspace())
            #expect(global.name == DefaultWorkspaceFactory.globalName)
            #expect(global.isGlobal)
            #expect(global.orderedModules.count == DefaultWorkspaceFactory.globalSpecs.count)
            #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<WorkspaceModule>())
                    == DefaultWorkspaceFactory.globalSpecs.count)

            // Seeding is configuration-only and must not disturb migrated rows.
            #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TodoProject>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskCategory>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskReminder>()) == 1)

            try WorkspaceSeeder.seedIfNeeded(in: context, now: base.addingTimeInterval(60))
            #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<WorkspaceModule>())
                    == DefaultWorkspaceFactory.globalSpecs.count)
        }

        // A second real launch reopens the migrated store and seeds again.
        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext
            try WorkspaceSeeder.seedIfNeeded(in: context, now: base.addingTimeInterval(120))

            #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<WorkspaceModule>())
                    == DefaultWorkspaceFactory.globalSpecs.count)
            let global = try #require(try WorkspaceService(context: context).globalWorkspace())
            #expect(global.isGlobal)
            #expect(global.orderedModules.compactMap(\.kind)
                    == DefaultWorkspaceFactory.globalSpecs.map(\.kind))

            let task = try #require(try context.fetch(FetchDescriptor<TodoTask>()).first)
            #expect(task.id == taskID)
            #expect(task.title == "V4 任务")
            #expect(task.dueAt == due)
            #expect(task.project?.name == "V4 项目 🌿")
            #expect(task.tags?.map(\.name) == ["V4 分类"])

            let reminder = try #require(try context.fetch(FetchDescriptor<TaskReminder>()).first)
            #expect(reminder.id == reminderID)
            #expect(reminder.taskID == taskID)
            #expect(reminder.kind == .due && reminder.leadMinutes == 120)
        }
    }

    @Test func migratedV4StoreExportsV2BackupAndRoundTripsTheSeededWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase05MigrationBackup-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("V4.store")
        let backups = root.appendingPathComponent("Backups", isDirectory: true)

        try autoreleasepool {
            let schema = Schema(versionedSchema: SelnoSchemaV4.self)
            let configuration = ModelConfiguration("Selno", schema: schema, url: sourceURL,
                                                   cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.autosaveEnabled = false
            let task = TodoTask(title: "从 V4 导出的任务", now: base)
            task.dueAt = base.addingTimeInterval(86_400)
            container.mainContext.insert(task)
            try container.mainContext.save()
        }

        var document: BackupDocument!
        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(sourceURL))
            try WorkspaceSeeder.seedIfNeeded(in: container.mainContext, now: base)
            document = try BackupExportService(context: container.mainContext)
                .makeDocument(now: base)
            #expect(document.backup.schemaVersion == 2)
            #expect(document.counts.tasks == 1)
            #expect(document.counts.workspaces == 1)
            #expect(document.counts.modules == DefaultWorkspaceFactory.globalSpecs.count)
            #expect(document.backup.data.workspaces.first?.isGlobal == true)
            #expect(document.backup.data.workspaces.first?.name
                    == DefaultWorkspaceFactory.globalName)
        }

        let encoded = try BackupCodec.encode(document.backup)
        let decoded = try BackupCodec.decode(encoded)
        try BackupCodec.validate(decoded)
        #expect(decoded.data.workspaces.count == 1)
        #expect(decoded.data.workspaces[0].modules.count
                == DefaultWorkspaceFactory.globalSpecs.count)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        _ = try BackupImportService(context: target.mainContext, backupDirectory: backups)
            .apply(document: BackupDocument(backup: decoded, fileName: "V4-v2.json"),
                   mode: .replace, now: base)

        let context = target.mainContext
        #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkspaceModule>())
                == DefaultWorkspaceFactory.globalSpecs.count)
        let global = try #require(try WorkspaceService(context: context).globalWorkspace())
        #expect(global.isGlobal)
        #expect(global.orderedModules.compactMap(\.kind)
                == DefaultWorkspaceFactory.globalSpecs.map(\.kind))
        let task = try #require(try context.fetch(FetchDescriptor<TodoTask>()).first)
        #expect(task.title == "从 V4 导出的任务")
    }

    @Test func storeWithExistingScenarioAndNoGlobalGainsGlobalOnFirstLaunch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase05MigrationScenario-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Selno.store")

        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext
            let scenario = Workspace(name: "旧场景", emoji: "🧪", accent: .plum,
                                     sortOrder: 7, isGlobal: false,
                                     filter: .unrestricted, now: base)
            context.insert(scenario)
            let module = WorkspaceModule(kind: .taskList, size: .medium, sortOrder: 3, now: base)
            context.insert(module)
            module.workspace = scenario
            try context.save()
        }

        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext
            try WorkspaceSeeder.seedIfNeeded(in: context, now: base.addingTimeInterval(30))
            let workspaces = try WorkspaceService(context: context).allWorkspaces()
            #expect(workspaces.count == 2)
            #expect(workspaces.first?.isGlobal == true)
            #expect(workspaces.last?.name == "旧场景")
            #expect(workspaces.last?.sortOrder == 1)
            #expect(workspaces.last?.orderedModules.count == 1)
        }
    }
}