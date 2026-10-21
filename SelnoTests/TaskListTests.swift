import Foundation
import Testing
@testable import Selno

@MainActor
struct TaskListTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    @Test func todayIncludesPlannedDueAndOverdueOnlyOnceAndExcludesClosedTasks() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let start = calendar.startOfDay(for: now)
        let planned = TodoTask(title: "今天计划")
        planned.plannedAt = start.addingTimeInterval(100)
        let starting = TodoTask(title: "今天开始")
        starting.plannedStartAt = start.addingTimeInterval(200)
        let due = TodoTask(title: "今天截止")
        due.dueAt = start.addingTimeInterval(300)
        let overdue = TodoTask(title: "已逾期")
        overdue.dueAt = start.addingTimeInterval(-1)
        let both = TodoTask(title: "同日计划与截止")
        both.plannedAt = start.addingTimeInterval(400)
        both.dueAt = start.addingTimeInterval(500)
        let future = TodoTask(title: "明天")
        future.dueAt = calendar.date(byAdding: .day, value: 1, to: start)
        let completed = TodoTask(title: "已完成", status: .completed)
        completed.dueAt = start
        let cancelled = TodoTask(title: "已取消", status: .cancelled)
        cancelled.dueAt = start
        let inbox = TodoTask(title: "未安排")
        let result = TaskListScope.today.tasks(
            from: [planned, starting, due, overdue, both, future, completed, cancelled, inbox],
            on: now, calendar: calendar
        )
        #expect(Set(result.map(\.id)) == Set([planned, starting, due, overdue, both].map(\.id)))
        #expect(result.count == 5)
        #expect(result.first?.id == overdue.id)
        #expect(due.urgency(on: now, calendar: calendar) == .dueToday)
        #expect(overdue.urgency(on: now, calendar: calendar) == .overdue)
        #expect(future.urgency(on: now, calendar: calendar) == .upcoming)
        #expect(completed.urgency(on: now, calendar: calendar) == .unscheduled)
    }

    @Test func inboxKeepsCompletedRecordsAndExcludesAssignedOrPlannedTasks() {
        let now = Date.now
        let inbox = TodoTask(title: "收件箱")
        let completed = TodoTask(title: "完成记录", status: .completed)
        let dueOnly = TodoTask(title: "只有截止日期")
        dueOnly.dueAt = now
        let projectTask = TodoTask(title: "项目任务")
        projectTask.project = TodoProject(name: "项目")
        let planned = TodoTask(title: "已计划")
        planned.plannedAt = now
        let starting = TodoTask(title: "已安排开始")
        starting.plannedStartAt = now
        let tasks = [inbox, completed, dueOnly, projectTask, planned, starting]
        let result = TaskListScope.inbox.tasks(from: tasks, on: now, calendar: calendar)
        #expect(Set(result.map(\.id)) == Set([inbox.id, completed.id, dueOnly.id]))
        #expect(result.last?.id == completed.id)
        #expect(TaskListScope.all.tasks(from: tasks, on: now, calendar: calendar).count == tasks.count)
    }

    @Test func prioritySortIsStableAndDayBoundariesFollowCalendar() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let normal = TodoTask(title: "普通", now: now)
        let high = TodoTask(title: "重要", importance: .high, now: now)
        let low = TodoTask(title: "低", importance: .low, now: now)
        let result = TaskListScope.all.tasks(from: [low, normal, high], on: now, calendar: calendar)
        #expect(result.map(\.id) == [high.id, normal.id, low.id])
        var shanghai = calendar
        shanghai.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .gmt
        let task = TodoTask(title: "本地今天")
        let start = shanghai.startOfDay(for: now)
        task.plannedAt = start
        #expect(TodayTaskFilter.includes(task, on: now, calendar: shanghai))
        task.plannedAt = shanghai.date(byAdding: .day, value: 1, to: start)
        #expect(!TodayTaskFilter.includes(task, on: now, calendar: shanghai))
    }
}
