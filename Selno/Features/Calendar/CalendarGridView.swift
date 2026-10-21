import SwiftUI

private struct CalendarDayAnchors: PreferenceKey {
    static var defaultValue: [Date: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Date: Anchor<CGRect>], nextValue: () -> [Date: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct CalendarGridView: View {
    let window: CalendarWindow
    let displayDate: Date
    let selectedDate: Date
    let mode: CalendarViewMode
    let calendar: Calendar
    let snapshot: CalendarAgendaSnapshot
    let now: Date
    let dayHeight: CGFloat
    let selectDate: (Date) -> Void
    let open: (AgendaSelection) -> Void
    let reschedule: (UUID, Date) -> Bool
    @State private var hoverCandidate: Date?
    @State private var hoverVisible = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    let index = (calendar.firstWeekday - 1 + offset) % 7
                    Text(calendar.shortStandaloneWeekdaySymbols[index])
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(window.days, id: \.self) { day in
                    CalendarDayCell(
                        agenda: snapshot.agenda(on: day, calendar: calendar),
                        calendar: calendar,
                        isInMonth: calendar.isDate(day, equalTo: displayDate, toGranularity: .month),
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        isToday: calendar.isDate(day, inSameDayAs: now),
                        isWeek: mode == .week,
                        dayHeight: dayHeight,
                        select: { selectDate(day) }, open: open,
                        reschedule: { id in
                            hoverCandidate = nil
                            hoverVisible = false
                            return reschedule(id, day)
                        }
                    )
                    .anchorPreference(key: CalendarDayAnchors.self, value: .bounds) { [day: $0] }
                    .onHover { hovering in
                        if hovering { hoverCandidate = day }
                        else if hoverCandidate == day { hoverCandidate = nil; hoverVisible = false }
                    }
                }
            }
        }
        .overlayPreferenceValue(CalendarDayAnchors.self) { anchors in
            GeometryReader { proxy in
                if hoverVisible, let day = hoverCandidate, let anchor = anchors[day] {
                    let rect = proxy[anchor]
                    let x = min(max(rect.midX, 150), max(150, proxy.size.width - 150))
                    let agenda = snapshot.agenda(on: day, calendar: calendar)
                    let height = CalendarHoverTip.height(for: agenda)
                    let y = rect.maxY + height + 8 < proxy.size.height ? rect.maxY + height / 2 + 6
                        : max(height / 2 + 4, rect.minY - height / 2 - 6)
                    CalendarHoverTip(agenda: agenda, calendar: calendar)
                        .position(x: x, y: y)
                }
            }
            .allowsHitTesting(false)
        }
        .task(id: hoverCandidate) {
            hoverVisible = false
            guard hoverCandidate != nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                hoverVisible = true
            } catch { }
        }
    }
}

private struct CalendarDayCell: View {
    let agenda: DayAgenda
    let calendar: Calendar
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let isWeek: Bool
    let dayHeight: CGFloat
    let select: () -> Void
    let open: (AgendaSelection) -> Void
    let reschedule: (UUID) -> Bool
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: select) {
                HStack {
                    Text("\(calendar.component(.day, from: agenda.date))")
                        .font(.system(.body, design: .rounded).weight(isToday ? .bold : .regular))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(isToday ? SelnoDesign.canvas : SelnoDesign.primary)
                        .background(isToday ? SelnoDesign.accent : .clear, in: Circle())
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CalendarMath.fullDate(agenda.date, calendar: calendar))
            .accessibilityValue("\(agenda.pendingCount) 项待办，\(agenda.events.count) 项日程")
            .accessibilityIdentifier("calendar.day.\(CalendarMath.dayID(agenda.date, calendar: calendar))")

            if !agenda.isEmpty {
                Text("\(agenda.pendingCount) 待办 · \(agenda.events.count) 日程")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            let limit = isWeek ? 6 : 2
            let eventCount = min(limit, agenda.events.count)
            ForEach(Array(agenda.events.prefix(eventCount))) { event in
                Button { select(); open(.event(event)) } label: {
                    Label(isWeek ? "\(CalendarAgendaBuilder.eventTime(event, calendar: calendar)) \(event.title)" : event.title, systemImage: "calendar")
                        .font(.system(size: 10)).lineLimit(isWeek ? 2 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            let taskCount = max(0, limit - eventCount)
            ForEach(Array(agenda.tasks.prefix(taskCount))) { occurrence in
                CalendarTaskDragButton(occurrence: occurrence, showsRole: isWeek) {
                    select(); open(.task(occurrence.task))
                }
                .frame(height: 16)
            }
            let remaining = agenda.tasks.count + agenda.events.count - eventCount - min(taskCount, agenda.tasks.count)
            if remaining > 0 { Text("另有 \(remaining) 项").font(.system(size: 9)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: select)
                .accessibilityHidden(true)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: dayHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(WorkspaceStyle.surface.opacity(isSelected || isDropTargeted ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected || isDropTargeted ? SelnoDesign.accent.opacity(0.85) : WorkspaceStyle.line, lineWidth: isSelected || isDropTargeted ? 1.5 : 0.5))
        .opacity(isInMonth || isWeek ? 1 : 0.45)
        .contentShape(Rectangle())
        .onDrop(of: [CalendarTaskDrag.contentType], isTargeted: $isDropTargeted) { providers in
            CalendarTaskDrag.receive(providers) { _ = reschedule($0) }
        }
    }
}
