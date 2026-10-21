import SwiftUI

struct MainWindowView: View {
    @Environment(\.calendar) private var systemCalendar
    @Environment(\.timeZone) private var timeZone
    @State private var section: AppSection? = .overview
    @State private var calendarDate = Date.now
    @State private var calendarRequest = UUID()
    @State private var projectID: UUID?
    @State private var projectRequest = UUID()
    @State private var brand = BrandTypingState()

    private var calendar: Calendar {
        var calendar = systemCalendar
        calendar.timeZone = timeZone
        return calendar
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selno").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.5)
                    Text("序宁 · 让事务有序").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.top, 18)
                List(AppSection.allCases, selection: $section) { item in
                    NavigationLink(value: item) {
                        Label(item.title, systemImage: item.symbolName).padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("sidebar.\(item.rawValue)")
                }
                SettingsLink { Label("设置", systemImage: "gearshape") }.buttonStyle(.plain)
                    .font(.subheadline).foregroundStyle(SelnoDesign.secondary).padding(.horizontal, 18).padding(.bottom, 16)
                    .accessibilityIdentifier("settings.open")
            }
            .navigationTitle("Selno")
            .background(SelnoDesign.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            switch section ?? .overview {
            case .overview, .today:
                DashboardWorkspace(calendar: calendar, brand: brand, isToday: section == .today,
                                   openCalendar: openCalendar, navigate: { section = $0 }, openProject: openProject)
                    .id(section)
            case .calendar:
                CalendarWorkspace(calendar: calendar, initialDate: calendarDate).id(calendarRequest)
            case .projects:
                ProjectWorkspace(calendar: calendar, initialProjectID: projectID).id(projectRequest)
            case .inbox, .all:
                TaskWorkspaceView(scope: (section ?? .inbox).taskScope, calendar: calendar).id(section)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .tint(SelnoDesign.accent)
        .modifier(ReminderReconciliation())
    }

    private func openCalendar(_ date: Date) {
        calendarDate = calendar.startOfDay(for: date)
        calendarRequest = UUID()
        section = .calendar
    }
    private func openProject(_ id: UUID) {
        projectID = id
        projectRequest = UUID()
        section = .projects
    }
}
