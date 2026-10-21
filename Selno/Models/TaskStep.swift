import Foundation
import SwiftData

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
