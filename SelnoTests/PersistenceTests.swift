import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct PersistenceTests {
    @Test func defaultCategoriesAreSeededOnceAndNotDetectedByName() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        context.insert(TaskCategory(name: "学习", symbolName: "tag", colorHex: "#808080", sortOrder: 20))
        try context.save()
        try DefaultDataSeeder.seedIfNeeded(in: context)
        try DefaultDataSeeder.seedIfNeeded(in: context)
        var categories = try context.fetch(FetchDescriptor<TaskCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(categories.count == 6)
        #expect(Array(categories.prefix(5)).map(\.name) == ["学习", "竞赛", "校园", "开发", "生活"])
        #expect(try context.fetchCount(FetchDescriptor<SeedRecord>()) == 1)
        let renamed = try #require(categories.first)
        renamed.name = "已重命名"
        renamed.isArchived = true
        let removed = categories.remove(at: 1)
        let removedID = removed.id
        context.delete(removed)
        try context.save()
        try DefaultDataSeeder.seedIfNeeded(in: context)
        let remaining = try context.fetch(FetchDescriptor<TaskCategory>())
        #expect(remaining.count == 5)
        #expect(remaining.contains { $0.id == renamed.id && $0.name == "已重命名" && $0.isArchived })
        #expect(!remaining.contains { $0.id == removedID })
    }

    @Test func eachInMemoryContainerIsIsolatedAndNeverUsesProductionStore() throws {
        let first = try PersistenceController.makeContainer(storage: .inMemory)
        let second = try PersistenceController.makeContainer(storage: .inMemory)
        #expect(first.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(second.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(first.mainContext.autosaveEnabled == false)
        try TaskService(context: first.mainContext).createTask(title: "只存在于第一个测试库")
        try DefaultDataSeeder.seedIfNeeded(in: first.mainContext)
        #expect(try second.mainContext.fetchCount(FetchDescriptor<TodoTask>()) == 0)
        #expect(try second.mainContext.fetchCount(FetchDescriptor<TaskCategory>()) == 0)
        try DefaultDataSeeder.seedIfNeeded(in: second.mainContext)
        #expect(try second.mainContext.fetchCount(FetchDescriptor<TaskCategory>()) == 5)
    }

    @Test func diskStorePreservesCompletedTaskRelationshipsAndSeedAcrossContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Selno.store")
        #expect(url != (try PersistenceController.localStoreURL()))
        let completion = Date(timeIntervalSince1970: 1_790_003_000)
        let taskID: UUID = try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            #expect(container.configurations.allSatisfy { !$0.isStoredInMemoryOnly })
            let context = container.mainContext
            try DefaultDataSeeder.seedIfNeeded(in: context)
            let project = TodoProject(name: "竞赛")
            context.insert(project)
            let service = TaskService(context: context)
            let task = try service.createTask(title: "准备人工智能竞赛材料")
            task.project = project
            task.category = try context.fetch(FetchDescriptor<TaskCategory>()).first
            task.plannedAt = completion
            task.dueAt = completion.addingTimeInterval(86_400)
            let step = try service.addStep(title: "阅读要求", to: task)
            try service.toggleStepCompletion(step, now: completion)
            try service.toggleCompletion(task, now: completion)
            return task.id
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        try autoreleasepool {
            let reopened = try PersistenceController.makeContainer(storage: .disk(url))
            try DefaultDataSeeder.seedIfNeeded(in: reopened.mainContext)
            let tasks = try reopened.mainContext.fetch(FetchDescriptor<TodoTask>())
            let task = try #require(tasks.first)
            #expect(tasks.count == 1)
            #expect(task.id == taskID)
            #expect(task.title == "准备人工智能竞赛材料")
            #expect(task.status == .completed)
            #expect(task.completedAt == completion)
            #expect(task.project?.name == "竞赛")
            #expect(task.category != nil)
            #expect(task.project?.tasks?.first?.id == task.id)
            #expect(task.orderedSteps.first?.isCompleted == true)
            #expect(task.orderedSteps.first?.parentTask?.id == task.id)
            #expect(task.plannedAt == completion)
            #expect(task.dueAt == completion.addingTimeInterval(86_400))
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<TaskCategory>()) == 5)
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<SeedRecord>()) == 1)
        }
    }

    @Test func invalidStoreDoesNotDeleteExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoInvalidStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Selno.store")
        let contents = Data("preserve-existing-data".utf8)
        try contents.write(to: url)
        #expect(throws: (any Error).self) {
            try PersistenceController.makeContainer(storage: .disk(url))
        }
        #expect(try Data(contentsOf: url) == contents)
    }
}
