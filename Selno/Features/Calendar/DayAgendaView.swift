import SwiftUI

private enum AgendaCreation: String, Identifiable {
    case task, event
    var id: String { rawValue }
}

struct DayAgendaView: View {
    let agenda: DayAgenda
    let calendar: Calendar
    let close: () -> Void
    let open: (AgendaSelection) -> Void
    let toggleTask: (TodoTask) -> Void
    @State private var creation: AgendaCreation?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("当日安排", systemImage: "list.bullet.rectangle").font(.headline)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭当日安排")
                        .accessibilityIdentifier("agenda.close")
                }
                Text(CalendarMath.fullDate(agenda.date, calendar: calendar))
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("agenda.date")
                HStack {
                    Text("\(agenda.pendingCount) 项待办 · \(agenda.events.count) 项日程")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("agenda.counts")
                    Spacer()
                    Menu {
                        Button("新建任务") { creation = .task }.accessibilityIdentifier("agenda.newTask")
                        Button("新建日程") { creation = .event }.accessibilityIdentifier("agenda.newEvent")
                    } label: { Label("新建", systemImage: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityIdentifier("agenda.new")
                }
            }
            .padding(16)
            Rectangle().fill(WorkspaceStyle.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if agenda.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("暂无安排").font(.headline)
                            Text("为这一天添加要做的任务，或需要按时参加的日程。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Button("新建任务") { creation = .task }
                                    .accessibilityIdentifier("agenda.empty.newTask")
                                Button("新建日程") { creation = .event }
                                    .accessibilityIdentifier("agenda.empty.newEvent")
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    if !agenda.events.isEmpty {
                        Text("日程").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(agenda.events) { event in
                            CalendarEventAgendaRow(event: event, calendar: calendar) { open(.event(event)) }
                        }
                    }
                    if !agenda.tasks.isEmpty {
                        if !agenda.events.isEmpty { Divider() }
                        Text("任务").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(agenda.tasks) { occurrence in
                            CalendarTaskAgendaRow(occurrence: occurrence,
                                                  open: { open(.task(occurrence.task)) },
                                                  toggle: { toggleTask(occurrence.task) })
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 275, idealWidth: 310, maxWidth: 420, maxHeight: .infinity)
        .background(WorkspaceStyle.surface.opacity(0.45))
        .sheet(item: $creation) { kind in
            switch kind {
            case .task: TaskEditorView(plannedDate: agenda.date, calendar: calendar)
            case .event: CalendarEventEditorView(date: agenda.date, calendar: calendar)
            }
        }
    }
}
