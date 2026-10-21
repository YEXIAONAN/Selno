import Foundation

enum TaskStatusFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case inProgress
    case completed
    case cancelled
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部状态"
        case .pending: "待开始"
        case .inProgress: "进行中"
        case .completed: "已完成"
        case .cancelled: "已取消"
        case .archived: "已归档"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .pending: "circle"
        case .inProgress: "circle.dotted"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .archived: "archivebox"
        }
    }

    func matches(_ task: TodoTask) -> Bool {
        switch self {
        case .all: !task.isArchived
        case .pending: !task.isArchived && task.status == .pending
        case .inProgress: !task.isArchived && task.status == .inProgress
        case .completed: !task.isArchived && task.status == .completed
        case .cancelled: !task.isArchived && task.status == .cancelled
        case .archived: task.isArchived
        }
    }
}

enum TaskProjectFilter: Hashable {
    case all
    case unassigned
    case project(UUID)

    var title: String {
        switch self {
        case .all: "全部项目"
        case .unassigned: "未归属项目"
        case .project: "指定项目"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "folder"
        case .unassigned: "tray"
        case .project: "folder.fill"
        }
    }
}

enum TaskSortMode: String, CaseIterable, Identifiable {
    case standard
    case dueDate
    case importance
    case updated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "默认排序"
        case .dueDate: "截止日期"
        case .importance: "重要性"
        case .updated: "最近更新"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "arrow.up.arrow.down"
        case .dueDate: "calendar"
        case .importance: "exclamationmark.circle"
        case .updated: "clock"
        }
    }

    func sort(_ tasks: [TodoTask]) -> [TodoTask] {
        switch self {
        case .standard:
            return tasks
        case .dueDate:
            return tasks.sorted {
                if $0.status.isActive != $1.status.isActive { return $0.status.isActive }
                return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
            }
        case .importance:
            return tasks.sorted {
                if $0.status.isActive != $1.status.isActive { return $0.status.isActive }
                if $0.importance.sortPriority != $1.importance.sortPriority {
                    return $0.importance.sortPriority > $1.importance.sortPriority
                }
                return $0.createdAt > $1.createdAt
            }
        case .updated:
            return tasks.sorted {
                if $0.status.isActive != $1.status.isActive { return $0.status.isActive }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }
}

enum TaskQueryFilter {
    /// Search is intentionally global: the caller decides which task universe to
    /// pass. All filters except archived exclude archived tasks.
    static func apply(
        _ tasks: [TodoTask],
        search: String,
        status: TaskStatusFilter,
        project: TaskProjectFilter,
        tagID: UUID?
    ) -> [TodoTask] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            guard status.matches(task) else { return false }

            switch project {
            case .all:
                break
            case .unassigned:
                guard task.project == nil else { return false }
            case .project(let id):
                guard task.project?.id == id else { return false }
            }

            if let tagID {
                let tagIDs = Set((task.tags ?? []).map(\.id) + (task.category.map { [$0.id] } ?? []))
                guard tagIDs.contains(tagID) else { return false }
            }

            guard !needle.isEmpty else { return true }
            return matches(task, needle: needle)
        }
    }

    static func matches(_ task: TodoTask, needle: String) -> Bool {
        var fields = [task.title, task.notes, task.project?.name ?? ""]
        fields.append(contentsOf: (task.tags ?? []).flatMap { [$0.name, $0.emoji] })
        if let category = task.category {
            fields.append(contentsOf: [category.name, category.emoji])
        }
        return fields.contains { $0.localizedStandardContains(needle) }
    }
}