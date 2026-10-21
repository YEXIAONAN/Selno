import SwiftUI
import SwiftData

enum TaskWorkspaceQuery {
    /// Archived rows are never shown by `TaskListScope`, so they are excluded
    /// at the store level for every scope. The Inbox scope also narrows to
    /// unplanned, unassigned rows; `TaskListScope.tasks` still applies the
    /// remaining in-memory rules (including status sections).
    static func tasks(for scope: TaskListScope) -> FetchDescriptor<TodoTask> {
        let predicate: Predicate<TodoTask> = scope == .inbox
            ? inboxPredicate()
            : #Predicate<TodoTask> { $0.archivedAt == nil }
        return FetchDescriptor<TodoTask>(
            predicate: predicate,
            sortBy: [SortDescriptor(\TodoTask.createdAt, order: .reverse)]
        )
    }

    /// `#Predicate` cannot type-check the archived/project/planned chain in
    /// reasonable time, and Foundation rejects a hand-built multi-component
    /// key path, so the relationship check is expressed as a flat map.
    private static func inboxPredicate() -> Predicate<TodoTask> {
        Predicate<TodoTask> { task in
            let unarchived = PredicateExpressions.build_Equal(
                lhs: PredicateExpressions.build_KeyPath(root: task, keyPath: \.archivedAt),
                rhs: PredicateExpressions.build_Arg(nil as Date?)
            )
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
            let planned = PredicateExpressions.build_Conjunction(
                lhs: unscheduledStart,
                rhs: unscheduled
            )
            let unplanned = PredicateExpressions.build_Conjunction(lhs: unassigned, rhs: planned)
            return PredicateExpressions.build_Conjunction(lhs: unarchived, rhs: unplanned)
        }
    }
}

struct TaskWorkspaceView: View {
    let scope: TaskListScope
    let calendar: Calendar
    var requestedTaskID: UUID? = nil
    var requestToken = UUID()

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            TaskWorkspaceContent(scope: scope, calendar: calendar, now: timeline.date,
                                 requestedTaskID: requestedTaskID, requestToken: requestToken)
                .id(calendar.startOfDay(for: timeline.date))
        }
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
    }
}

private struct TaskWorkspaceContent: View {
    @Query private var tasks: [TodoTask]
    @Query private var events: [CalendarEvent]
    let scope: TaskListScope
    let calendar: Calendar
    let requestedTaskID: UUID?
    let requestToken: UUID
    @State private var selection: Set<UUID> = []
    @State private var selectedEvent: CalendarEvent?
    @State private var focusRequest = 0

    init(scope: TaskListScope, calendar: Calendar, now: Date,
         requestedTaskID: UUID? = nil, requestToken: UUID = UUID()) {
        self.scope = scope
        self.calendar = calendar
        self.requestedTaskID = requestedTaskID
        self.requestToken = requestToken
        _selection = State(initialValue: requestedTaskID.map { [$0] } ?? [])
        _tasks = Query(TaskWorkspaceQuery.tasks(for: scope))
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        _events = Query(CalendarDataQuery.events(in: DateInterval(start: start, end: end)))
    }

    /// The store predicate covers archived/project/planned fields; the
    /// in-memory check also applies `isInInbox`'s complete definition and keeps
    /// the semantics in one place if the predicate is narrowed later.
    private var visibleTasks: [TodoTask] {
        scope == .inbox ? tasks.filter(\.isInInbox) : tasks
    }

    var body: some View {
        HSplitView {
            TaskListView(scope: scope, tasks: visibleTasks, selection: $selection, focusRequest: focusRequest,
                         events: scope == .today ? events : [], openEvent: {
                selection.removeAll()
                selectedEvent = $0
            })
            .frame(minWidth: 290, idealWidth: 370, maxWidth: 600, maxHeight: .infinity)
            Group {
                if selection.count == 1, let selectedTaskID = selection.first,
                   let task = visibleTasks.first(where: { $0.id == selectedTaskID }) {
                    TaskDetailView(task: task).id(task.id)
                } else if selection.count > 1 {
                    ContentUnavailableView {
                        Label("已选择 \(selection.count) 个任务", systemImage: "checklist")
                    } description: {
                        Text("在左侧批量操作栏中完成、添加标签、移动项目、归档或删除。")
                    }
                } else if let selectedEvent {
                    CalendarEventDetailView(event: selectedEvent, calendar: calendar, onDelete: { self.selectedEvent = nil })
                } else {
                    ContentUnavailableView {
                        Label("序宁", systemImage: "checkmark.circle")
                    } description: {
                        Text("让每一件事，都有条不紊。")
                        Text("选择一项安排，查看详情。")
                    }
                }
            }
            .frame(minWidth: 310, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(scope.title)
        .onChange(of: requestToken) { _, _ in
            guard let requestedTaskID else { return }
            selectedEvent = nil
            selection = [requestedTaskID]
        }
        .onChange(of: selection) { _, ids in
            if !ids.isEmpty { selectedEvent = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selnoDataDidChange)) { _ in
            // A replace import can delete the rows behind these transient selections.
            selection.removeAll()
            selectedEvent = nil
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { focusRequest += 1 } label: { Label("新建任务", systemImage: "plus") }
                    .help("新建任务（⌘N）")
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("task.new")
            }
        }
    }
}
