import Foundation
import SwiftData

struct CalendarEventDraft {
    var title = ""
    var notes = ""
    var startsAt: Date
    // In the all-day editor this represents the inclusive last date.
    var endsAt: Date
    var isAllDay = false
    var location = ""

    init(date: Date, calendar: Calendar) {
        startsAt = CalendarMath.defaultTime(on: date, calendar: calendar)
        endsAt = calendar.date(byAdding: .hour, value: 1, to: startsAt) ?? startsAt
    }

    init(event: CalendarEvent, calendar: Calendar) {
        title = event.title
        notes = event.notes
        startsAt = event.startsAt
        endsAt = event.isAllDay
            ? (calendar.date(byAdding: .day, value: -1, to: event.endsAt) ?? event.startsAt)
            : event.endsAt
        isAllDay = event.isAllDay
        location = event.location ?? ""
    }
}

enum CalendarEventError: LocalizedError {
    case emptyTitle
    case invalidInterval

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "请输入日程名称，名称不能只有空格。"
        case .invalidInterval: "结束时间不能早于开始时间。全天日程的结束日期包含当天。"
        }
    }
}

@MainActor
struct CalendarEventService {
    let context: ModelContext
    let calendar: Calendar

    @discardableResult
    func create(draft: CalendarEventDraft, now: Date = .now) throws -> CalendarEvent {
        let values = try validated(draft)
        let event = CalendarEvent(
            title: values.title, notes: draft.notes,
            startsAt: values.start, endsAt: values.end,
            isAllDay: draft.isAllDay, location: values.location, now: now
        )
        context.insert(event)
        try save()
        return event
    }

    func update(_ event: CalendarEvent, draft: CalendarEventDraft, now: Date = .now) throws {
        let values = try validated(draft)
        event.title = values.title
        event.notes = draft.notes
        event.startsAt = values.start
        event.endsAt = values.end
        event.isAllDay = draft.isAllDay
        event.location = values.location
        event.updatedAt = now
        try save()
    }

    func delete(_ event: CalendarEvent) throws {
        context.delete(event)
        try save()
    }

    private func validated(_ draft: CalendarEventDraft) throws -> (title: String, start: Date, end: Date, location: String?) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CalendarEventError.emptyTitle }
        let start: Date
        let end: Date
        if draft.isAllDay {
            start = calendar.startOfDay(for: draft.startsAt)
            let lastDay = calendar.startOfDay(for: draft.endsAt)
            guard lastDay >= start,
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else {
                throw CalendarEventError.invalidInterval
            }
            end = nextDay
        } else {
            start = draft.startsAt
            end = draft.endsAt
            guard end >= start else { throw CalendarEventError.invalidInterval }
        }
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, start, end, location.isEmpty ? nil : location)
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
