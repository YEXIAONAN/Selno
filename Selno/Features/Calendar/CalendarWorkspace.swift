import SwiftUI

struct CalendarWorkspace: View {
    let calendar: Calendar
    @State private var displayDate: Date
    @State private var selectedDate: Date
    @State private var mode: CalendarViewMode = .month
    @State private var listRange: CalendarListRange = .month
    @State private var window: CalendarWindow
    @State private var isPanelOpen = true

    init(calendar: Calendar, initialDate: Date = .now) {
        self.calendar = calendar
        let today = calendar.startOfDay(for: initialDate)
        _displayDate = State(initialValue: today)
        _selectedDate = State(initialValue: today)
        _window = State(initialValue: CalendarMath.window(containing: today, mode: .month, listRange: .month, calendar: calendar))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("日历").font(.caption).foregroundStyle(.secondary)
                        Text(CalendarMath.monthTitle(displayDate, calendar: calendar))
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .accessibilityIdentifier("calendar.heading")
                    }
                    Spacer(minLength: 8)
                    Picker("日历视图", selection: $mode) {
                        ForEach(CalendarViewMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .accessibilityIdentifier("calendar.mode")
                    Button { isPanelOpen.toggle() } label: { Image(systemName: "sidebar.right") }
                        .help("展开或收起当日安排")
                        .accessibilityLabel("切换当日安排面板")
                        .accessibilityIdentifier("calendar.toggleAgenda")
                }
                HStack(spacing: 10) {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("上一个日期范围").accessibilityIdentifier("calendar.previous")
                    Button("今天") { go(to: .now) }.accessibilityIdentifier("calendar.today")
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("下一个日期范围").accessibilityIdentifier("calendar.next")
                    Menu("年份") {
                        Button("上一年") { moveYear(-1) }
                        Button("下一年") { moveYear(1) }
                    }
                    .fixedSize()
                    .accessibilityIdentifier("calendar.year")
                    DatePicker("定位日期", selection: Binding(get: { displayDate }, set: go), displayedComponents: .date)
                        .labelsHidden().fixedSize()
                        .accessibilityIdentifier("calendar.jumpDate")
                    Spacer(minLength: 0)
                    if mode == .list {
                        Picker("范围", selection: $listRange) {
                            ForEach(CalendarListRange.allCases) { Text($0.title).tag($0) }
                        }
                        .fixedSize().accessibilityIdentifier("calendar.listRange")
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
            Rectangle().fill(WorkspaceStyle.line).frame(height: 1)
            CalendarRangeContent(window: window, displayDate: displayDate, mode: mode, calendar: calendar,
                                 selectedDate: $selectedDate, isPanelOpen: $isPanelOpen)
                .id(window)
        }
        .navigationTitle("日历")
        .background(WorkspaceStyle.canvas)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .onChange(of: mode) { _, _ in displayDate = selectedDate; rebuildWindow() }
        .onChange(of: listRange) { _, _ in displayDate = selectedDate; rebuildWindow() }
        .onChange(of: calendar) { _, _ in go(to: selectedDate) }
    }

    private func go(to date: Date) {
        displayDate = calendar.startOfDay(for: date)
        selectedDate = displayDate
        rebuildWindow()
    }

    private func move(_ direction: Int) {
        go(to: CalendarMath.moved(displayDate, by: direction, mode: mode, listRange: listRange, calendar: calendar))
    }

    private func moveYear(_ direction: Int) {
        go(to: calendar.date(byAdding: .year, value: direction, to: displayDate) ?? displayDate)
    }

    private func rebuildWindow() {
        window = CalendarMath.window(containing: displayDate, mode: mode, listRange: listRange, calendar: calendar)
    }
}
