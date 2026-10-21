// Frozen Phase 02 schema. Do not edit when evolving current models.
import Foundation
import SwiftData

extension SelnoSchemaV2 {

    @Model
    final class TodoProject {
        var id: UUID = UUID()
        var name: String = ""
        var notes: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var archivedAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \TodoTask.project)
        var tasks: [TodoTask]? = []

        init(id: UUID = UUID(), name: String, notes: String = "", now: Date = .now) {
            self.id = id
            self.name = name
            self.notes = notes
            self.createdAt = now
            self.updatedAt = now
        }
    }

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

    @Model
    final class TaskStep {
        var id: UUID = UUID()
        var title: String = ""
        var isCompleted: Bool = false
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var completedAt: Date?
        var parentTask: TodoTask?

        init(id: UUID = UUID(), title: String, sortOrder: Int, now: Date = .now) {
            self.id = id
            self.title = title
            self.sortOrder = sortOrder
            self.createdAt = now
        }
    }

    @Model
    final class TaskCategory {
        var id: UUID = UUID()
        var name: String = ""
        var symbolName: String = "tag"
        var colorHex: String = "#808080"
        var sortOrder: Int = 0
        var isArchived: Bool = false
        var createdAt: Date = Date()

        @Relationship(deleteRule: .nullify, inverse: \TodoTask.category)
        var tasks: [TodoTask]? = []

        init(
            id: UUID = UUID(),
            name: String,
            symbolName: String,
            colorHex: String,
            sortOrder: Int,
            now: Date = .now
        ) {
            self.id = id
            self.name = name
            self.symbolName = symbolName
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.createdAt = now
        }
    }

    @Model
    final class SeedRecord {
        var id: UUID = UUID()
        var key: String = ""
        var createdAt: Date = Date()

        init(key: String, now: Date = .now) {
            self.key = key
            self.createdAt = now
        }
    }

    @Model
    final class CalendarEvent {
        var id: UUID = UUID()
        var title: String = ""
        var notes: String = ""
        var startsAt: Date = Date()
        var endsAt: Date = Date()
        var isAllDay: Bool = false
        var location: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        // All-day intervals use local midnight boundaries with an exclusive end.
        init(
            id: UUID = UUID(), title: String, notes: String = "",
            startsAt: Date, endsAt: Date, isAllDay: Bool = false,
            location: String? = nil, now: Date = .now
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.startsAt = startsAt
            self.endsAt = endsAt
            self.isAllDay = isAllDay
            self.location = location
            self.createdAt = now
            self.updatedAt = now
        }
    }

}
