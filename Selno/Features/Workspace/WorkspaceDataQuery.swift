import Foundation
import SwiftData

// MARK: - Query descriptors

enum WorkspaceDataQuery {
    static func activeTasks() -> FetchDescriptor<TodoTask> {
        let pending = TaskStatus.pending.rawValue
        let inProgress = TaskStatus.inProgress.rawValue
        let cancelled = TaskStatus.cancelled.rawValue
        // Cancelled tasks are terminal but still user-visible through an explicit
        // status filter or a global-scope module. They must be in the board's
        // universe even when they have no planned/due date.
        return FetchDescriptor(predicate: #Predicate<TodoTask> { task in
            task.archivedAt == nil
                && (task.statusRaw == pending || task.statusRaw == inProgress
                    || task.statusRaw == cancelled)
        }, sortBy: [SortDescriptor(\TodoTask.createdAt)])
    }

    /// Recently completed rows let statistics and "completed" filters work without
    /// loading years of history. Older completed tasks remain in the store and in
    /// JSON backups; they are simply outside the board's bounded window.
    static func completed(since cutoff: Date) -> FetchDescriptor<TodoTask> {
        let completed = TaskStatus.completed.rawValue
        let missing = Date.distantPast
        return FetchDescriptor(predicate: #Predicate<TodoTask> { task in
            task.archivedAt == nil && task.statusRaw == completed
                && (task.completedAt ?? missing) >= cutoff
        }, sortBy: [SortDescriptor(\TodoTask.updatedAt, order: .reverse)])
    }

    static func archived(since cutoff: Date) -> FetchDescriptor<TodoTask> {
        let missing = Date.distantPast
        return FetchDescriptor(predicate: #Predicate<TodoTask> { task in
            (task.archivedAt ?? missing) >= cutoff
        }, sortBy: [SortDescriptor(\TodoTask.updatedAt, order: .reverse)])
    }

    static func projects() -> FetchDescriptor<TodoProject> {
        FetchDescriptor(predicate: #Predicate<TodoProject> { $0.archivedAt == nil },
                        sortBy: [SortDescriptor(\TodoProject.updatedAt, order: .reverse)])
    }

    static func tags() -> FetchDescriptor<TaskCategory> {
        FetchDescriptor(sortBy: [SortDescriptor(\TaskCategory.sortOrder), SortDescriptor(\TaskCategory.name)])
    }

    static func savedViews() -> FetchDescriptor<SavedTaskView> {
        FetchDescriptor(sortBy: [SortDescriptor(\SavedTaskView.name)])
    }
}

// MARK: - Query plan

/// One plan per board, not per module. The plan unions the date windows needed by
/// the visible modules and clamps the result to a bounded lookback/lookahead.
nonisolated struct WorkspaceBoardQueryPlan: Hashable {
    let day: Date
    let monthWindow: CalendarWindow
    let range: DateInterval
    let signature: String

    var identity: String {
        "\(day.timeIntervalSince1970)|\(range.start.timeIntervalSince1970)|\(range.end.timeIntervalSince1970)|\(signature)"
    }

    static func make(
        workspace: WorkspaceSnapshot,
        savedViews: [SavedTaskViewSnapshot],
        now: Date,
        calendar: Calendar
    ) -> WorkspaceBoardQueryPlan {
        let today = calendar.startOfDay(for: now)
        let month = CalendarMath.window(containing: today, mode: .month, listRange: .month, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        var start = today
        var end = max(tomorrow, today.addingTimeInterval(1))

        let modules = workspace.orderedModules.filter(\.isKnownKind)
        if modules.contains(where: { $0.kind == .month }) {
            start = min(start, month.range.start)
            end = max(end, month.range.end)
        }
        if modules.contains(where: { $0.kind == .upcoming }) {
            end = max(end, calendar.date(byAdding: .day, value: 8, to: today) ?? end)
        }

        let viewsByID = Dictionary(uniqueKeysWithValues: savedViews.map { ($0.id, $0) })
        var filters: [TaskFilterExpression] = [workspace.filter]
        for module in modules {
            let resolved = WorkspaceFilterResolver.resolve(
                module: module, workspace: workspace.filter, savedViews: viewsByID
            )
            filters.append(resolved.filter)
        }
        for filter in filters {
            if let interval = TaskFilterEngine.requestedInterval(for: filter, now: now, calendar: calendar) {
                start = min(start, interval.start)
                end = max(end, interval.end)
            }
        }

        let lookback = calendar.date(byAdding: .day, value: -WorkspaceLimits.queryLookbackDays, to: today) ?? today
        let lookahead = calendar.date(byAdding: .day, value: WorkspaceLimits.queryLookaheadDays, to: today) ?? end
        start = max(start, lookback)
        end = min(end, lookahead)
        if end <= start { end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400) }
        let maximumEnd = calendar.date(byAdding: .day, value: WorkspaceLimits.maximumQuerySpanDays, to: start) ?? end
        if end > maximumEnd { end = maximumEnd }

        let viewSignature = savedViews
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)\($0.updatedAt.timeIntervalSince1970)" }
            .joined(separator: ",")
        let signature = workspace.layoutSignature + "|" + viewSignature

        return WorkspaceBoardQueryPlan(
            day: today,
            monthWindow: month,
            range: DateInterval(start: start, end: end),
            signature: signature
        )
    }
}

// MARK: - Scope resolution

nonisolated enum WorkspaceFilterResolver {
    static func resolve(
        module: WorkspaceModuleSnapshot,
        workspace: TaskFilterExpression,
        savedViews: [UUID: SavedTaskViewSnapshot]
    ) -> ResolvedTaskFilter {
        if let viewID = module.savedViewID, let view = savedViews[viewID] {
            return ResolvedTaskFilter(filter: view.filter, source: .custom)
        }
        return TaskFilterEngine.resolve(
            scope: module.dataScope,
            custom: module.config.filter,
            workspace: workspace
        )
    }
}

// MARK: - Board data

@MainActor
final class WorkspaceBoardData {
    let allTasks: [TodoTask]
    let events: [CalendarEvent]
    let milestones: [TaskMilestone]
    let projects: [TodoProject]
    let tags: [TaskCategory]
    let monthWindow: CalendarWindow
    let now: Date
    let calendar: Calendar

    private var taskCache: [TaskFilterExpression: [TodoTask]] = [:]
    private var milestoneCache: [TaskFilterExpression: [TaskMilestone]] = [:]
    private var projectionCache: [ProjectionKey: DashboardProjection] = [:]
    private var monthCache: [TaskFilterExpression: CalendarAgendaSnapshot] = [:]

    init(
        plan: WorkspaceBoardQueryPlan,
        activeTasks: [TodoTask],
        windowTasks: [TodoTask],
        recentCompleted: [TodoTask],
        archivedTasks: [TodoTask],
        events: [CalendarEvent],
        milestones: [TaskMilestone],
        projects: [TodoProject],
        tags: [TaskCategory],
        now: Date,
        calendar: Calendar
    ) {
        var seen = Set<UUID>()
        var union: [TodoTask] = []
        for task in activeTasks + windowTasks + recentCompleted + archivedTasks where seen.insert(task.id).inserted {
            union.append(task)
        }
        self.allTasks = union
        self.events = events.sorted { $0.startsAt == $1.startsAt ? $0.id.uuidString < $1.id.uuidString : $0.startsAt < $1.startsAt }
        self.milestones = milestones
        self.projects = projects
        self.tags = tags
        self.monthWindow = plan.monthWindow
        self.now = now
        self.calendar = calendar
    }

    var tagNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
    }

    var projectNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    }

    func tasks(matching filter: TaskFilterExpression) -> [TodoTask] {
        if let cached = taskCache[filter] { return cached }
        let result = allTasks.filter { filter.matches($0, now: now, calendar: calendar) }
        taskCache[filter] = result
        return result
    }

    func milestones(matching filter: TaskFilterExpression) -> [TaskMilestone] {
        if let cached = milestoneCache[filter] { return cached }
        let taskIDs = Set(tasks(matching: filter).map(\.id))
        let result = milestones.filter { node in
            node.task.map { taskIDs.contains($0.id) } ?? false
        }
        milestoneCache[filter] = result
        return result
    }

    func projection(filter: TaskFilterExpression, days: Int) -> DashboardProjection {
        let key = ProjectionKey(filter: filter, days: days == 7 ? 7 : 3)
        if let cached = projectionCache[key] { return cached }
        let result = DashboardProjection.build(
            tasks: tasks(matching: filter),
            events: events,
            now: now,
            days: key.days,
            monthWindow: monthWindow,
            calendar: calendar,
            milestones: milestones(matching: filter)
        )
        projectionCache[key] = result
        return result
    }

    func monthSnapshot(filter: TaskFilterExpression) -> CalendarAgendaSnapshot {
        if let cached = monthCache[filter] { return cached }
        let result = CalendarAgendaBuilder.build(
            tasks: tasks(matching: filter),
            events: events,
            window: monthWindow,
            calendar: calendar,
            milestones: milestones(matching: filter)
        )
        monthCache[filter] = result
        return result
    }

    func inboxTasks(filter: TaskFilterExpression, limit: Int) -> [TodoTask] {
        Array(tasks(matching: filter)
            .filter { $0.isInInbox && $0.status.isActive }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit))
    }

    func inboxCount(filter: TaskFilterExpression) -> Int {
        tasks(matching: filter).filter { $0.isInInbox && $0.status.isActive }.count
    }

    func taskList(
        filter: TaskFilterExpression,
        sort: TaskSortMode,
        limit: Int
    ) -> (visible: [TodoTask], total: Int) {
        let filtered = tasks(matching: filter)
        let sorted = sort.sort(filtered)
        return (Array(sorted.prefix(limit)), sorted.count)
    }

    func projectList(
        filter: TaskFilterExpression,
        limit: Int
    ) -> (visible: [TodoProject], total: Int) {
        let filtered: [TodoProject]
        if filter.projectIDs.isEmpty {
            filtered = projects
        } else {
            filtered = projects.filter { filter.projectIDs.contains($0.id) }
        }
        return (Array(filtered.prefix(limit)), filtered.count)
    }

    private struct ProjectionKey: Hashable {
        var filter: TaskFilterExpression
        var days: Int
    }
}

// MARK: - Statistics

nonisolated struct WorkspaceTaskStatistics: Equatable {
    var pending: Int
    var completedToday: Int
    var overdue: Int
    var dueSoon: Int

    @MainActor
    static func make(tasks: [TodoTask], now: Date, calendar: Calendar) -> WorkspaceTaskStatistics {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let soon = calendar.date(byAdding: .day, value: 3, to: today) ?? tomorrow

        var value = WorkspaceTaskStatistics(pending: 0, completedToday: 0, overdue: 0, dueSoon: 0)
        for task in tasks {
            if task.status.isActive {
                value.pending += 1
                if let due = task.dueAt {
                    if due < today { value.overdue += 1 }
                    else if due < soon { value.dueSoon += 1 }
                }
            } else if task.status == .completed, let completedAt = task.completedAt,
                      completedAt >= today, completedAt < tomorrow {
                value.completedToday += 1
            }
        }
        return value
    }
}