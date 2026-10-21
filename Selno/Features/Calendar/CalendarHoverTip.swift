import SwiftUI

struct CalendarHoverTip: View {
    let agenda: DayAgenda
    let calendar: Calendar

    static func height(for agenda: DayAgenda) -> CGFloat {
        let count = agenda.tasks.count + agenda.events.count
        return max(100, CGFloat(74 + min(4, count) * 22 + (count > 4 ? 18 : 0)))
    }

    private var spokenSummary: String {
        let events = agenda.events.prefix(4).map { "\(CalendarAgendaBuilder.eventTime($0, calendar: calendar)) \($0.title)" }
        let tasks = agenda.tasks.prefix(max(0, 4 - events.count)).map { "\($0.roleTitle) · \($0.task.title)" }
        let items = events + tasks
        let remaining = agenda.events.count + agenda.tasks.count - items.count
        let details = agenda.isEmpty ? "暂无安排" : items.joined(separator: "；")
        return "\(CalendarMath.fullDate(agenda.date, calendar: calendar))，\(agenda.pendingCount) 项待办，\(agenda.events.count) 项日程。\(details)\(remaining > 0 ? "；另有 \(remaining) 项安排" : "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CalendarMath.fullDate(agenda.date, calendar: calendar)).font(.headline)
            Text("\(agenda.pendingCount) 项待办 · \(agenda.events.count) 项日程")
                .font(.caption).foregroundStyle(.secondary)
            if agenda.isEmpty {
                Text("暂无安排").foregroundStyle(.secondary)
            } else {
                let eventLimit = min(agenda.events.count, 4)
                ForEach(Array(agenda.events.prefix(eventLimit))) { event in
                    Label("\(CalendarAgendaBuilder.eventTime(event, calendar: calendar))  \(event.title)", systemImage: "calendar")
                        .lineLimit(1)
                }
                let taskLimit = max(0, 4 - eventLimit)
                ForEach(Array(agenda.tasks.prefix(taskLimit))) { occurrence in
                    Label("\(occurrence.shortRoleTitle) · \(occurrence.task.title)", systemImage: occurrence.task.status == .completed ? "checkmark.circle.fill" : "checklist")
                        .lineLimit(1)
                }
                let remaining = agenda.events.count + agenda.tasks.count - eventLimit - min(agenda.tasks.count, taskLimit)
                if remaining > 0 { Text("另有 \(remaining) 项安排").foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(12)
        .frame(width: 290, height: Self.height(for: agenda), alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.7)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityIdentifier("calendar.hover")
        .allowsHitTesting(false)
    }
}
