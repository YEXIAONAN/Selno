import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct Phase04TaskWorkflowTests {
    private let base = Date(timeIntervalSince1970: 1_790_003_000.125)

    private func make() throws -> (ModelContainer, ModelContext) {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        return (container, container.mainContext)
    }

    private func task(_ title: String, now: Date? = nil) -> TodoTask {
        TodoTask(title: title, now: now ?? base)
    }

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    // MARK: Filtering

    @Test func searchCoversTitleNotesProjectTagAndLegacyCategory() throws {
        let (container, context) = try make()
        _ = container
        let project = TodoProject(name: "毕业设计", now: base)
        let tag = TaskCategory(name: "学习", symbolName: "book", colorHex: "#3F6852", sortOrder: 1, now: base)
        tag.emoji = "📚"
        let legacy = TaskCategory(name: "旧分类", symbolName: "tag", colorHex: "#808080", sortOrder: 2, now: base)
        context.insert(project)
        context.insert(tag)
        context.insert(legacy)

        let paper = task("撰写论文")
        paper.notes = "检查引用格式"
        paper.project = project
        paper.tags = [tag]
        paper.category = tag
        let groceries = task("买菜")
        groceries.category = legacy
        let archived = task("旧任务")
        archived.archivedAt = base
        archived.tags = [tag]
        context.insert(paper)
        context.insert(groceries)
        context.insert(archived)
        try context.save()

        #expect(TaskQueryFilter.matches(paper, needle: "论文"))
        #expect(TaskQueryFilter.matches(paper, needle: "引用"))
        #expect(TaskQueryFilter.matches(paper, needle: "毕业"))
        #expect(TaskQueryFilter.matches(paper, needle: "📚"))
        #expect(TaskQueryFilter.matches(groceries, needle: "旧分类"))
        #expect(!TaskQueryFilter.matches(groceries, needle: "毕业"))

        let all = [paper, groceries, archived]
        let searchResult = TaskQueryFilter.apply(
            all, search: "📚", status: .all, project: .all, tagID: nil
        )
        #expect(searchResult.map(\.id) == [paper.id])

        let archivedResult = TaskQueryFilter.apply(
            all, search: "", status: .archived, project: .all, tagID: nil
        )
        #expect(archivedResult.map(\.id) == [archived.id])

        let projectResult = TaskQueryFilter.apply(
            all, search: "", status: .all, project: .project(project.id), tagID: nil
        )
        #expect(projectResult.map(\.id) == [paper.id])

        let unassigned = TaskQueryFilter.apply(
            all, search: "", status: .all, project: .unassigned, tagID: nil
        )
        #expect(unassigned.map(\.id) == [groceries.id])

        let tagResult = TaskQueryFilter.apply(
            all, search: "", status: .all, project: .all, tagID: legacy.id
        )
        #expect(tagResult.map(\.id) == [groceries.id])
    }

    @Test func statusFilterNeverMixesArchivedWithEverydayStatuses() throws {
        let (container, context) = try make()
        _ = container
        let pending = task("待开始")
        let active = task("进行中")
        active.statusRaw = TaskStatus.inProgress.rawValue
        let completed = task("已完成")
        completed.statusRaw = TaskStatus.completed.rawValue
        let cancelled = task("已取消")
        cancelled.statusRaw = TaskStatus.cancelled.rawValue
        let archived = task("已归档")
        archived.archivedAt = base
        let archivedCompleted = task("已归档完成")
        archivedCompleted.archivedAt = base
        archivedCompleted.statusRaw = TaskStatus.completed.rawValue
        for value in [pending, active, completed, cancelled, archived, archivedCompleted] {
            context.insert(value)
        }
        try context.save()

        let all = [pending, active, completed, cancelled, archived, archivedCompleted]
        func ids(_ status: TaskStatusFilter) -> Set<UUID> {
            Set(TaskQueryFilter.apply(all, search: "", status: status,
                                      project: .all, tagID: nil).map(\.id))
        }

        #expect(ids(.all) == [pending.id, active.id, completed.id, cancelled.id])
        #expect(ids(.pending) == [pending.id])
        #expect(ids(.inProgress) == [active.id])
        #expect(ids(.completed) == [completed.id])
        #expect(ids(.cancelled) == [cancelled.id])
        #expect(ids(.archived) == [archived.id, archivedCompleted.id])
    }

    @Test func listScopesHideArchivedTasksEverywhere() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 21, hour: 9, minute: 0
        )))
        let active = task("今天要做")
        active.plannedAt = today
        let archivedToday = task("已归档的今天")
        archivedToday.plannedAt = today
        archivedToday.archivedAt = base
        let inbox = task("收件箱任务")
        let archivedInbox = task("已归档的收件箱")
        archivedInbox.archivedAt = base
        let values = [active, archivedToday, inbox, archivedInbox]

        #expect(TaskListScope.today.tasks(from: values, on: today, calendar: calendar).map(\.id) == [active.id])
        #expect(TaskListScope.inbox.tasks(from: values, on: today, calendar: calendar).map(\.id) == [inbox.id])
        #expect(Set(TaskListScope.all.tasks(from: values, on: today, calendar: calendar).map(\.id))
                == [active.id, inbox.id])
    }

    @Test func sortModesKeepActiveTasksBeforeFinishedOnes() {
        let activeLater = task("晚截止", now: base)
        activeLater.dueAt = base.addingTimeInterval(86_400)
        let activeSooner = task("早截止", now: base)
        activeSooner.dueAt = base.addingTimeInterval(3_600)
        let done = task("已完成", now: base)
        done.statusRaw = TaskStatus.completed.rawValue
        done.dueAt = base

        let sorted = TaskSortMode.dueDate.sort([done, activeLater, activeSooner])
        #expect(sorted.map(\.id) == [activeSooner.id, activeLater.id, done.id])
    }

    // MARK: Batch operations

    @Test func batchOperationsUpdateAllTargetsInOneTransaction() throws {
        let (container, context) = try make()
        _ = container
        let project = TodoProject(name: "项目", now: base)
        let firstTag = TaskCategory(name: "已有", symbolName: "tag", colorHex: "#3F6852", sortOrder: 1, now: base)
        let secondTag = TaskCategory(name: "新增", symbolName: "tag", colorHex: "#A33E3C", sortOrder: 2, now: base)
        context.insert(project)
        context.insert(firstTag)
        context.insert(secondTag)

        let one = task("任务一")
        one.tags = [firstTag]
        one.category = firstTag
        let two = task("任务二")
        two.tags = [firstTag]
        two.category = firstTag
        let cancelled = task("取消任务")
        cancelled.statusRaw = TaskStatus.cancelled.rawValue
        for value in [one, two, cancelled] { context.insert(value) }
        try context.save()

        let service = TaskService(context: context)
        let completed = try service.complete([one, two])
        #expect(completed == 2)
        #expect(one.status == .completed && two.status == .completed)
        #expect(cancelled.status == .cancelled)

        try service.addTag(secondTag, to: [one, two])
        #expect(Set((one.tags ?? []).map(\.id)) == [firstTag.id, secondTag.id])
        // Adding the same tag again must not duplicate the association.
        try service.addTag(secondTag, to: [one])
        #expect((one.tags ?? []).filter { $0.id == secondTag.id }.count == 1)

        try service.assign(project: project, to: [one, two])
        #expect(one.project?.id == project.id && two.project?.id == project.id)
        try service.assign(project: nil, to: [one])
        #expect(one.project == nil && two.project?.id == project.id)

        try service.setArchived(true, for: [one, two])
        #expect(one.isArchived && two.isArchived)
        #expect(Set(TaskListScope.all.tasks(from: [one, two, cancelled], on: base, calendar: .current).map(\.id))
                == [cancelled.id])
        try service.setArchived(false, for: [two])
        #expect(!two.isArchived && one.isArchived)
    }

    // MARK: Delete and undo

    private struct DeletionFixture {
        let taskID: UUID
        let projectID: UUID
        let tagID: UUID
        let templateID: UUID
        let stepIDs: [UUID]
        let milestoneID: UUID
        let instanceID: UUID
        let dueReminderID: UUID
        let scheduledReminderID: UUID
        let due: Date
        let scheduled: Date
    }

    private func populateForDeletion(_ context: ModelContext) throws -> DeletionFixture {
        let due = base.addingTimeInterval(2 * 86_400)
        let scheduled = base.addingTimeInterval(4 * 3_600)
        let project = TodoProject(name: "项目", notes: "说明", now: base)
        let tag = TaskCategory(name: "标签", symbolName: "tag", colorHex: "#3F6852", sortOrder: 1, now: base)
        context.insert(project)
        context.insert(tag)

        var definition = TemplateDefinition()
        definition.fields = [TemplateField("截止", kind: .dateTime, semantic: .date)]
        var payload = TemplatePayload(definition: definition)
        payload.answers[0].date = due
        payload.answers[0].showOnCalendar = true
        payload.answers[0].reminderMinutes = 1_440

        let template = TaskTemplate(name: "模板", definition: definition)
        context.insert(template)

        let taskID = UUID()
        let value = TodoTask(id: taskID, title: "会被删除的任务", notes: "备注\n第二行",
                             status: .inProgress, importance: .high, now: base)
        value.updatedAt = base.addingTimeInterval(60)
        value.plannedStartAt = base.addingTimeInterval(3_600)
        value.plannedAt = base.addingTimeInterval(7_200)
        value.dueAt = due
        value.project = project
        value.category = tag
        value.tags = [tag]
        context.insert(value)

        let stepIDs = [UUID(), UUID()]
        let step1 = TaskStep(id: stepIDs[0], title: "第一步", sortOrder: 0, now: base)
        let step2 = TaskStep(id: stepIDs[1], title: "第二步", sortOrder: 1, now: base.addingTimeInterval(10))
        step2.isCompleted = true
        step2.completedAt = base.addingTimeInterval(20)
        context.insert(step1)
        context.insert(step2)
        step1.parentTask = value
        step2.parentTask = value

        let instance = try TaskTemplateInstance(templateID: template.id, name: template.name,
                                                revision: template.revision, payload: payload)
        let instanceID = instance.id
        context.insert(instance)
        value.templateInstance = instance

        let milestone = TaskMilestone(fieldID: definition.fields[0].id, title: "截止",
                                      semantic: MilestoneSemantic.date.rawValue, date: due)
        let milestoneID = milestone.id
        milestone.isOnCalendar = true
        milestone.reminderLeadMinutes = 1_440
        context.insert(milestone)
        milestone.task = value

        let dueReminder = TaskReminder(id: UUID(), taskID: taskID, kind: .due,
                                       leadMinutes: 120, now: base)
        let scheduledReminder = TaskReminder(id: UUID(), taskID: taskID, kind: .scheduled,
                                             scheduledAt: scheduled, now: base)
        context.insert(dueReminder)
        context.insert(scheduledReminder)

        try context.save()
        return DeletionFixture(
            taskID: taskID, projectID: project.id, tagID: tag.id, templateID: template.id,
            stepIDs: stepIDs, milestoneID: milestoneID, instanceID: instanceID,
            dueReminderID: dueReminder.id, scheduledReminderID: scheduledReminder.id,
            due: due, scheduled: scheduled
        )
    }

    @Test func deletionSnapshotRestoresIDsRelationshipsChildrenAndReminders() throws {
        let (container, context) = try make()
        _ = container
        let fixture = try populateForDeletion(context)
        let service = TaskService(context: context)

        let taskID = fixture.taskID
        let task = try #require(try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first)
        let snapshot = try service.delete(task, now: base.addingTimeInterval(120))
        #expect(snapshot.count == 1)
        #expect(snapshot.taskIDs == [fixture.taskID])
        #expect(snapshot.message.contains("会被删除的任务"))

        #expect(try count(TodoTask.self, in: context) == 0)
        #expect(try count(TaskStep.self, in: context) == 0)
        #expect(try count(TaskMilestone.self, in: context) == 0)
        #expect(try count(TaskTemplateInstance.self, in: context) == 0)
        #expect(try count(TaskReminder.self, in: context) == 0)
        // Tags, projects and the template must survive a task deletion.
        #expect(try count(TodoProject.self, in: context) == 1)
        #expect(try count(TaskCategory.self, in: context) == 1)
        #expect(try count(TaskTemplate.self, in: context) == 1)

        try service.restore(snapshot, now: base.addingTimeInterval(180))
        let restored = try #require(try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first)
        #expect(restored.title == "会被删除的任务")
        #expect(restored.notes == "备注\n第二行")
        #expect(restored.status == .inProgress)
        #expect(restored.importance == .high)
        #expect(restored.plannedStartAt == base.addingTimeInterval(3_600))
        #expect(restored.plannedAt == base.addingTimeInterval(7_200))
        #expect(restored.dueAt == fixture.due)
        #expect(restored.project?.id == fixture.projectID)
        #expect(Set(restored.tags?.map(\.id) ?? []) == [fixture.tagID])
        #expect(restored.category?.id == fixture.tagID)
        #expect(restored.orderedSteps.map(\.id) == fixture.stepIDs)
        #expect(restored.orderedSteps.map(\.title) == ["第一步", "第二步"])
        #expect(restored.orderedSteps.map(\.isCompleted) == [false, true])
        #expect(restored.templateInstance?.id == fixture.instanceID)
        #expect(restored.templateInstance?.payload?.answers.first?.date == fixture.due)
        #expect(restored.milestones?.map(\.id) == [fixture.milestoneID])
        #expect(restored.milestones?.first?.isOnCalendar == true)
        #expect(restored.milestones?.first?.reminderLeadMinutes == 1_440)

        let reminders = try context.fetch(FetchDescriptor<TaskReminder>())
        #expect(reminders.count == 2)
        let dueReminder = try #require(reminders.first { $0.id == fixture.dueReminderID })
        let scheduledReminder = try #require(reminders.first { $0.id == fixture.scheduledReminderID })
        #expect(dueReminder.taskID == fixture.taskID)
        #expect(dueReminder.kind == .due && dueReminder.leadMinutes == 120)
        #expect(scheduledReminder.taskID == fixture.taskID)
        #expect(scheduledReminder.kind == .scheduled && scheduledReminder.scheduledAt == fixture.scheduled)

        // The snapshot is idempotent: undoing twice must not duplicate any row.
        try service.restore(snapshot, now: base.addingTimeInterval(240))
        #expect(try count(TodoTask.self, in: context) == 1)
        #expect(try count(TaskStep.self, in: context) == 2)
        #expect(try count(TaskMilestone.self, in: context) == 1)
        #expect(try count(TaskTemplateInstance.self, in: context) == 1)
        #expect(try count(TaskReminder.self, in: context) == 2)
    }

    @Test func undoCenterOffersMessageAndRestoresThroughTaskService() throws {
        let (container, context) = try make()
        _ = container
        let fixture = try populateForDeletion(context)
        let service = TaskService(context: context)
        let taskID = fixture.taskID
        let task = try #require(try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first)
        let snapshot = try service.delete(task)
        let undo = TaskUndoCenter.shared
        defer { undo.clear() }

        undo.offer(snapshot)
        #expect(undo.snapshot?.taskIDs == [fixture.taskID])
        #expect(undo.message == snapshot.message)

        try undo.undo(context: context)
        #expect(undo.snapshot == nil)
        #expect(undo.message == nil)
        #expect(try count(TodoTask.self, in: context) == 1)
        let restored = try #require(try context.fetch(FetchDescriptor<TodoTask>()).first)
        #expect(restored.id == fixture.taskID)
    }
}