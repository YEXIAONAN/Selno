import Foundation
import SwiftData

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

    /// Restoration path for backups: the payload bytes are already validated and may
    /// intentionally be preserved verbatim when they cannot be decoded by this version.
    init(id: UUID, templateID: UUID?, name: String, revision: Int, payloadData: Data?) {
        self.id = id
        self.templateID = templateID
        templateName = name
        templateRevision = revision
        self.payloadData = payloadData
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
