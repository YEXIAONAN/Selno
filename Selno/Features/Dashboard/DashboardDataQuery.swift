import Foundation
import SwiftData

enum DashboardDataQuery {
    static func overdue(before today: Date) -> FetchDescriptor<TodoTask> {
        let missing = Date.distantFuture
        return FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { task in
            task.archivedAt == nil
                && (task.statusRaw == "pending" || task.statusRaw == "inProgress")
                && (task.dueAt ?? missing) < today
        }, sortBy: [SortDescriptor(\TodoTask.createdAt)])
    }

    static func inbox(limit: Int? = nil) -> FetchDescriptor<TodoTask> {
        let active = [TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue]
        let predicate = #Predicate<TodoTask> { task in
            task.project?.id == nil && task.plannedAt == nil && task.plannedStartAt == nil && active.contains(task.statusRaw)
        }
        var descriptor = FetchDescriptor<TodoTask>(predicate: predicate, sortBy: [SortDescriptor(\TodoTask.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return descriptor
    }

    static func projects(limit: Int? = nil) -> FetchDescriptor<TodoProject> {
        var descriptor = FetchDescriptor<TodoProject>(predicate: #Predicate<TodoProject> { $0.archivedAt == nil },
                                         sortBy: [SortDescriptor(\TodoProject.updatedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return descriptor
    }
}
