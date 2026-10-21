import Foundation
import SwiftData

enum TaskReminderKind: String, CaseIterable, Identifiable {
    case due
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .due: "截止前提醒"
        case .scheduled: "指定时间提醒"
        }
    }
}

enum TaskReminderState: String {
    case pending
    case scheduled
    case blocked
    case expired
    case paused
    case failed
    case unconfigured
    case duplicate

    var title: String {
        switch self {
        case .pending: "待安排"
        case .scheduled: "已安排"
        case .blocked: "通知权限未开放"
        case .expired: "提醒时间已过"
        case .paused: "任务已结束，提醒已停用"
        case .failed: "安排失败，稍后重试"
        case .unconfigured: "缺少提醒凭据"
        case .duplicate: "重复配置，仅保留最新一条"
        }
    }
}

/// A per-task notification preference. It is stored separately from `TodoTask` so the
/// reminder can keep a stable notification identifier while the task is edited.
@Model
final class TaskReminder {
    var id: UUID = UUID()
    var taskID: UUID?
    var kindRaw: String = TaskReminderKind.due.rawValue
    var leadMinutes: Int = 0
    var scheduledAt: Date?
    /// Set when the user chooses "稍后提醒" from a delivered notification. The value is
    /// transient scheduling state and deliberately excluded from JSON backups.
    var snoozeUntil: Date?
    var stateRaw: String = TaskReminderState.pending.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        taskID: UUID?,
        kind: TaskReminderKind,
        leadMinutes: Int = 0,
        scheduledAt: Date? = nil,
        now: Date = .now
    ) {
        self.id = id
        self.taskID = taskID
        self.kindRaw = kind.rawValue
        self.leadMinutes = leadMinutes
        self.scheduledAt = scheduledAt
        self.createdAt = now
        self.updatedAt = now
    }

    var kind: TaskReminderKind { TaskReminderKind(rawValue: kindRaw) ?? .due }
    var state: TaskReminderState { TaskReminderState(rawValue: stateRaw) ?? .pending }
    var notificationID: String { "selno.task.\(id.uuidString)" }

    /// The unshifted fire time. Quiet hours and snoozing are applied by `ReminderService`.
    func baseFireDate(for task: TodoTask) -> Date? {
        switch kind {
        case .due:
            guard let dueAt = task.dueAt else { return nil }
            return dueAt.addingTimeInterval(-Double(max(0, leadMinutes)) * 60)
        case .scheduled:
            return scheduledAt
        }
    }

    var leadDescription: String {
        switch kind {
        case .due:
            if leadMinutes == 0 { return "截止时" }
            if leadMinutes % 10_080 == 0 { return "提前 \(leadMinutes / 10_080) 周" }
            if leadMinutes % 1_440 == 0 { return "提前 \(leadMinutes / 1_440) 天" }
            if leadMinutes % 60 == 0 { return "提前 \(leadMinutes / 60) 小时" }
            return "提前 \(leadMinutes) 分钟"
        case .scheduled:
            return scheduledAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "未设置时间"
        }
    }
}