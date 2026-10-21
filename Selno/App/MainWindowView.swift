import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(\.calendar) private var systemCalendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SidebarSelection? = .section(.overview)
    @State private var calendarDate = Date.now
    @State private var calendarRequest = UUID()
    @State private var projectID: UUID?
    @State private var projectRequest = UUID()
    @State private var requestedTaskID: UUID?
    @State private var taskRequest = UUID()
    @State private var brand = BrandTypingState()
    @State private var undoCenter = TaskUndoCenter.shared
    @State private var undoError: PresentedError?

    private var calendar: Calendar {
        var calendar = systemCalendar
        calendar.timeZone = timeZone
        return calendar
    }

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebarView(selection: $selection)
        } detail: {
            detail
        }
        .frame(minWidth: 1000, minHeight: 600)
        .tint(SelnoDesign.accent)
        .modifier(ReminderReconciliation())
        .overlay(alignment: .bottomTrailing) {
            if let message = undoCenter.message {
                HStack(spacing: 10) {
                    Image(systemName: "trash").foregroundStyle(SelnoDesign.secondary)
                    Text(message).font(.callout)
                    Button("撤销") { undoDeletion() }
                        .buttonStyle(SelnoButtonStyle(primary: true))
                        .controlSize(.small)
                        .accessibilityIdentifier("task.undo")
                    Button { undoCenter.clear() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .help("关闭")
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(20)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("task.undo.banner")
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.28), value: undoCenter.message)
        .alert(item: $undoError) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("好")))
        }
        .onAppear {
            // A notification response can arrive before SwiftUI subscribes to the
            // in-process notification, especially on a cold launch.
            if let id = NotificationCenterCoordinator.shared.consumePendingTaskID() { openTask(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selnoOpenTask)) { note in
            guard let id = note.userInfo?["taskID"] as? UUID else { return }
            _ = NotificationCenterCoordinator.shared.consumePendingTaskID()
            openTask(id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selnoDataDidChange)) { _ in
            // Imported data may have replaced every row; drop stale navigation state
            // and the pending deletion snapshot from the previous store contents.
            requestedTaskID = nil
            undoCenter.clear()
            // A restore may have replaced the workspace rows wholesale. Return to
            // the global overview rather than leaving a dangling scenario ID.
            selection = .section(.overview)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .section(.overview) {
        case .section(.overview):
            WorkspaceBoardView(
                workspaceID: nil,
                calendar: calendar,
                brand: brand,
                openCalendar: openCalendar,
                navigate: { selection = .section($0) },
                openProject: openProject,
                onWorkspaceDeleted: { selection = .section(.overview) }
            )
            .id(SidebarSelection.section(.overview))
        case .section(.today):
            DashboardWorkspace(calendar: calendar, brand: brand, isToday: true,
                               openCalendar: openCalendar,
                               navigate: { selection = .section($0) },
                               openProject: openProject)
                .id(AppSection.today)
        case .section(.calendar):
            CalendarWorkspace(calendar: calendar, initialDate: calendarDate).id(calendarRequest)
        case .section(.projects):
            ProjectWorkspace(calendar: calendar, initialProjectID: projectID).id(projectRequest)
        case .section(.inbox), .section(.all):
            let section = selection?.section ?? .inbox
            TaskWorkspaceView(scope: section.taskScope, calendar: calendar,
                              requestedTaskID: requestedTaskID, requestToken: taskRequest)
                .id(section)
        case .workspace(let id):
            WorkspaceBoardView(
                workspaceID: id,
                calendar: calendar,
                brand: brand,
                openCalendar: openCalendar,
                navigate: { selection = .section($0) },
                openProject: openProject,
                onWorkspaceDeleted: { selection = .section(.overview) }
            )
            .id(SidebarSelection.workspace(id))
        }
    }

    private func openTask(_ id: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.allSatisfy({ !$0.isVisible }) { openWindow(id: "main") }
        requestedTaskID = id
        taskRequest = UUID()
        selection = .section(.all)
    }

    private func openCalendar(_ date: Date) {
        calendarDate = calendar.startOfDay(for: date)
        calendarRequest = UUID()
        selection = .section(.calendar)
    }
    private func undoDeletion() {
        do { try undoCenter.undo(context: context) }
        catch { undoError = PresentedError("无法撤销删除", error: error) }
    }

    private func openProject(_ id: UUID) {
        projectID = id
        projectRequest = UUID()
        selection = .section(.projects)
    }
}
