import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct SelnoTests {
    @Test func createTrimsAndPersistsTaskWithInboxDefaults() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let task = try TaskService(context: container.mainContext)
            .createTask(title: "  准备人工智能竞赛材料 \n", now: now)
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let stored = try #require(tasks.first)
        #expect(tasks.count == 1)
        #expect(stored.id == task.id)
        #expect(stored.title == "准备人工智能竞赛材料")
        #expect(stored.status == .pending)
        #expect(stored.importance == .normal)
        #expect(stored.createdAt == now)
        #expect(stored.updatedAt == now)
        #expect(stored.completedAt == nil)
        #expect(stored.dueAt == nil)
        #expect(stored.plannedAt == nil)
        #expect(stored.plannedStartAt == nil)
        #expect(stored.project == nil)
        #expect(stored.category == nil)
        #expect(stored.isInInbox)
        #expect(!container.mainContext.hasChanges)
    }

    @Test func whitespaceTitleIsRejectedWithoutInserting() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = TaskService(context: container.mainContext)
        #expect(throws: TaskValidationError.self) { try service.createTask(title: " \n\t ") }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TodoTask>()) == 0)
    }

    @Test func updateSavesEditedFieldsAndKeepsPlannedAndDueDatesSeparate() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = TaskService(context: container.mainContext)
        let task = try service.createTask(title: "原始标题")
        let now = Date(timeIntervalSince1970: 1_790_000_100)
        var draft = TaskDraft(task: task)
        draft.title = "  新标题  "
        draft.notes = "报名材料"
        draft.importance = .high
        draft.plannedAt = Date(timeIntervalSince1970: 1_790_100_000)
        draft.dueAt = Date(timeIntervalSince1970: 1_790_200_000)
        try service.update(task, draft: draft, now: now)
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<TodoTask>()).first)
        #expect(stored.title == "新标题")
        #expect(stored.notes == "报名材料")
        #expect(stored.importance == .high)
        #expect(stored.plannedAt == draft.plannedAt)
        #expect(stored.dueAt == draft.dueAt)
        #expect(stored.updatedAt == now)
        #expect(!stored.isInInbox)
    }

    @Test func invalidEditLeavesOriginalTaskUnchanged() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = TaskService(context: container.mainContext)
        let task = try service.createTask(title: "保留标题")
        var draft = TaskDraft(task: task)
        draft.title = "\n "
        draft.notes = "不应写入"
        #expect(throws: TaskValidationError.self) { try service.update(task, draft: draft) }
        #expect(task.title == "保留标题")
        #expect(task.notes.isEmpty)
        #expect(!container.mainContext.hasChanges)
    }

    @Test(arguments: [TaskStatus.pending, .inProgress])
    func completionRecordsTimestampAndReopeningClearsIt(initialStatus: TaskStatus) throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = TaskService(context: container.mainContext)
        let task = try service.createTask(title: "竞赛材料")
        try service.setStatus(initialStatus, for: task)
        let completion = Date(timeIntervalSince1970: 1_790_001_000)
        try service.toggleCompletion(task, now: completion)
        #expect(task.status == .completed)
        #expect(task.completedAt == completion)
        #expect(task.updatedAt == completion)
        try service.setStatus(.completed, for: task, now: completion.addingTimeInterval(1))
        #expect(task.completedAt == completion)
        try service.toggleCompletion(task)
        #expect(task.status == .pending)
        #expect(task.completedAt == nil)
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<TodoTask>()).first)
        #expect(stored.statusRaw == "pending")
        #expect(stored.completedAt == nil)
    }

    @Test func cancellationRequiresAnExplicitStatusChangeToResume() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = TaskService(context: container.mainContext)
        let task = try service.createTask(title: "已取消事项")
        try service.setStatus(.cancelled, for: task)
        #expect(throws: TaskValidationError.self) { try service.toggleCompletion(task) }
        #expect(task.status == .cancelled)
        try service.setStatus(.inProgress, for: task)
        #expect(task.status == .inProgress)
        #expect(task.completedAt == nil)
    }

    @Test func projectAndCategoryRelationshipsSurviveDeletionWithoutDeletingTasks() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let project = TodoProject(name: "人工智能竞赛")
        let category = TaskCategory(name: "自定义", symbolName: "tag", colorHex: "#808080", sortOrder: 10)
        context.insert(project)
        context.insert(category)
        let task = try TaskService(context: context).createTask(title: "准备材料")
        task.project = project
        task.category = category
        try context.save()
        let verification = ModelContext(container)
        let storedProject = try #require(verification.fetch(FetchDescriptor<TodoProject>()).first)
        let storedCategory = try #require(verification.fetch(FetchDescriptor<TaskCategory>()).first)
        #expect(storedProject.tasks?.first?.id == task.id)
        #expect(storedCategory.tasks?.first?.id == task.id)
        #expect(!task.isInInbox)
        context.delete(project)
        context.delete(category)
        try context.save()
        let remaining = try #require(ModelContext(container).fetch(FetchDescriptor<TodoTask>()).first)
        #expect(remaining.id == task.id)
        #expect(remaining.project == nil)
        #expect(remaining.category == nil)
        #expect(remaining.isInInbox)
    }

    @Test func projectCanExistWithoutTasks() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        container.mainContext.insert(TodoProject(name: "独立项目"))
        try container.mainContext.save()
        let projects = try ModelContext(container).fetch(FetchDescriptor<TodoProject>())
        #expect(projects.count == 1)
        let taskCount = (projects.first?.tasks ?? []).count
        #expect(taskCount == 0)
    }

    @Test func stepsHaveStableOrderIndependentCompletionAndCascadeWithTask() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let service = TaskService(context: context)
        let task = try service.createTask(title: "准备材料")
        let first = try service.addStep(title: "  阅读规则 ", to: task)
        let second = try service.addStep(title: "提交材料", to: task)
        let completedAt = Date(timeIntervalSince1970: 1_790_002_000)
        try service.toggleStepCompletion(first, now: completedAt)
        #expect(first.title == "阅读规则")
        #expect(first.completedAt == completedAt)
        #expect(first.parentTask?.id == task.id)
        #expect(second.parentTask?.id == task.id)
        #expect(task.orderedSteps.map(\.id) == [first.id, second.id])
        #expect(task.completedStepCount == 1)
        #expect(task.status == .pending)
        #expect(second.isCompleted == false)
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<TodoTask>()).first)
        #expect(stored.orderedSteps.map(\.title) == ["阅读规则", "提交材料"])
        try service.toggleStepCompletion(first)
        #expect(first.completedAt == nil)
        context.delete(task)
        try context.save()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TaskStep>()) == 0)
    }

    @Test func unknownRawValuesHaveSafeDisplayFallbacksWithoutRewritingData() {
        let task = TodoTask(title: "未来版本")
        task.statusRaw = "future-status"
        task.importanceRaw = "future-importance"
        #expect(task.status == .pending)
        #expect(task.importance == .normal)
        #expect(task.statusRaw == "future-status")
        #expect(task.importanceRaw == "future-importance")
    }
}
