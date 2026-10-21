import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor struct Phase03Tests {
    private func container() throws -> ModelContainer { try PersistenceController.makeContainer(storage: .inMemory) }
    private func campus() throws -> TemplateDefinition { try #require(TemplatePresets.all.first { $0.0 == "校园二课活动" }?.2) }

    @Test func brandTypesReadsDeletesAndLoopsWithGraphemeClusters() {
        let phrase = "👩🏽‍💻e\u{301}，宁。"
        let state = BrandTypingState(phrases: [phrase, "从容。"])
        var values = [state.text]
        for _ in 0..<100 {
            if state.phase == .reading { #expect(state.text == state.fullText); #expect(state.delay >= .milliseconds(3500)) }
            state.advance(); values.append(state.text)
        }
        #expect(values.contains(phrase))
        #expect(values.contains("👩🏽‍💻e\u{301}"))
        #expect(values.contains(""))
        #expect(values.contains("从容。"))
        #expect(!values.contains("👩"))
        let saved = state.text
        // A suspended view does not advance its retained state; no timer exists in the model.
        #expect(state.text == saved)
    }

    @Test func presetsSeedOnceAndDeletedPresetStaysDeleted() throws {
        let c = try container(); let context = c.mainContext
        try TemplatePresets.seed(in: context)
        #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 4)
        let first = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
        try TemplateService(context: context).delete(first)
        try TemplatePresets.seed(in: context)
        #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 3)
    }

    @Test func templateCRUDStableFieldsAndIndependentHistoricalInstance() throws {
        let c = try container(); let context = c.mainContext; let service = TemplateService(context: context)
        let definition = try campus()
        let template = try service.save(name: "校园", emoji: "🏫", definition: definition)
        let copy = try service.duplicate(template)
        #expect(copy.id != template.id && copy.definition?.fields.map(\.id) == definition.fields.map(\.id))
        var draft = TaskDraft(plannedAt: .now)
        draft.title = "独立活动名称"; draft.template = TemplateTaskDraft(templateID: template.id, name: template.name, revision: template.revision, payload: TemplatePayload(definition: definition))
        let task = try TaskService(context: context).createTask(draft: draft)
        let snapshot = try #require(task.templateInstance?.payloadData)
        var changed = definition; changed.fields.reverse(); changed.fields[0].name = "新字段名称"
        try service.save(template, name: "新版校园", emoji: "", definition: changed)
        #expect(template.revision == 2)
        try service.delete(template)
        let reopened = ModelContext(c)
        let stored = try #require(reopened.fetch(FetchDescriptor<TodoTask>()).first)
        #expect(stored.title == "独立活动名称")
        #expect(stored.templateInstance?.payloadData == snapshot)
        #expect(stored.templateInstance?.templateRevision == 1)
        #expect(stored.templateInstance?.templateName == "校园")
    }

    @Test func multipleNodesRetainMeaningAndDoNotBecomeDeadlinesOrEvents() throws {
        let c = try container(); let context = c.mainContext
        let definition = try campus()
        var payload = TemplatePayload(definition: definition)
        let date = Date.now.addingTimeInterval(7 * 86400)
        for index in payload.fields.indices where payload.fields[index].kind == .dateTime {
            payload.answers[index].date = date.addingTimeInterval(Double(index) * 3600)
            payload.answers[index].showOnCalendar = true
        }
        var draft = TaskDraft(plannedAt: date); draft.plannedAt = nil; draft.title = "多个时间含义"
        draft.template = TemplateTaskDraft(templateID: nil, name: "校园", revision: 1, payload: payload)
        let task = try TaskService(context: context).createTask(draft: draft)
        #expect(task.dueAt == nil && task.plannedAt == nil)
        #expect(task.milestones?.count == 5)
        #expect(Set((task.milestones ?? []).map(\.semanticRaw)).count == 5)
        #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 0)
        let window = CalendarMath.window(containing: date, mode: .month, listRange: .month, calendar: .current)
        let nodes = try context.fetch(CalendarDataQuery.milestones(in: window.range))
        let summary = CalendarAgendaBuilder.build(tasks: [], events: [], window: window, calendar: .current, milestones: nodes)
        let day = summary.agenda(on: date, calendar: .current)
        #expect(day.tasks.count == 1 && day.events.isEmpty)
        #expect(day.tasks.first?.milestones.count == 5)
        let ids = Dictionary(uniqueKeysWithValues: (task.milestones ?? []).map { ($0.fieldID, $0.id) })
        var edit = TaskDraft(task: task)
        edit.template?.payload.answers[2].date = date.addingTimeInterval(1 * 3600)
        try TaskService(context: context).update(task, draft: edit)
        #expect(Dictionary(uniqueKeysWithValues: (task.milestones ?? []).map { ($0.fieldID, $0.id) }) == ids)
        #expect(task.dueAt == nil)
    }

    @Test func optionalFieldsHiddenFieldsAndInvalidURLsAndRangesValidate() throws {
        var payload = TemplatePayload(definition: try campus())
        try TemplateValidation.validate(payload)
        let url = try #require(payload.fields.firstIndex { $0.kind == .url })
        payload.answers[url].text = "file:///private/data"
        #expect(throws: TemplateError.self) { try TemplateValidation.validate(payload) }
        payload.answers[url].text = "https://school.example.edu/activity"
        let start = try #require(payload.fields.firstIndex { $0.semanticRaw == "activityStarts" })
        let end = try #require(payload.fields.firstIndex { $0.semanticRaw == "activityEnds" })
        payload.answers[start].date = .now; payload.answers[end].date = .distantPast
        #expect(throws: TemplateError.self) { try TemplateValidation.validate(payload) }
        payload.answers[end].date = .distantFuture
        payload.fields[0].isOptional = false; payload.fields[0].isVisible = false
        try TemplateValidation.validate(payload)
    }

    @Test func invalidTaskSaveDoesNotLeavePartialModels() throws {
        let c = try container(); let context = c.mainContext
        var definition = TemplateDefinition(); definition.fields = [TemplateField("网址", kind: .url)]
        var draft = TaskDraft(plannedAt: .now); draft.title = "无效任务"
        var payload = TemplatePayload(definition: definition); payload.answers[0].text = "invalid"
        draft.template = TemplateTaskDraft(templateID: nil, name: "测试", revision: 1, payload: payload)
        #expect(throws: TemplateError.self) { try TaskService(context: context).createTask(draft: draft) }
        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TaskTemplateInstance>()) == 0)
    }

    @Test func corruptAndFuturePayloadsAreRetainedDuringOrdinaryTaskEditing() throws {
        let c = try container(); let context = c.mainContext
        let task = try TaskService(context: context).createTask(title: "保留未知数据")
        let instance = try TaskTemplateInstance(templateID: nil, name: "未来版本", revision: 99, payload: TemplatePayload(definition: .init()))
        let bytes = Data("{invalid future content}".utf8)
        instance.payloadData = bytes; context.insert(instance); task.templateInstance = instance; try context.save()
        #expect(instance.payload == nil)
        var draft = TaskDraft(task: task); draft.title = "仍可编辑普通信息"
        try TaskService(context: context).update(task, draft: draft)
        #expect(instance.payloadData == bytes)
        var payload = TemplatePayload(definition: .init()); payload.version = 99
        #expect(!payload.isEditable)
        let fieldID = UUID()
        let answer = try JSONDecoder().decode(FieldAnswer.self, from: Data("{\"fieldID\":\"\(fieldID)\",\"date\":\"bad\",\"text\":12}".utf8))
        #expect(answer.date == nil && answer.text.isEmpty)
    }

    @Test func tagsCRUDMultipleAssociationsAndLegacyCategoryRemainSafe() throws {
        let c = try container(); let context = c.mainContext
        let tagService = TagService(context: context)
        let one = try tagService.save(name: "学习", emoji: "📚", color: "#4F7A69")
        let two = try tagService.save(name: "长名称的第二课堂活动", emoji: "", color: "#647C91")
        var draft = TaskDraft(plannedAt: .now); draft.title = "多标签"; draft.tagIDs = [one.id, two.id]
        let task = try TaskService(context: context).createTask(draft: draft)
        #expect(task.visibleTags.count == 2)
        try tagService.save(one, name: "课程", emoji: "🏫", color: "#A27A3F")
        #expect(task.visibleTags.contains { $0.name == "课程" && $0.emoji == "🏫" })
        try tagService.delete(one)
        let stored = try #require(ModelContext(c).fetch(FetchDescriptor<TodoTask>()).first)
        #expect(stored.visibleTags.map(\.id) == [two.id])
        #expect(stored.title == "多标签")
    }

    @Test func savingTaskAsTemplateCopiesTextAndTagsWithoutOldDatesOrReminders() throws {
        let c = try container(); let context = c.mainContext
        var definition = TemplateDefinition(); definition.fields = [TemplateField("说明"), TemplateField("报名截止", kind: .dateTime)]
        var payload = TemplatePayload(definition: definition); payload.answers[0].text = "可复用内容"; payload.answers[1].date = .now; payload.answers[1].reminderMinutes = 10
        var draft = TaskDraft(plannedAt: .now); draft.title = "现有任务"; draft.template = TemplateTaskDraft(templateID: nil, name: "源", revision: 1, payload: payload)
        let task = try TaskService(context: context).createTask(draft: draft)
        let template = try TemplateService(context: context).saveTaskAsTemplate(task, name: "自定义复用名称")
        #expect(template.name == "自定义复用名称")
        #expect(template.definition?.fields.first?.defaultText == "可复用内容")
        #expect(template.definition?.fields.last?.defaultDate == nil)
    }

    @Test func unsupportedTemplateDefinitionsCannotBeOverwrittenAndBlankGroupsNormalize() throws {
        let c = try container(); let context = c.mainContext
        let service = TemplateService(context: context)
        var definition = TemplateDefinition(); definition.fields = [TemplateField("内容", group: "  ")]
        let template = try service.save(name: "自定义", emoji: "", definition: definition)
        #expect(template.definition?.fields.first?.group == "其他")
        let bytes = Data("{unreadable future definition}".utf8)
        template.definitionData = bytes; try context.save()
        #expect(throws: TemplateError.self) { try service.save(template, name: "不会覆盖", emoji: "", definition: definition) }
        #expect(template.definitionData == bytes && template.name == "自定义")
        #expect(throws: TemplateError.self) { try service.duplicate(template) }
    }

    @Test func v2DiskStoreMigratesTaskEventCategoryAndRelationsToV3() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelnoV3-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Selno.store"); let id = UUID(); let tagID = UUID(); let eventID = UUID()
        let eventStart = Date(timeIntervalSince1970: 1_800_000_000)
        try autoreleasepool {
            let schema = Schema(versionedSchema: SelnoSchemaV2.self)
            let config = ModelConfiguration("Selno", schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: config)
            let task = SelnoSchemaV2.TodoTask(id: id, title: "V2 原任务", status: .completed)
            let tag = SelnoSchemaV2.TaskCategory(id: tagID, name: "旧标签", symbolName: "book", colorHex: "#123456", sortOrder: 2)
            old.mainContext.insert(task); old.mainContext.insert(tag); task.category = tag; task.dueAt = Date(timeIntervalSince1970: 1_800_000_000)
            old.mainContext.insert(SelnoSchemaV2.CalendarEvent(id: eventID, title: "原独立日程", startsAt: eventStart, endsAt: eventStart.addingTimeInterval(60)))
            try old.mainContext.save()
        }
        try autoreleasepool {
            let current = try PersistenceController.makeContainer(storage: .disk(url)); let context = current.mainContext
            let task = try #require(context.fetch(FetchDescriptor<TodoTask>()).first)
            #expect(task.id == id && task.status == .completed)
            #expect(task.visibleTags.first?.id == tagID && task.tags?.first?.id == tagID)
            #expect(task.visibleTags.first?.emoji == "" && task.visibleTags.first?.colorHex == "#123456")
            #expect(task.dueAt == Date(timeIntervalSince1970: 1_800_000_000))
            #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 1)
            let event = try #require(context.fetch(FetchDescriptor<CalendarEvent>()).first)
            #expect(event.id == eventID && event.title == "原独立日程")
            #expect(event.startsAt == eventStart && event.endsAt == eventStart.addingTimeInterval(60))
            try TemplatePresets.seed(in: context)
        }
        let reopened = try PersistenceController.makeContainer(storage: .disk(url))
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<TaskTemplate>()) == 4)
    }

    @Test func diskReopenRetainsTemplateSnapshotNodesAndMultipleTags() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelnoTemplateDisk-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Selno.store")
        var taskID = UUID()
        let tagID = UUID(), otherTagID = UUID()
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        var snapshot = Data(), nodeIDs = Set<UUID>(), fieldIDs: [UUID] = []
        try autoreleasepool {
            let c = try PersistenceController.makeContainer(storage: .disk(url)); let context = c.mainContext
            let tag = TaskCategory(id: tagID, name: "校园", symbolName: "tag", colorHex: "#4F7A69", sortOrder: 0)
            tag.emoji = "🏫"
            context.insert(tag)
            context.insert(TaskCategory(id: otherTagID, name: "材料", symbolName: "doc", colorHex: "#A27A3F", sortOrder: 1))
            let definition = try campus(); fieldIDs = definition.fields.map(\.id)
            let template = try TemplateService(context: context).save(name: "持久化模板", emoji: "🏫", definition: definition)
            var payload = TemplatePayload(definition: definition)
            for index in payload.fields.indices where payload.fields[index].kind == .dateTime {
                payload.answers[index].date = date.addingTimeInterval(Double(index) * 3600)
                payload.answers[index].showOnCalendar = true
            }
            var draft = TaskDraft(plannedAt: date); draft.title = "磁盘快照"; draft.dueAt = date.addingTimeInterval(10 * 86400)
            draft.tagIDs = [tagID, otherTagID]
            draft.template = TemplateTaskDraft(templateID: template.id, name: template.name, revision: template.revision, payload: payload)
            let task = try TaskService(context: context).createTask(draft: draft)
            taskID = task.id
            snapshot = try #require(task.templateInstance?.payloadData)
            nodeIDs = Set((task.milestones ?? []).map(\.id))
        }
        try autoreleasepool {
            let c = try PersistenceController.makeContainer(storage: .disk(url)); let context = c.mainContext
            let task = try #require(context.fetch(FetchDescriptor<TodoTask>()).first)
            #expect(task.id == taskID && task.title == "磁盘快照")
            #expect(task.dueAt == date.addingTimeInterval(10 * 86400))
            #expect(Set(task.visibleTags.map(\.id)) == [tagID, otherTagID])
            #expect(task.visibleTags.first?.emoji == "🏫")
            #expect(task.templateInstance?.payloadData == snapshot)
            #expect(task.templateInstance?.payload?.fields.map(\.id) == fieldIDs)
            #expect(task.templateInstance?.templateName == "持久化模板" && task.templateInstance?.templateRevision == 1)
            #expect(Set((task.milestones ?? []).map(\.id)) == nodeIDs && nodeIDs.count == 5)
            #expect(task.milestones?.allSatisfy(\.isOnCalendar) == true)
            #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 0)
        }
    }
}

@MainActor private final class TestReminderGateway: ReminderGateway {
    var isAuthorized = true
    var scheduled: [String: String] = [:]
    var additions = 0
    func authorized() async -> Bool { isAuthorized }
    func pending() async -> [String: String] { scheduled }
    func remove(_ identifiers: [String]) { for id in identifiers { scheduled.removeValue(forKey: id) } }
    func add(_ reminder: MilestoneReminder) async throws { scheduled[reminder.id] = reminder.signature; additions += 1 }
}

@MainActor struct MilestoneReminderTests {
    @Test func explicitRemindersReplaceByStableIDAndCleanUpOnCompletionAndDeletion() async throws {
        let c = try PersistenceController.makeContainer(storage: .inMemory); let context = c.mainContext
        let gateway = TestReminderGateway(); let service = ReminderService(context: context, gateway: gateway)
        let task = try TaskService(context: context).createTask(title: "报名活动")
        let node = TaskMilestone(fieldID: UUID(), title: "报名截止", semantic: "registrationEnds", date: .now.addingTimeInterval(7200))
        context.insert(node); node.task = task; try context.save()
        try await service.reconcile(); #expect(gateway.scheduled.isEmpty)
        node.reminderLeadMinutes = 10; try context.save()
        try await service.reconcile(); #expect(gateway.scheduled.count == 1); #expect(gateway.additions == 1)
        let id = node.notificationID
        try await service.reconcile(); #expect(gateway.additions == 1)
        node.date = node.date.addingTimeInterval(3600); try context.save()
        try await service.reconcile(); #expect(gateway.scheduled.keys.first == id && gateway.additions == 2)
        try TaskService(context: context).setStatus(.completed, for: task)
        try await service.reconcile(); #expect(gateway.scheduled.isEmpty)
        try TaskService(context: context).setStatus(.pending, for: task)
        try await service.reconcile(); #expect(gateway.scheduled.count == 1)
        try TaskService(context: context).delete(task)
        try await service.reconcile(); #expect(gateway.scheduled.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<TaskMilestone>()) == 0)
    }
    @Test func deniedPermissionAndPastTimesNeverProduceNotifications() async throws {
        let c = try PersistenceController.makeContainer(storage: .inMemory); let context = c.mainContext
        let gateway = TestReminderGateway(); gateway.isAuthorized = false
        let task = try TaskService(context: context).createTask(title: "不自动授权")
        let node = TaskMilestone(fieldID: UUID(), title: "提交", semantic: "submissionEnds", date: .distantFuture)
        context.insert(node); node.task = task; node.reminderLeadMinutes = 30; try context.save()
        let service = ReminderService(context: context, gateway: gateway)
        try await service.reconcile(); #expect(gateway.scheduled.isEmpty && node.reminderStateRaw == "blocked")
        gateway.isAuthorized = true; node.date = .distantPast; try context.save()
        try await service.reconcile(); #expect(gateway.scheduled.isEmpty && node.reminderStateRaw == "expired")
    }
}
