import Foundation
import SwiftData

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
