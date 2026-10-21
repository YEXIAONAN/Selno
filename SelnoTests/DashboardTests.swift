import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct DashboardTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
    private func projection(_ tasks: [TodoTask], events: [CalendarEvent] = [], days: Int = 7) -> DashboardProjection {
        DashboardProjection.build(tasks: tasks, events: events, now: today, days: days,
                                  monthWindow: CalendarMath.window(containing: today, mode: .month, listRange: .month, calendar: calendar), calendar: calendar)
    }

    @Test func focusDeduplicatesRolesAndPrioritizesUrgencyThenImportance() {
        let plan = TodoTask(title: "普通计划")
        plan.plannedAt = today
        let important = TodoTask(title: "重要计划", importance: .high)
        important.plannedAt = today
        let due = TodoTask(title: "今日截止")
        due.plannedAt = today; due.plannedStartAt = today; due.dueAt = today
        let overdue = TodoTask(title: "逾期")
        overdue.dueAt = day(-10)
        let complete = TodoTask(title: "已完成", status: .completed)
        complete.plannedAt = today
        let cancelled = TodoTask(title: "已取消", status: .cancelled)
        cancelled.dueAt = day(-1)
        let result = projection([plan, due, important, overdue, complete, cancelled, due, TodoTask(title: "无日期")])
        #expect(result.focus.map(\.id) == [overdue.id, due.id, important.id, plan.id])
        #expect(result.focus[1].roles == Set([.planned, .starts, .deadline]))
        #expect(result.overdueCount == 1)
    }

    @Test func upcomingShowsOneNextCommitmentAndExcludesFocusItems() throws {
        let todayTask = TodoTask(title: "今天计划未来截止")
        todayTask.plannedAt = today; todayTask.dueAt = day(3)
        let nextTask = TodoTask(title: "未来计划截止")
        nextTask.plannedAt = day(2); nextTask.dueAt = day(4)
        let combined = TodoTask(title: "未来同日")
        combined.plannedAt = day(3); combined.dueAt = day(3)
        let fallback = TodoTask(title: "只有截止")
        fallback.dueAt = day(1)
        let result = projection([todayTask, nextTask, combined, fallback])
        let occurrences = result.upcoming.flatMap(\.tasks)
        #expect(occurrences.count == 3)
        #expect(Set(occurrences.map(\.id)).count == 3)
        #expect(!occurrences.contains { $0.id == todayTask.id })
        #expect(result.upcoming.first?.date == day(1))
        #expect(try #require(occurrences.first { $0.id == nextTask.id }).roles == Set([.planned]))
        #expect(try #require(occurrences.first { $0.id == combined.id }).roles == Set([.planned, .deadline]))
        #expect(projection([nextTask], days: 3).upcoming.count == 1)
    }

    @Test func upcomingHonorsLocalDayRangeAndDeduplicatesMultidayEvents() {
        let continuing = CalendarEvent(title: "今天持续到后天", startsAt: today, endsAt: day(2), isAllDay: true)
        let future = CalendarEvent(title: "未来跨日", startsAt: day(1), endsAt: day(4), isAllDay: true)
        let midnight = CalendarEvent(title: "边界外", startsAt: day(4), endsAt: day(4))
        let result = projection([], events: [continuing, future, midnight], days: 3)
        #expect(result.todayEvents.map(\.id) == [continuing.id])
        #expect(result.upcoming.flatMap(\.events).map(\.id) == [future.id])
        // The mini calendar still represents every day of an overlapping event.
        #expect(result.month.agenda(on: day(2), calendar: calendar).events.map(\.id).contains(future.id))
    }

    @Test func boundedDashboardQueryIncludesActiveOverdueButNotUndatedOrOldCompleted() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let overdue = TodoTask(title: "很久以前仍逾期")
        overdue.dueAt = calendar.date(byAdding: .year, value: -5, to: today)
        let oldComplete = TodoTask(title: "很久以前已完成", status: .completed)
        oldComplete.dueAt = overdue.dueAt
        let oldPlan = TodoTask(title: "旧计划不自动当逾期")
        oldPlan.plannedAt = overdue.dueAt
        let future = TodoTask(title: "范围内")
        future.plannedAt = day(2)
        for task in [overdue, oldComplete, oldPlan, future, TodoTask(title: "无日期")] { context.insert(task) }
        try context.save()
        let found = try context.fetch(CalendarDataQuery.tasks(in: DateInterval(start: today, end: day(8))))
            + context.fetch(DashboardDataQuery.overdue(before: today))
        #expect(Set(found.map(\.id)) == Set([overdue.id, future.id]))
    }

    @Test func inboxSnapshotIsLimitedButCountIncludesAllActiveUnarrangedTasks() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let service = TaskService(context: context)
        for index in 0..<7 { try service.createTask(title: "收件箱 \(index)") }
        let dueOnly = try service.createTask(title: "只有截止仍遵循原 Inbox 规则")
        dueOnly.dueAt = day(3)
        let completed = try service.createTask(title: "已完成不计待整理")
        try service.setStatus(.completed, for: completed)
        let project = try ProjectService(context: context).save(name: "项目", notes: "")
        try service.createTask(title: "项目任务", project: project)
        let archived = try service.createTask(title: "已归档但仍符合旧规则")
        archived.archivedAt = day(-1)
        try context.save()
        let visible = try context.fetch(DashboardDataQuery.inbox(limit: 4))
        #expect(visible.count == 4)
        #expect(visible.allSatisfy { !$0.isArchived })
        #expect(try context.fetchCount(DashboardDataQuery.inbox()) == 8)
    }

    @Test func projectsHaveRealProgressAndProjectTasksPersistWithoutEnteringInbox() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let project = try ProjectService(context: context).save(name: "  发布准备  ", notes: "项目备注")
        let service = TaskService(context: context)
        let first = try service.createTask(title: "第一项", project: project)
        let second = try service.createTask(title: "第二项", project: project)
        second.dueAt = day(-1)
        try service.toggleCompletion(first)
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<TodoProject>()).first)
        let progress = ProjectProgress(project: stored, now: today, calendar: calendar)
        #expect(stored.name == "发布准备")
        #expect(progress.total == 2 && progress.completed == 1 && progress.overdue == 1)
        #expect(progress.fraction == 0.5)
        #expect(!second.isInInbox)
        #expect(second.dueAt == day(-1) && second.plannedAt == nil)
    }

    @Test func invalidProjectNameDoesNotInsertAndEditingKeepsIdentity() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let service = ProjectService(context: container.mainContext)
        #expect(throws: ProjectValidationError.self) { try service.save(name: " \n ", notes: "") }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TodoProject>()) == 0)
        let project = try service.save(name: "原名称", notes: "")
        let id = project.id
        let edited = try service.save(project: project, name: "新名称", notes: "新备注")
        #expect(edited.id == id && edited.notes == "新备注")
    }

    @Test func nextDaysRemainCalendarDaysAcrossDST() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(local.date(from: DateComponents(year: 2026, month: 3, day: 7)))
        let future = TodoTask(title: "夏令时之后")
        future.plannedAt = local.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 30))
        let month = CalendarMath.window(containing: start, mode: .month, listRange: .month, calendar: local)
        let result = DashboardProjection.build(tasks: [future], events: [], now: start, days: 3, monthWindow: month, calendar: local)
        #expect(result.upcoming.count == 1)
        #expect(local.component(.day, from: try #require(result.upcoming.first?.date)) == 9)
    }
}
