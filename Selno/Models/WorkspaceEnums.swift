import Foundation
import SwiftUI

// MARK: - Sizes

nonisolated enum ModuleSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var symbolName: String {
        switch self {
        case .small: "square"
        case .medium: "rectangle"
        case .large: "rectangle.expand.vertical"
        }
    }

    var rank: Int {
        switch self {
        case .small: 1
        case .medium: 2
        case .large: 3
        }
    }

    /// Number of columns this size prefers. The layout engine clamps the span to
    /// the current column count, so a large module becomes full width on narrow
    /// windows instead of overflowing.
    func preferredSpan(columns: Int) -> Int {
        let columns = max(1, columns)
        switch columns {
        case 1:
            return 1
        case 2:
            return self == .large ? 2 : 1
        default:
            // Three medium modules line up in one row; a large module becomes a
            // full-width band. This keeps the default overview balanced without
            // leaving a permanently empty third column.
            return self == .large ? 3 : 1
        }
    }
}

// MARK: - Scope

nonisolated enum ModuleDataScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case inherit
    case global
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: "继承场景"
        case .global: "全局数据"
        case .custom: "自定义筛选"
        }
    }

    var detail: String {
        switch self {
        case .inherit: "使用场景的默认筛选规则。"
        case .global: "不应用场景筛选，读取全部本地业务数据。"
        case .custom: "完全使用模块自己的筛选规则，替代而不是叠加场景规则。"
        }
    }
}

nonisolated enum FilterSource: String, Sendable {
    case scenario
    case global
    case custom

    var title: String {
        switch self {
        case .scenario: "场景筛选"
        case .global: "全局"
        case .custom: "自定义"
        }
    }

    var symbolName: String {
        switch self {
        case .scenario: "square.stack.3d.up"
        case .global: "globe"
        case .custom: "line.3.horizontal.decrease.circle"
        }
    }
}

nonisolated struct ResolvedTaskFilter: Equatable, Sendable {
    var filter: TaskFilterExpression
    var source: FilterSource
}

// MARK: - Module kinds

nonisolated enum WorkspaceModuleKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case focus
    case upcoming
    case month
    case inbox
    case projects
    case taskList
    case stats
    case quickActions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "今日聚焦"
        case .upcoming: "近期安排"
        case .month: "月历"
        case .inbox: "收件箱"
        case .projects: "项目进度"
        case .taskList: "任务列表"
        case .stats: "任务统计"
        case .quickActions: "快捷操作"
        }
    }

    var symbolName: String {
        switch self {
        case .focus: "scope"
        case .upcoming: "calendar.badge.clock"
        case .month: "calendar"
        case .inbox: "tray"
        case .projects: "folder"
        case .taskList: "list.bullet.rectangle"
        case .stats: "chart.bar"
        case .quickActions: "bolt"
        }
    }

    var isDataDriven: Bool {
        self != .quickActions
    }
}

nonisolated enum ModuleCatalogCategory: String, CaseIterable, Identifiable, Sendable {
    case focus
    case tasks
    case calendar
    case actions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "聚焦"
        case .tasks: "任务与项目"
        case .calendar: "日历"
        case .actions: "快捷操作"
        }
    }
}

// MARK: - Accent

nonisolated enum WorkspaceAccent: String, CaseIterable, Identifiable, Codable, Sendable {
    case sage
    case ocean
    case amber
    case plum
    case rose
    case slate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sage: "鼠尾草"
        case .ocean: "海蓝"
        case .amber: "琥珀"
        case .plum: "雾紫"
        case .rose: "蔷薇"
        case .slate: "岩灰"
        }
    }

    private var lightValue: UInt32 {
        switch self {
        case .sage: 0x4F7A69
        case .ocean: 0x4F7085
        case .amber: 0x9A7438
        case .plum: 0x776A8A
        case .rose: 0x98606A
        case .slate: 0x647066
        }
    }

    private var darkValue: UInt32 {
        switch self {
        case .sage: 0xA8C7A1
        case .ocean: 0xA6C3D3
        case .amber: 0xD9BC87
        case .plum: 0xC5B6D6
        case .rose: 0xD8AFB6
        case .slate: 0xB9C4B8
        }
    }

    @MainActor
    var color: Color {
        SelnoDesign.adaptiveColor(lightValue, darkValue)
    }

    @MainActor
    static func color(for rawValue: String) -> Color {
        (WorkspaceAccent(rawValue: rawValue) ?? .sage).color
    }
}

// MARK: - Limits

nonisolated enum WorkspaceLimits {
    static let maximumWorkspaces = 24
    static let maximumModulesPerWorkspace = 48
    static let maximumNameLength = 30
    static let maximumEmojiLength = 8
    static let taskListLimitRange = 1...50
    static let queryLookbackDays = 180
    static let queryLookaheadDays = 365
    static let maximumQuerySpanDays = 550
}