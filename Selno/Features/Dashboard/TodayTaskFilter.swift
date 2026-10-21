import Foundation

enum TodayTaskFilter {
    static func includes(_ task: TodoTask, on date: Date, calendar: Calendar) -> Bool {
        guard task.status.isActive,
              let interval = calendar.dateInterval(of: .day, for: date) else { return false }
        let plannedToday = task.plannedAt.map { $0 >= interval.start && $0 < interval.end } ?? false
        let startsToday = task.plannedStartAt.map { $0 >= interval.start && $0 < interval.end } ?? false
        let dueTodayOrOverdue = task.dueAt.map { $0 < interval.end } ?? false
        return plannedToday || startsToday || dueTodayOrOverdue
    }
}
