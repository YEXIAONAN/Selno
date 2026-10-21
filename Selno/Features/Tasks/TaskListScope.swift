import Foundation

enum TaskListScope: String, CaseIterable, Identifiable {
    case today
    case inbox
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .inbox: "收件箱"
        case .all: "全部任务"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max"
        case .inbox: "tray"
        case .all: "checklist"
        }
    }

    var emptyDescription: String {
        switch self {
        case .today: "今天计划、今天截止和已逾期的待办会显示在这里。"
        case .inbox: "随手记下想做的事，稍后再安排。"
        case .all: "从下方输入框创建你的第一个任务。"
        }
    }

    func tasks(from tasks: [TodoTask], on date: Date, calendar: Calendar) -> [TodoTask] {
        tasks.filter { task in
            guard !task.isArchived else { return false }
            switch self {
            case .today: return TodayTaskFilter.includes(task, on: date, calendar: calendar)
            case .inbox: return task.isInInbox
            case .all: return true
            }
        }.sorted { lhs, rhs in
            if lhs.status.isActive != rhs.status.isActive { return lhs.status.isActive }
            if self == .today, lhs.dueAt != rhs.dueAt {
                return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
            }
            if lhs.importance != rhs.importance {
                return lhs.importance.sortPriority > rhs.importance.sortPriority
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
