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
    /// nil means no reminder for that kind. Rows are reconciled into `TaskReminder`
    /// in the same save as the task, so a date edit cannot leave a stale notification.
    var dueReminderLeadMinutes: Int?
    var scheduledReminderAt: Date?

    init(plannedAt: Date) {
        title = ""
        notes = ""
        status = .pending
        importance = .normal
        self.plannedAt = plannedAt
        dueAt = nil
        dueReminderLeadMinutes = nil
        scheduledReminderAt = nil
    }

    init(task: TodoTask, reminders: [TaskReminder] = []) {
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
        let relevant = reminders.filter { $0.taskID == task.id }
        dueReminderLeadMinutes = relevant
            .filter { $0.kind == .due }
            .max { $0.updatedAt < $1.updatedAt }?
            .leadMinutes
        scheduledReminderAt = relevant
            .filter { $0.kind == .scheduled }
            .max { $0.updatedAt < $1.updatedAt }?
            .scheduledAt
    }
}

/// Everything needed to recreate a deletion and its relationships, captured before
/// the rows are removed. Restoring reuses the validated JSON import path so a deleted
/// task comes back with the same IDs, tags, project, steps, template snapshot,
/// milestones and reminder configuration.
struct TaskDeletionSnapshot {
    let backup: SelnoBackup
    let taskIDs: Set<UUID>
    let titles: [String]

    var count: Int { taskIDs.count }
    var message: String {
        if count == 1 { return "已删除「\(titles.first ?? "任务")」" }
        return "已删除 \(count) 个任务"
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
        do {
            try applyDetails(draft, to: task)
            try applyReminders(draft, to: task, previousDueAt: nil, now: now)
        } catch { context.rollback(); throw error }
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
        let previousDueAt = task.dueAt
        task.title = title
        task.notes = draft.notes
        task.importanceRaw = draft.importance.rawValue
        task.plannedAt = draft.plannedAt
        task.dueAt = draft.dueAt
        applyStatus(draft.status, to: task, now: now)
        do {
            try applyDetails(draft, to: task)
            try applyReminders(draft, to: task, previousDueAt: previousDueAt, now: now)
        } catch { context.rollback(); throw error }
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

    @discardableResult
    func delete(_ task: TodoTask, now: Date = .now) throws -> TaskDeletionSnapshot {
        try delete([task], now: now)
    }

    @discardableResult
    func delete(_ tasks: [TodoTask], now: Date = .now) throws -> TaskDeletionSnapshot {
        let unique = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        let targets = Array(unique)
        let ids = Set(targets.map(\.id))
        let snapshot = try deletionSnapshot(for: targets, now: now)
        do {
            let reminders = try context.fetch(FetchDescriptor<TaskReminder>())
            for reminder in reminders where reminder.taskID.map(ids.contains) == true {
                context.delete(reminder)
            }
            for task in targets { context.delete(task) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return snapshot
    }

    func restore(_ snapshot: TaskDeletionSnapshot, now: Date = .now) throws {
        guard !snapshot.taskIDs.isEmpty else { return }
        let document = BackupDocument(backup: snapshot.backup, fileName: "Selno-Undo-Delete.json")
        _ = try BackupImportService(context: context).apply(document: document, mode: .merge, now: now)
    }

    private func deletionSnapshot(for tasks: [TodoTask], now: Date) throws -> TaskDeletionSnapshot {
        let ids = Set(tasks.map(\.id))
        let titles = tasks.sorted { $0.createdAt < $1.createdAt }.map(\.title)
        guard !ids.isEmpty else {
            return TaskDeletionSnapshot(
                backup: SelnoBackup(exportedAt: now, data: SelnoBackupData()),
                taskIDs: ids, titles: titles
            )
        }
        let full = try BackupExportService(context: context).makeBackup(now: now)
        let data = SelnoBackupData(
            projects: full.data.projects,
            tags: full.data.tags,
            templates: full.data.templates,
            tasks: full.data.tasks.filter { ids.contains($0.id) },
            events: [],
            reminders: full.data.reminders.filter { ids.contains($0.taskID) }
        )
        return TaskDeletionSnapshot(
            backup: SelnoBackup(exportedAt: now, data: data),
            taskIDs: ids, titles: titles
        )
    }

    @discardableResult
    func complete(_ tasks: [TodoTask], now: Date = .now) throws -> Int {
        let eligible = tasks.filter { $0.status != .cancelled }
        guard !eligible.isEmpty else { return 0 }
        do {
            for task in eligible { applyStatus(.completed, to: task, now: now) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return eligible.count
    }

    /// Adds a tag without dropping any existing associations. Existing category or
    /// archived-tag state is preserved.
    func addTag(_ tag: TaskCategory, to tasks: [TodoTask], now: Date = .now) throws {
        guard !tasks.isEmpty else { return }
        do {
            for task in tasks {
                var current = task.tags ?? []
                if !current.contains(where: { $0.id == tag.id }) { current.append(tag) }
                task.tags = current
                task.updatedAt = now
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func assign(project: TodoProject?, to tasks: [TodoTask], now: Date = .now) throws {
        guard !tasks.isEmpty else { return }
        do {
            for task in tasks {
                task.project = project
                task.updatedAt = now
            }
            project?.updatedAt = now
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func setArchived(_ archived: Bool, for tasks: [TodoTask], now: Date = .now) throws {
        guard !tasks.isEmpty else { return }
        do {
            for task in tasks {
                task.archivedAt = archived ? (task.archivedAt ?? now) : nil
                task.updatedAt = now
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

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

    private func applyReminders(_ draft: TaskDraft, to task: TodoTask,
                               previousDueAt: Date?, now: Date) throws {
        let taskID = task.id
        let existing = try context.fetch(
            FetchDescriptor<TaskReminder>(predicate: #Predicate { $0.taskID == taskID })
        )
        let dueRows = existing.filter { $0.kind == .due }
            .sorted { $0.updatedAt > $1.updatedAt || ($0.updatedAt == $1.updatedAt && $0.id.uuidString > $1.id.uuidString) }
        let scheduledRows = existing.filter { $0.kind == .scheduled }
            .sorted { $0.updatedAt > $1.updatedAt || ($0.updatedAt == $1.updatedAt && $0.id.uuidString > $1.id.uuidString) }

        if let lead = draft.dueReminderLeadMinutes, task.dueAt != nil {
            guard (0...525_600).contains(lead) else { throw ReminderError.invalidLead }
            let row: TaskReminder
            if let existingRow = dueRows.first {
                row = existingRow
                if row.leadMinutes != lead || previousDueAt != task.dueAt { row.snoozeUntil = nil }
            } else {
                row = TaskReminder(taskID: taskID, kind: .due, leadMinutes: lead, now: now)
                context.insert(row)
            }
            row.taskID = taskID
            row.kindRaw = TaskReminderKind.due.rawValue
            row.leadMinutes = lead
            row.scheduledAt = nil
            row.stateRaw = TaskReminderState.pending.rawValue
            row.updatedAt = now
            for duplicate in dueRows.dropFirst() { context.delete(duplicate) }
        } else {
            for row in dueRows { context.delete(row) }
        }

        if let date = draft.scheduledReminderAt, date.timeIntervalSince1970.isFinite {
            let row: TaskReminder
            if let existingRow = scheduledRows.first {
                row = existingRow
                if row.scheduledAt != date { row.snoozeUntil = nil }
            } else {
                row = TaskReminder(taskID: taskID, kind: .scheduled, scheduledAt: date, now: now)
                context.insert(row)
            }
            row.taskID = taskID
            row.kindRaw = TaskReminderKind.scheduled.rawValue
            row.leadMinutes = 0
            row.scheduledAt = date
            row.stateRaw = TaskReminderState.pending.rawValue
            row.updatedAt = now
            for duplicate in scheduledRows.dropFirst() { context.delete(duplicate) }
        } else {
            for row in scheduledRows { context.delete(row) }
        }
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
