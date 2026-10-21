import Foundation
import SwiftData

enum CalendarDataQuery {
    static func milestones(in range: DateInterval) -> FetchDescriptor<TaskMilestone> {
        let start = range.start, end = range.end
        return FetchDescriptor(predicate: #Predicate<TaskMilestone> {
            $0.isOnCalendar && $0.task?.archivedAt == nil && $0.date >= start && $0.date < end
        }, sortBy: [SortDescriptor(\TaskMilestone.date)])
    }
    static func tasks(in range: DateInterval) -> FetchDescriptor<TodoTask> {
        let start = range.start
        let end = range.end
        let missing = Date.distantPast
        let predicate = #Predicate<TodoTask> { task in
            task.archivedAt == nil && (
                ((task.plannedAt ?? missing) >= start && (task.plannedAt ?? missing) < end)
                || ((task.plannedStartAt ?? missing) >= start && (task.plannedStartAt ?? missing) < end)
                || ((task.dueAt ?? missing) >= start && (task.dueAt ?? missing) < end)
            )
        }
        return FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\TodoTask.createdAt)])
    }

    static func events(in range: DateInterval) -> FetchDescriptor<CalendarEvent> {
        let start = range.start
        let end = range.end
        let predicate = #Predicate<CalendarEvent> { event in
            event.startsAt < end && (event.endsAt > start || (event.startsAt == event.endsAt && event.startsAt >= start))
        }
        return FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\CalendarEvent.startsAt)])
    }
}
