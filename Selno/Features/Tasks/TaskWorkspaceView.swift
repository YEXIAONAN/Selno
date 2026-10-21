import SwiftUI
import SwiftData

struct TaskWorkspaceView: View {
    let scope: TaskListScope
    let calendar: Calendar

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            TaskWorkspaceContent(scope: scope, calendar: calendar, now: timeline.date)
                .id(calendar.startOfDay(for: timeline.date))
        }
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
    }
}

private struct TaskWorkspaceContent: View {
    @Query(sort: \TodoTask.createdAt, order: .reverse) private var tasks: [TodoTask]
    @Query private var events: [CalendarEvent]
    let scope: TaskListScope
    let calendar: Calendar
    @State private var selectedTaskID: UUID?
    @State private var selectedEvent: CalendarEvent?
    @State private var focusRequest = 0

    init(scope: TaskListScope, calendar: Calendar, now: Date) {
        self.scope = scope
        self.calendar = calendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        _events = Query(CalendarDataQuery.events(in: DateInterval(start: start, end: end)))
    }

    var body: some View {
        HSplitView {
            TaskListView(scope: scope, tasks: tasks, selectedTaskID: $selectedTaskID, focusRequest: focusRequest,
                         events: scope == .today ? events : [], openEvent: {
                selectedTaskID = nil
                selectedEvent = $0
            })
            .frame(minWidth: 290, idealWidth: 370, maxWidth: 600, maxHeight: .infinity)
            Group {
                if let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) {
                    TaskDetailView(task: task).id(task.id)
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
