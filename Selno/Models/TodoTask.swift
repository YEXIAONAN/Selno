import Foundation
import SwiftData

@Model
final class TodoTask {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var statusRaw: String = TaskStatus.pending.rawValue
    var importanceRaw: String = TaskImportance.normal.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var plannedStartAt: Date?
    var plannedAt: Date?
    var dueAt: Date?
    var project: TodoProject?
    var category: TaskCategory?
    @Relationship(deleteRule: .nullify, inverse: \TaskCategory.taggedTasks)
    var tags: [TaskCategory]? = []
    @Relationship(deleteRule: .cascade, inverse: \TaskTemplateInstance.task)
    var templateInstance: TaskTemplateInstance?
    @Relationship(deleteRule: .cascade, inverse: \TaskMilestone.task)
    var milestones: [TaskMilestone]? = []

    @Relationship(deleteRule: .cascade, inverse: \TaskStep.parentTask)
    var steps: [TaskStep]? = []

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        status: TaskStatus = .pending,
        importance: TaskImportance = .normal,
        now: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.statusRaw = status.rawValue
        self.importanceRaw = importance.rawValue
        self.createdAt = now
        self.updatedAt = now
        self.completedAt = status == .completed ? now : nil
    }

    var status: TaskStatus { TaskStatus(rawValue: statusRaw) ?? .pending }
    var importance: TaskImportance { TaskImportance(rawValue: importanceRaw) ?? .normal }
    var isInInbox: Bool { project == nil && plannedAt == nil && plannedStartAt == nil }
    var visibleTags: [TaskCategory] {
        var ids = Set<UUID>()
        return ((tags ?? []) + (category.map { [$0] } ?? [])).filter { !$0.isArchived && ids.insert($0.id).inserted }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
    }

    var orderedSteps: [TaskStep] {
        (steps ?? []).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var completedStepCount: Int { (steps ?? []).filter(\.isCompleted).count }

    func urgency(on date: Date = .now, calendar: Calendar = .current) -> TaskUrgency {
        guard status.isActive, let dueAt else { return .unscheduled }
        if dueAt < calendar.startOfDay(for: date) { return .overdue }
        if calendar.isDate(dueAt, inSameDayAs: date) { return .dueToday }
        return .upcoming
    }
}
