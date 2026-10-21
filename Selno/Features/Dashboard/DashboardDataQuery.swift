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
        let predicate = Predicate<TodoTask> { task in
            // `#Predicate` cannot type-check six chained conditions in reasonable
            // time, so the standard expression tree is built explicitly.
            let unarchived = PredicateExpressions.build_Equal(
                lhs: PredicateExpressions.build_KeyPath(root: task, keyPath: \.archivedAt),
                rhs: PredicateExpressions.build_Arg(nil as Date?)
            )
            // Foundation rejects multi-component key paths in a hand-built
            // predicate, so optional chaining is expressed as a flat map.
            let project = PredicateExpressions.build_KeyPath(root: task, keyPath: \.project)
            let projectID = PredicateExpressions.build_flatMap(project) { project in
                PredicateExpressions.build_KeyPath(root: project, keyPath: \.id)
            }
            let unassigned = PredicateExpressions.build_Equal(
                lhs: projectID,
                rhs: PredicateExpressions.build_Arg(nil as UUID?)
            )
            let unscheduledStart = PredicateExpressions.build_Equal(
                lhs: PredicateExpressions.build_KeyPath(root: task, keyPath: \.plannedStartAt),
                rhs: PredicateExpressions.build_Arg(nil as Date?)
            )
            let unscheduled = PredicateExpressions.build_Equal(
                lhs: PredicateExpressions.build_KeyPath(root: task, keyPath: \.plannedAt),
                rhs: PredicateExpressions.build_Arg(nil as Date?)
            )
            let notCompleted = PredicateExpressions.build_NotEqual(
                lhs: PredicateExpressions.build_KeyPath(root: task, keyPath: \.statusRaw),
                rhs: PredicateExpressions.build_Arg(TaskStatus.completed.rawValue)
            )
            let notCancelled = PredicateExpressions.build_NotEqual(
                lhs: PredicateExpressions.build_KeyPath(root: task, keyPath: \.statusRaw),
                rhs: PredicateExpressions.build_Arg(TaskStatus.cancelled.rawValue)
            )
            let unassignedAndUnscheduled = PredicateExpressions.build_Conjunction(
                lhs: unassigned,
                rhs: unscheduledStart
            )
            let scheduled = PredicateExpressions.build_Conjunction(
                lhs: unassignedAndUnscheduled,
                rhs: unscheduled
            )
            let active = PredicateExpressions.build_Conjunction(
                lhs: notCompleted,
                rhs: notCancelled
            )
            let visible = PredicateExpressions.build_Conjunction(
                lhs: unarchived,
                rhs: scheduled
            )
            return PredicateExpressions.build_Conjunction(lhs: visible, rhs: active)
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
