import Foundation

enum TaskDateRole: Int, CaseIterable {
    case planned, starts, deadline
    var title: String {
        switch self {
        case .planned: "计划执行"
        case .starts: "计划开始"
        case .deadline: "最终截止"
        }
    }
}

struct CalendarTaskOccurrence: Identifiable {
    let task: TodoTask
    var roles: Set<TaskDateRole>
    var milestones: [TaskMilestone] = []
    var id: UUID { task.id }
    var roleTitle: String { (roles.sorted { $0.rawValue < $1.rawValue }.map(\.title) + milestones.map { "节点：\($0.title)" }).joined(separator: " · ") }
    var shortRoleTitle: String {
        (roles.sorted { $0.rawValue < $1.rawValue }.map {
            switch $0 {
            case .planned: "计划"
            case .starts: "开始"
            case .deadline: "截止"
            }
        } + milestones.map(\.title)).joined(separator: "/")
    }
}

struct DayAgenda: Identifiable {
    let date: Date
    var tasks: [CalendarTaskOccurrence] = []
    var events: [CalendarEvent] = []
    var id: Date { date }
    var pendingCount: Int { tasks.filter { $0.task.status.isActive }.count }
    var isEmpty: Bool { tasks.isEmpty && events.isEmpty }
}

struct CalendarAgendaSnapshot {
    var days: [Date: DayAgenda] = [:]

    func agenda(on date: Date, calendar: Calendar) -> DayAgenda {
        let day = calendar.startOfDay(for: date)
        return days[day] ?? DayAgenda(date: day)
    }
}

enum CalendarAgendaBuilder {
    static func build(tasks: [TodoTask], events: [CalendarEvent], window: CalendarWindow, calendar: Calendar, milestones: [TaskMilestone] = []) -> CalendarAgendaSnapshot {
        var days = Dictionary(uniqueKeysWithValues: window.days.map { ($0, DayAgenda(date: $0)) })
        for task in tasks {
            var occurrences: [Date: Set<TaskDateRole>] = [:]
            let dates: [(Date?, TaskDateRole)] = [(task.plannedAt, .planned), (task.plannedStartAt, .starts), (task.dueAt, .deadline)]
            for (date, role) in dates {
                guard let date, date >= window.range.start, date < window.range.end else { continue }
                occurrences[calendar.startOfDay(for: date), default: []].insert(role)
            }
            for (day, roles) in occurrences {
                days[day]?.tasks.append(CalendarTaskOccurrence(task: task, roles: roles))
            }
        }
        for node in milestones where node.isOnCalendar && node.date >= window.range.start && node.date < window.range.end {
            guard let task = node.task else { continue }
            let day = calendar.startOfDay(for: node.date)
            if let index = days[day]?.tasks.firstIndex(where: { $0.id == task.id }) { days[day]?.tasks[index].milestones.append(node) }
            else { days[day]?.tasks.append(CalendarTaskOccurrence(task: task, roles: [], milestones: [node])) }
        }
        for event in events {
            for day in window.days {
                guard let interval = calendar.dateInterval(of: .day, for: day),
                      intersects(event, interval: interval) else { continue }
                days[day]?.events.append(event)
            }
        }
        for day in window.days {
            days[day]?.tasks.sort {
                if $0.task.status.isActive != $1.task.status.isActive { return $0.task.status.isActive }
                if $0.task.importance != $1.task.importance { return $0.task.importance.sortPriority > $1.task.importance.sortPriority }
                if $0.task.createdAt != $1.task.createdAt { return $0.task.createdAt < $1.task.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            days[day]?.events.sort {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
        return CalendarAgendaSnapshot(days: days)
    }

    static func intersects(_ event: CalendarEvent, interval: DateInterval) -> Bool {
        if event.startsAt == event.endsAt {
            return event.startsAt >= interval.start && event.startsAt < interval.end
        }
        return event.startsAt < interval.end && event.endsAt > interval.start
    }

    static func eventTime(_ event: CalendarEvent, calendar: Calendar) -> String {
        if event.isAllDay { return "全天" }
        let suffix = calendar.isDate(event.startsAt, inSameDayAs: event.endsAt) ? "" : " · 跨日"
        return "\(CalendarMath.time(event.startsAt, calendar: calendar))–\(CalendarMath.time(event.endsAt, calendar: calendar))\(suffix)"
    }
}
