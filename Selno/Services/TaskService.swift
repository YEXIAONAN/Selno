import Foundation
import SwiftData

struct TaskDraft: Equatable {
    var tagIDs: Set<UUID> = []
    var template: TemplateTaskDraft?
    var title: String
    var notes: String
    var status: TaskStatus
    var importance: TaskImportance
    var plannedAt: Date?
    var dueAt: Date?

    init(plannedAt: Date) {
        title = ""
        notes = ""
        status = .pending
        importance = .normal
        self.plannedAt = plannedAt
        dueAt = nil
    }

    init(task: TodoTask) {
        tagIDs = Set(task.visibleTags.map(\.id))
        if let instance = task.templateInstance, let payload = instance.payload, payload.isEditable {
            template = TemplateTaskDraft(templateID: instance.templateID, name: instance.templateName, revision: instance.templateRevision, payload: payload)
        }
        title = task.title
        notes = task.notes
        status = task.status
        importance = task.importance
        plannedAt = task.plannedAt
        dueAt = task.dueAt
    }
}

enum TaskValidationError: LocalizedError {
    case emptyTitle
    case cancelledTask
    case taskNotFound

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "请输入任务标题，标题不能只有空格或换行。"
        case .cancelledTask: "请先在任务详情中将已取消的任务恢复为待开始。"
        case .taskNotFound: "找不到要调整的任务，请刷新日历后重试。"
        }
    }
}

@MainActor
struct TaskService {
    let context: ModelContext

    @discardableResult
    func createTask(title: String, project: TodoProject? = nil, now: Date = .now) throws -> TodoTask {
        let title = try validatedTitle(title)
        let task = TodoTask(title: title, now: now)
        context.insert(task)
        task.project = project
        project?.updatedAt = now
        try save()
        return task
    }

    @discardableResult
    func createTask(draft: TaskDraft, now: Date = .now) throws -> TodoTask {
        let title = try validatedTitle(draft.title)
        if let payload = draft.template?.payload { try TemplateValidation.validate(payload) }
        let task = TodoTask(title: title, notes: draft.notes, status: draft.status, importance: draft.importance, now: now)
        task.plannedAt = draft.plannedAt
        task.dueAt = draft.dueAt
        context.insert(task)
        do { try applyDetails(draft, to: task) } catch { context.rollback(); throw error }
        try save()
        return task
    }

    func reschedule(taskID: UUID, to day: Date, calendar: Calendar, now: Date = .now) throws {
        let id = taskID
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })
        guard let task = try context.fetch(descriptor).first else { throw TaskValidationError.taskNotFound }
        let time = calendar.dateComponents([.hour, .minute, .second], from: task.plannedAt ?? CalendarMath.defaultTime(on: day, calendar: calendar))
        task.plannedAt = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0,
                                      second: time.second ?? 0, of: day) ?? calendar.startOfDay(for: day)
        task.updatedAt = now
        try save()
    }

    func update(_ task: TodoTask, draft: TaskDraft, now: Date = .now) throws {
        let title = try validatedTitle(draft.title)
        if let payload = draft.template?.payload { try TemplateValidation.validate(payload) }
        task.title = title
        task.notes = draft.notes
        task.importanceRaw = draft.importance.rawValue
        task.plannedAt = draft.plannedAt
        task.dueAt = draft.dueAt
        applyStatus(draft.status, to: task, now: now)
        do { try applyDetails(draft, to: task) } catch { context.rollback(); throw error }
        try save()
    }

    func setStatus(_ status: TaskStatus, for task: TodoTask, now: Date = .now) throws {
        applyStatus(status, to: task, now: now)
        try save()
    }

    func toggleCompletion(_ task: TodoTask, now: Date = .now) throws {
        guard task.status != .cancelled else { throw TaskValidationError.cancelledTask }
        try setStatus(task.status == .completed ? .pending : .completed, for: task, now: now)
    }

    @discardableResult
    func addStep(title: String, to task: TodoTask, now: Date = .now) throws -> TaskStep {
        let title = try validatedTitle(title)
        let order = (task.steps ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
        let step = TaskStep(title: title, sortOrder: order, now: now)
        context.insert(step)
        step.parentTask = task
        task.updatedAt = now
        try save()
        return step
    }

    func toggleStepCompletion(_ step: TaskStep, now: Date = .now) throws {
        step.isCompleted.toggle()
        step.completedAt = step.isCompleted ? now : nil
        step.parentTask?.updatedAt = now
        try save()
    }

    private func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskValidationError.emptyTitle }
        return trimmed
    }

    func delete(_ task: TodoTask) throws { context.delete(task); try save() }

    private func applyDetails(_ draft: TaskDraft, to task: TodoTask) throws {
        let tags = try context.fetch(FetchDescriptor<TaskCategory>()).filter { draft.tagIDs.contains($0.id) }
        task.tags = tags
        task.category = tags.first
        guard let source = draft.template else { return } // Keep unreadable future-version payloads intact.
        let encoded = try TemplateCodec.encode(source.payload)
        if let instance = task.templateInstance { instance.payloadData = encoded }
        else {
            let instance = try TaskTemplateInstance(templateID: source.templateID, name: source.name, revision: source.revision, payload: source.payload)
            context.insert(instance); task.templateInstance = instance
        }
        var retained = Set<UUID>()
        for field in source.payload.fields where field.kind == .dateTime {
            let answer = source.payload.answer(field)
            guard let date = answer.date else { continue }
            let node = (task.milestones ?? []).first { $0.fieldID == field.id } ?? TaskMilestone(fieldID: field.id, title: field.name, semantic: field.semanticRaw, date: date)
            if node.modelContext == nil { context.insert(node); node.task = task }
            node.title = field.name; node.date = date; node.semanticRaw = field.semanticRaw
            node.isOnCalendar = answer.showOnCalendar; node.reminderLeadMinutes = answer.reminderMinutes
            retained.insert(node.id)
        }
        for node in task.milestones ?? [] where !retained.contains(node.id) { context.delete(node) }
    }

    private func applyStatus(_ status: TaskStatus, to task: TodoTask, now: Date) {
        if status == .completed {
            task.completedAt = task.completedAt ?? now
        } else {
            task.completedAt = nil
        }
        task.statusRaw = status.rawValue
        task.updatedAt = now
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
