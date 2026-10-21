import Foundation
import SwiftData

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
