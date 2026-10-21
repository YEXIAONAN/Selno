import Foundation

nonisolated enum TaskStatus: String, CaseIterable, Identifiable {
    case pending
    case inProgress
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: "待开始"
        case .inProgress: "进行中"
        case .completed: "已完成"
        case .cancelled: "已取消"
        }
    }

    var isActive: Bool { self == .pending || self == .inProgress }
}

nonisolated enum TaskImportance: String, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "低"
        case .normal: "普通"
        case .high: "重要"
        }
    }

    var sortPriority: Int {
        switch self {
        case .low: 0
        case .normal: 1
        case .high: 2
        }
    }
}

nonisolated enum TaskUrgency {
    case unscheduled
    case upcoming
    case dueToday
    case overdue
}
