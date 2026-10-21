import SwiftUI

struct CalendarListView: View {
    let window: CalendarWindow
    let selectedDate: Date
    let snapshot: CalendarAgendaSnapshot
    let calendar: Calendar
    let selectDate: (Date) -> Void
    let open: (AgendaSelection) -> Void
    let toggleTask: (TodoTask) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(window.days, id: \.self) { day in
                let agenda = snapshot.agenda(on: day, calendar: calendar)
                VStack(alignment: .leading, spacing: 8) {
                    Button { selectDate(day) } label: {
                        HStack {
                            Text(CalendarMath.fullDate(day, calendar: calendar)).font(.headline)
                            Spacer()
                            Text("\(agenda.pendingCount) 待办 · \(agenda.events.count) 日程")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendar.list.day.\(CalendarMath.dayID(day, calendar: calendar))")
                    if agenda.isEmpty { Text("暂无安排").font(.caption).foregroundStyle(.secondary) }
                    ForEach(agenda.events) { event in
                        CalendarEventAgendaRow(event: event, calendar: calendar) {
                            selectDate(day); open(.event(event))
                        }
                    }
                    ForEach(agenda.tasks) { occurrence in
                        CalendarTaskAgendaRow(occurrence: occurrence,
                                              open: { selectDate(day); open(.task(occurrence.task)) },
                                              toggle: { toggleTask(occurrence.task) })
                    }
                }
                .padding(16)
                .background(calendar.isDate(day, inSameDayAs: selectedDate) ? SelnoDesign.accent.opacity(0.08) : .clear)
                Divider()
            }
        }
    }
}
