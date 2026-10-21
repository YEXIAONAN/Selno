// Frozen Phase 03 schema (3.0.0). Do not edit when evolving current models.
// Current model types live at module level and are declared as SelnoSchemaV4.
import Foundation
import SwiftData

extension SelnoSchemaV3 {

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
        var emoji: String = ""

        @Relationship(deleteRule: .nullify, inverse: \TodoTask.category)
        var tasks: [TodoTask]? = []
        var taggedTasks: [TodoTask]? = []

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

    @Model final class TaskTemplate {
        var id: UUID = UUID()
        var name: String = ""
        var emoji: String = ""
        var revision: Int = 1
        var definitionData: Data?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        init(name: String, emoji: String = "", definition: TemplateDefinition = .init()) {
            self.name = name; self.emoji = emoji
            definitionData = try? TemplateCodec.encode(definition)
        }
        var definition: TemplateDefinition? { TemplateCodec.decode(TemplateDefinition.self, data: definitionData) }
    }

    @Model final class TaskTemplateInstance {
        var id: UUID = UUID()
        var templateID: UUID?
        var templateName: String = ""
        var templateRevision: Int = 1
        var payloadData: Data?
        var task: TodoTask?
        init(templateID: UUID?, name: String, revision: Int, payload: TemplatePayload) throws {
            self.templateID = templateID; templateName = name; templateRevision = revision
            payloadData = try TemplateCodec.encode(payload)
        }
        var payload: TemplatePayload? { TemplateCodec.decode(TemplatePayload.self, data: payloadData) }
    }

    @Model final class TaskMilestone {
        var id: UUID = UUID()
        var fieldID: UUID = UUID()
        var title: String = ""
        var semanticRaw: String = "date"
        var date: Date = Date()
        var isOnCalendar: Bool = false
        var reminderLeadMinutes: Int?
        var reminderStateRaw: String = "none"
        var task: TodoTask?
        init(fieldID: UUID, title: String, semantic: String, date: Date) {
            self.fieldID = fieldID; self.title = title; semanticRaw = semantic; self.date = date
        }
        var notificationID: String { "selno.node.\(id.uuidString)" }
    }
}