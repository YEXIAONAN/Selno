import Foundation

/// One selection model for the fixed sections and the user's scenario
/// workspaces. `.section(.overview)` always represents the global workspace.
enum SidebarSelection: Hashable {
    case section(AppSection)
    case workspace(UUID)

    var section: AppSection? {
        if case .section(let value) = self { return value }
        return nil
    }

    var workspaceID: UUID? {
        if case .workspace(let value) = self { return value }
        return nil
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case overview, calendar, today, inbox, all, projects
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "总览"
        case .today: "今天"
        case .calendar: "日历"
        case .inbox: "收件箱"
        case .all: "全部任务"
        case .projects: "项目"
        }
    }
    var symbolName: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .today: "sun.max"
        case .calendar: "calendar"
        case .inbox: "tray"
        case .all: "checklist"
        case .projects: "folder"
        }
    }
    var taskScope: TaskListScope {
        switch self {
        case .today: .today
        case .inbox: .inbox
        case .all: .all
        case .overview, .calendar, .projects: .all
        }
    }
}
