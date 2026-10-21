import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct CalendarAgendaTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .gmt
        return calendar
    }
    private var today: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000)) }

    @Test func sameDayTaskIsDeduplicatedAndDateRolesRemainDistinct() throws {
        let start = today
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let task = TodoTask(title: "同日三种日期")
        task.plannedAt = start.addingTimeInterval(3600)
        task.plannedStartAt = start.addingTimeInterval(1800)
        task.dueAt = start.addingTimeInterval(7200)
        let other = TodoTask(title: "跨日的计划与截止")
        other.plannedAt = start
        other.dueAt = tomorrow
        let undated = TodoTask(title: "收件箱不应混入")
        let window = CalendarMath.window(containing: start, mode: .month, listRange: .month, calendar: calendar)
        let snapshot = CalendarAgendaBuilder.build(tasks: [task, other, undated], events: [], window: window, calendar: calendar)
        let agenda = snapshot.agenda(on: start, calendar: calendar)
        #expect(agenda.tasks.count == 2)
        #expect(agenda.pendingCount == 2)
        let occurrence = try #require(agenda.tasks.first { $0.id == task.id })
        #expect(occurrence.roles == Set([.planned, .starts, .deadline]))
        #expect(snapshot.agenda(on: tomorrow, calendar: calendar).tasks.first?.roles == Set([.deadline]))
        #expect(undated.isInInbox)
    }

    @Test func timedAllDayAndZeroDurationEventsUseHalfOpenLocalDays() throws {
        let start = today
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let dayAfter = try #require(calendar.date(byAdding: .day, value: 2, to: start))
        let timed = CalendarEvent(title: "跨午夜", startsAt: tomorrow.addingTimeInterval(-3600), endsAt: tomorrow.addingTimeInterval(3600))
        let allDay = CalendarEvent(title: "全天两天", startsAt: start, endsAt: dayAfter, isAllDay: true)
        let endsAtMidnight = CalendarEvent(title: "午夜结束", startsAt: start.addingTimeInterval(3600), endsAt: tomorrow)
        let point = CalendarEvent(title: "零时长", startsAt: tomorrow, endsAt: tomorrow)
        let window = CalendarMath.window(containing: start, mode: .list, listRange: .thirtyDays, calendar: calendar)
        let snapshot = CalendarAgendaBuilder.build(tasks: [], events: [timed, allDay, endsAtMidnight, point], window: window, calendar: calendar)
        #expect(snapshot.agenda(on: start, calendar: calendar).events.count == 3)
        #expect(snapshot.agenda(on: tomorrow, calendar: calendar).events.count == 3)
        #expect(snapshot.agenda(on: dayAfter, calendar: calendar).events.isEmpty)
        #expect(!snapshot.agenda(on: tomorrow, calendar: calendar).events.contains { $0.id == endsAtMidnight.id })
    }

    @Test func databaseQueriesFetchOnlyTheVisibleRangeAndIncludeOverlap() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let window = CalendarMath.window(containing: today, mode: .week, listRange: .week, calendar: calendar)
        let inside = TodoTask(title: "范围内")
        inside.dueAt = today
        let outside = TodoTask(title: "多年以前")
        outside.plannedAt = calendar.date(byAdding: .year, value: -5, to: today)
        context.insert(inside)
        context.insert(outside)
        context.insert(TodoTask(title: "无日期"))
        let overlap = CalendarEvent(title: "从范围外跨入", startsAt: window.range.start.addingTimeInterval(-3600), endsAt: window.range.start.addingTimeInterval(3600))
        let outsideEvent = CalendarEvent(title: "范围结束时开始", startsAt: window.range.end, endsAt: window.range.end.addingTimeInterval(3600))
        context.insert(overlap)
        context.insert(outsideEvent)
        try context.save()
        #expect(try context.fetch(CalendarDataQuery.tasks(in: window.range)).map(\.id) == [inside.id])
        #expect(try context.fetch(CalendarDataQuery.events(in: window.range)).map(\.id) == [overlap.id])
    }

    @Test func reschedulingChangesOnlyPlannedDateAndPreservesTimeStatusAndDeadline() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let service = TaskService(context: context)
        let task = try service.createTask(title: "拖动任务")
        task.plannedAt = CalendarMath.defaultTime(on: today, calendar: calendar)
        task.plannedStartAt = today
        task.dueAt = today.addingTimeInterval(9 * 86400)
        try service.setStatus(.completed, for: task)
        let completion = task.completedAt
        let deadline = task.dueAt
        let destination = try #require(calendar.date(byAdding: .day, value: 3, to: today))
        try service.reschedule(taskID: task.id, to: destination, calendar: calendar)
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<TodoTask>()).first)
        #expect(calendar.isDate(try #require(stored.plannedAt), inSameDayAs: destination))
        #expect(calendar.component(.hour, from: try #require(stored.plannedAt)) == 9)
        #expect(stored.status == .completed)
        #expect(stored.completedAt == completion)
        #expect(stored.dueAt == deadline)
        #expect(stored.plannedStartAt == today)
    }

    @Test func calendarTaskCreationUsesPlanWithoutSettingDeadline() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        var draft = TaskDraft(plannedAt: CalendarMath.defaultTime(on: today, calendar: calendar))
        draft.title = "  日历创建  "
        let task = try TaskService(context: container.mainContext).createTask(draft: draft)
        #expect(task.title == "日历创建")
        #expect(task.plannedAt == draft.plannedAt)
        #expect(task.dueAt == nil)
        #expect(task.status == .pending)
    }

    @Test func mixedDailyCountsIncludeMultipleEventsAndOnlyActiveUnduplicatedTasks() {
        let first = TodoTask(title: "计划与截止同日")
        first.plannedAt = today
        first.dueAt = today
        let second = TodoTask(title: "另一条待办")
        second.dueAt = today
        let completed = TodoTask(title: "完成记录", status: .completed)
        completed.plannedAt = today
        let events = (0..<3).map { index in
            CalendarEvent(title: "日程 \(index)", startsAt: today.addingTimeInterval(Double(index + 9) * 3600),
                          endsAt: today.addingTimeInterval(Double(index + 9) * 3600 + 900))
        }
        let window = CalendarMath.window(containing: today, mode: .month, listRange: .month, calendar: calendar)
        let snapshot = CalendarAgendaBuilder.build(tasks: [first, second, completed], events: events, window: window, calendar: calendar)
        let day = snapshot.agenda(on: today, calendar: calendar)
        #expect(day.tasks.count == 3)
        #expect(day.pendingCount == 2)
        #expect(day.events.count == 3)
        #expect(Set(day.tasks.map(\.id)).count == 3)
    }
}
