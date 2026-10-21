import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct CalendarEventTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    @Test func createUpdateAndDeleteEventsAreSavedExplicitly() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = CalendarEventService(context: container.mainContext, calendar: calendar)
        var draft = CalendarEventDraft(date: .now, calendar: calendar)
        draft.title = "  竞赛讨论  "
        draft.location = "  实验室  "
        let event = try service.create(draft: draft)
        #expect(event.title == "竞赛讨论")
        #expect(event.location == "实验室")
        #expect(!container.mainContext.hasChanges)
        draft.title = "竞赛答辩"
        draft.notes = "带电脑"
        let changedAt = Date.now.addingTimeInterval(1)
        try service.update(event, draft: draft, now: changedAt)
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<CalendarEvent>()).first)
        #expect(stored.id == event.id)
        #expect(stored.title == "竞赛答辩")
        #expect(stored.notes == "带电脑")
        #expect(stored.updatedAt == changedAt)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TodoTask>()) == 0)
        try service.delete(event)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<CalendarEvent>()) == 0)
    }

    @Test func invalidInputDoesNotInsertOrMutateData() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = CalendarEventService(context: container.mainContext, calendar: calendar)
        var draft = CalendarEventDraft(date: .now, calendar: calendar)
        draft.title = " \n "
        #expect(throws: CalendarEventError.self) { try service.create(draft: draft) }
        draft.title = "原始日程"
        let event = try service.create(draft: draft)
        draft.title = "不应保存"
        draft.endsAt = draft.startsAt.addingTimeInterval(-1)
        #expect(throws: CalendarEventError.self) { try service.update(event, draft: draft) }
        #expect(event.title == "原始日程")
        #expect(!container.mainContext.hasChanges)
    }

    @Test func allDayEndIsExclusiveAndEditingRoundTripsAcrossDST() throws {
        var calendar = calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = CalendarEventService(context: container.mainContext, calendar: calendar)
        var draft = CalendarEventDraft(date: day, calendar: calendar)
        draft.title = "全天事项"
        draft.isAllDay = true
        let event = try service.create(draft: draft)
        #expect(event.startsAt == day)
        #expect(event.endsAt.timeIntervalSince(event.startsAt) == 23 * 3600)
        let end = event.endsAt
        try service.update(event, draft: CalendarEventDraft(event: event, calendar: calendar))
        #expect(event.endsAt == end)
    }

    @Test func eventsAndTasksSurviveDiskContainerRecreation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelnoCalendarDisk-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Calendar.store")
        let id = try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            var draft = CalendarEventDraft(date: .now, calendar: calendar)
            draft.title = "重启保留日程"
            let event = try CalendarEventService(context: container.mainContext, calendar: calendar).create(draft: draft)
            try TaskService(context: container.mainContext).createTask(title: "收件箱也保留")
            return event.id
        }
        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let event = try #require(container.mainContext.fetch(FetchDescriptor<CalendarEvent>()).first)
            #expect(event.id == id)
            #expect(event.title == "重启保留日程")
            #expect(try container.mainContext.fetchCount(FetchDescriptor<TodoTask>()) == 1)
        }
    }
}
