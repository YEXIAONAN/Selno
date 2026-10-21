import SwiftUI
import SwiftData

struct CalendarRangeContent: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query private var events: [CalendarEvent]
    @Query private var milestones: [TaskMilestone]
    let window: CalendarWindow
    let displayDate: Date
    let mode: CalendarViewMode
    let calendar: Calendar
    @Binding var selectedDate: Date
    @Binding var isPanelOpen: Bool
    @State private var snapshot = CalendarAgendaSnapshot()
    @State private var selection: AgendaSelection?
    @State private var presentedError: PresentedError?

    init(window: CalendarWindow, displayDate: Date, mode: CalendarViewMode, calendar: Calendar,
         selectedDate: Binding<Date>, isPanelOpen: Binding<Bool>) {
        self.window = window
        self.displayDate = displayDate
        self.mode = mode
        self.calendar = calendar
        _selectedDate = selectedDate
        _isPanelOpen = isPanelOpen
        _tasks = Query(CalendarDataQuery.tasks(in: window.range))
        _events = Query(CalendarDataQuery.events(in: window.range))
        _milestones = Query(CalendarDataQuery.milestones(in: window.range))
    }

    // Group only when the fetched data changes; hovering and selection reuse the snapshot.
    private var revision: [String] {
        tasks.map { "t\($0.id)\($0.updatedAt.timeIntervalSince1970)\($0.statusRaw)\(String(describing: $0.plannedAt))\(String(describing: $0.dueAt))\(String(describing: $0.plannedStartAt))" }
        + events.map { "e\($0.id)\($0.updatedAt.timeIntervalSince1970)\($0.startsAt.timeIntervalSince1970)\($0.endsAt.timeIntervalSince1970)" }
        + milestones.map { "n\($0.id)\($0.title)\($0.date.timeIntervalSince1970)\($0.isOnCalendar)\($0.task?.statusRaw ?? "")" }
    }

    var body: some View {
        HSplitView {
            GeometryReader { geometry in
                ScrollView {
                    if mode == .list {
                        CalendarListView(window: window, selectedDate: selectedDate, snapshot: snapshot,
                                         calendar: calendar, selectDate: select, open: { selection = $0 }, toggleTask: toggle)
                    } else {
                        TimelineView(.everyMinute) { timeline in
                            let rows = max(1, window.days.count / 7)
                            let dayHeight = mode == .week ? max(300, geometry.size.height - 60)
                                : max(96, (geometry.size.height - 60 - CGFloat(rows - 1) * 4) / CGFloat(rows))
                            CalendarGridView(window: window, displayDate: displayDate, selectedDate: selectedDate,
                                             mode: mode, calendar: calendar, snapshot: snapshot,
                                             now: timeline.date, dayHeight: dayHeight,
                                             selectDate: select, open: { selection = $0 }, reschedule: reschedule)
                                .padding(12)
                        }
                    }
                }
            }
            .frame(minWidth: 510, maxWidth: .infinity, maxHeight: .infinity)
            if isPanelOpen {
                DayAgendaView(agenda: snapshot.agenda(on: selectedDate, calendar: calendar), calendar: calendar,
                              close: { isPanelOpen = false }, open: { selection = $0 }, toggleTask: toggle)
            }
        }
        .onChange(of: revision, initial: true) { _, _ in
            snapshot = CalendarAgendaBuilder.build(tasks: tasks, events: events, window: window, calendar: calendar, milestones: milestones)
        }
        .sheet(item: $selection) { AgendaDetailsSheet(selection: $0, calendar: calendar) }
        .alert(item: $presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("好")))
        }
    }

    private func select(_ day: Date) {
        selectedDate = calendar.startOfDay(for: day)
        isPanelOpen = true
    }

    private func toggle(_ task: TodoTask) {
        do { try TaskService(context: context).toggleCompletion(task) }
        catch { presentedError = PresentedError("无法更新任务", error: error) }
    }

    private func reschedule(_ id: UUID, _ day: Date) -> Bool {
        do {
            try TaskService(context: context).reschedule(taskID: id, to: day, calendar: calendar)
            selectedDate = calendar.startOfDay(for: day)
            isPanelOpen = true
            return true
        } catch {
            presentedError = PresentedError("无法调整计划日期", error: error)
            return false
        }
    }
}
