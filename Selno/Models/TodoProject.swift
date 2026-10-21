import Foundation
import SwiftData

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
