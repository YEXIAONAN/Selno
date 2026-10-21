import SwiftUI

enum AgendaSelection: Identifiable {
    case task(TodoTask)
    case event(CalendarEvent)
    var id: String {
        switch self {
        case .task(let task): "task-\(task.id)"
        case .event(let event): "event-\(event.id)"
        }
    }
}

struct AgendaDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selection: AgendaSelection
    let calendar: Calendar

    var body: some View {
        NavigationStack {
            Group {
                switch selection {
                case .task(let task): TaskDetailView(task: task)
                case .event(let event): CalendarEventDetailView(event: event, calendar: calendar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 540, height: 640)
    }
}

struct CalendarTaskAgendaRow: View {
    let occurrence: CalendarTaskOccurrence
    let open: () -> Void
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: toggle) {
                Image(systemName: occurrence.task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(occurrence.task.status == .cancelled)
            .accessibilityLabel(occurrence.task.status == .completed ? "恢复为未完成" : "标记为完成")
            .accessibilityIdentifier("agenda.complete.\(occurrence.id.uuidString)")
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(occurrence.task.title)
                        .strikethrough(occurrence.task.status == .completed)
                        .foregroundStyle(occurrence.task.status.isActive ? .primary : .secondary)
                    Text(occurrence.roleTitle).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .calendarTaskDraggable(occurrence.id)
        }
        .padding(.vertical, 7)
    }
}

struct CalendarEventAgendaRow: View {
    let event: CalendarEvent
    let calendar: Calendar
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "calendar").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                    Text(CalendarAgendaBuilder.eventTime(event, calendar: calendar))
                        .font(.caption).foregroundStyle(.secondary)
                    if let location = event.location {
                        Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
        .accessibilityIdentifier("agenda.event.\(event.id.uuidString)")
    }
}
