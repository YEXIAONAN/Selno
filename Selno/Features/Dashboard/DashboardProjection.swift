import Foundation

struct FocusTask: Identifiable {
    let task: TodoTask
    let roles: Set<TaskDateRole>
    let isOverdue: Bool
    var milestoneTitles: [String] = []
    var id: UUID { task.id }
    var subtitle: String {
        var labels = isOverdue ? ["已逾期"] : []
        labels += milestoneTitles
        labels += roles.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        if task.importance == .high { labels.append("重要") }
        return labels.joined(separator: " · ")
    }
}

struct DashboardProjection {
    var focus: [FocusTask] = []
    var todayEvents: [CalendarEvent] = []
    var upcoming: [DayAgenda] = []
    var month = CalendarAgendaSnapshot()
    var overdueCount: Int { focus.filter(\.isOverdue).count }

    static func build(tasks: [TodoTask], events: [CalendarEvent], now: Date, days: Int,
                      monthWindow: CalendarWindow, calendar: Calendar, milestones: [TaskMilestone] = []) -> Self {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: days + 1, to: today) ?? tomorrow
        let todayInterval = DateInterval(start: today, end: tomorrow)
        var result = Self()
        var taskIDs = Set<UUID>()
        let uniqueTasks = tasks.filter { taskIDs.insert($0.id).inserted }
        // Use the same local-day rules as the standalone Today page and calendar.
        var seen = Set<UUID>()
        for task in uniqueTasks where TodayTaskFilter.includes(task, on: today, calendar: calendar) && seen.insert(task.id).inserted {
            let dates: [(Date?, TaskDateRole)] = [(task.plannedAt, .planned), (task.plannedStartAt, .starts), (task.dueAt, .deadline)]
            let roles = Set(dates.compactMap { date, role in
                date.map { $0 >= today && $0 < tomorrow } == true ? role : nil
            })
            result.focus.append(FocusTask(task: task, roles: roles, isOverdue: task.dueAt.map { $0 < today } ?? false))
        }
        for node in milestones where node.isOnCalendar && node.date >= today && node.date < tomorrow {
            guard let task = node.task, task.status.isActive else { continue }
            let title = "节点：\(node.title)"
            if let index = result.focus.firstIndex(where: { $0.id == task.id }) { result.focus[index].milestoneTitles.append(title) }
            else { seen.insert(task.id); result.focus.append(FocusTask(task: task, roles: [], isOverdue: false, milestoneTitles: [title])) }
        }
        result.focus.sort {
            if $0.isOverdue != $1.isOverdue { return $0.isOverdue }
            let leftDue = $0.roles.contains(.deadline), rightDue = $1.roles.contains(.deadline)
            if leftDue != rightDue { return leftDue }
            if $0.task.importance != $1.task.importance { return $0.task.importance.sortPriority > $1.task.importance.sortPriority }
            if $0.task.dueAt != $1.task.dueAt { return ($0.task.dueAt ?? .distantFuture) < ($1.task.dueAt ?? .distantFuture) }
            if $0.task.createdAt != $1.task.createdAt { return $0.task.createdAt < $1.task.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        result.todayEvents = events.filter { CalendarAgendaBuilder.intersects($0, interval: todayInterval) }
            .sorted { $0.isAllDay != $1.isAllDay ? $0.isAllDay : $0.startsAt < $1.startsAt }
        let upcomingWindow = CalendarWindow(range: DateInterval(start: tomorrow, end: end),
                                            days: CalendarMath.days(in: DateInterval(start: tomorrow, end: end), calendar: calendar))
        var groups = Dictionary(uniqueKeysWithValues: upcomingWindow.days.map { ($0, DayAgenda(date: $0)) })
        // A task gets one next action here; full calendar retains every distinct date role.
        // Today's focus is excluded so the dashboard never repeats the same task in two modules.
        for task in uniqueTasks where task.status.isActive && seen.insert(task.id).inserted {
            let dates: [(Date?, TaskDateRole)] = [(task.plannedAt, .planned), (task.plannedStartAt, .starts), (task.dueAt, .deadline)]
            let candidates = dates.compactMap { date, role -> (Date, TaskDateRole)? in
                guard let date, date >= tomorrow, date < end else { return nil }
                return (date, role)
            }
            // Show the earliest commitment, retaining all roles when they fall on that day.
            guard let first = candidates.map(\.0).min() else { continue }
            let day = calendar.startOfDay(for: first)
            let roles = Set(candidates.filter { calendar.isDate($0.0, inSameDayAs: day) }.map(\.1))
            groups[day]?.tasks.append(CalendarTaskOccurrence(task: task, roles: roles))
        }
        for node in milestones where node.isOnCalendar && node.date >= tomorrow && node.date < end {
            guard let task = node.task, task.status.isActive, !result.focus.contains(where: { $0.id == task.id }) else { continue }
            let target = calendar.startOfDay(for: node.date)
            let existing = upcomingWindow.days.first { groups[$0]?.tasks.contains(where: { $0.id == task.id }) == true }
            if let existing, existing < target { continue }
            if let existing, existing == target, let index = groups[target]?.tasks.firstIndex(where: { $0.id == task.id }) {
                groups[target]?.tasks[index].milestones.append(node)
            } else {
                if let existing { groups[existing]?.tasks.removeAll { $0.id == task.id } }
                groups[target]?.tasks.append(CalendarTaskOccurrence(task: task, roles: [], milestones: [node]))
            }
        }
        let todayIDs = Set(result.todayEvents.map(\.id))
        var eventIDs = todayIDs
        for event in events.sorted(by: { $0.startsAt < $1.startsAt }) where eventIDs.insert(event.id).inserted {
            guard let day = upcomingWindow.days.first(where: {
                calendar.dateInterval(of: .day, for: $0).map { CalendarAgendaBuilder.intersects(event, interval: $0) } ?? false
            }) else { continue }
            groups[day]?.events.append(event)
        }
        result.upcoming = upcomingWindow.days.compactMap { day in
            guard var group = groups[day], !group.isEmpty else { return nil }
            group.tasks.sort {
                if $0.task.importance != $1.task.importance { return $0.task.importance.sortPriority > $1.task.importance.sortPriority }
                return $0.id.uuidString < $1.id.uuidString
            }
            return group
        }
        result.month = CalendarAgendaBuilder.build(tasks: uniqueTasks, events: events, window: monthWindow, calendar: calendar, milestones: milestones)
        return result
    }
}

struct ProjectProgress {
    let total: Int
    let completed: Int
    let overdue: Int
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    init(project: TodoProject, now: Date, calendar: Calendar) {
        let tasks = project.tasks ?? []
        total = tasks.count
        completed = tasks.filter { $0.status == .completed }.count
        overdue = tasks.filter { $0.status.isActive && ($0.dueAt.map { $0 < calendar.startOfDay(for: now) } ?? false) }.count
    }
}
