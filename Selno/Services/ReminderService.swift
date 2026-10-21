import Foundation
import SwiftData
import UserNotifications
import AppKit

struct MilestoneReminder: Equatable {
    let id: String
    let title: String
    let body: String
    let firesAt: Date
    /// Set for task-level reminders so the notification can open the task and offer
    /// snooze actions. Milestone notifications carry their task as well.
    var taskID: UUID? = nil
    var categoryIdentifier: String = SelnoNotifications.milestoneCategory
    var signature: String { "\(firesAt.timeIntervalSince1970)|\(title)|\(body)" }
}

/// Notification identifiers and payload keys are read from the notification
/// delegate's nonisolated callbacks, so they must not inherit the module's
/// default main-actor isolation.
enum SelnoNotifications {
    nonisolated static let taskCategory = "selno.notification.task"
    nonisolated static let milestoneCategory = "selno.notification.milestone"
    nonisolated static let openAction = "selno.action.open"
    nonisolated static let snooze10Action = "selno.action.snooze.10"
    nonisolated static let snooze60Action = "selno.action.snooze.60"
    nonisolated static let taskIDKey = "selno.taskID"
    nonisolated static let reminderIDKey = "selno.reminderID"
    nonisolated static let signatureKey = "selno.signature"
}

extension Notification.Name {
    static let selnoOpenTask = Notification.Name("SelnoOpenTask")
    static let selnoReminderNeedsReconcile = Notification.Name("SelnoReminderNeedsReconcile")
}

/// User-configurable quiet hours. A reminder that would fire inside the window is
/// moved to the window's end; it is never retried repeatedly after that time passes.
struct QuietHours: Equatable {
    var isEnabled: Bool
    var startMinute: Int
    var endMinute: Int

    static let disabled = QuietHours(isEnabled: false, startMinute: 22 * 60, endMinute: 8 * 60)

    static var current: QuietHours {
        let defaults = UserDefaults.standard
        return QuietHours(
            isEnabled: defaults.bool(forKey: QuietHoursKeys.enabled),
            startMinute: defaults.object(forKey: QuietHoursKeys.start) as? Int ?? 22 * 60,
            endMinute: defaults.object(forKey: QuietHoursKeys.end) as? Int ?? 8 * 60
        )
    }

    func adjusted(_ date: Date, calendar: Calendar = .current) -> Date {
        guard isEnabled, startMinute != endMinute else { return date }
        let day = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .minute, value: min(max(startMinute, 0), 1_439), to: day) ?? day
        var end = calendar.date(byAdding: .minute, value: min(max(endMinute, 0), 1_439), to: day) ?? day
        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86_400)
        }
        if startMinute > endMinute {
            // Crossing midnight: the window spans last night into this morning,
            // or starts tonight and ends tomorrow morning.
            if date >= start { return end }
            let morningEnd = calendar.date(byAdding: .minute, value: min(max(endMinute, 0), 1_439), to: day) ?? day
            if date < morningEnd { return morningEnd }
        } else if date >= start, date < end {
            return end
        }
        return date
    }
}

enum QuietHoursKeys {
    static let enabled = "selno.quietHours.enabled"
    static let start = "selno.quietHours.startMinute"
    static let end = "selno.quietHours.endMinute"
}

@MainActor protocol ReminderGateway {
    func authorized() async -> Bool
    func pending() async -> [String: String]
    func remove(_ identifiers: [String])
    func add(_ reminder: MilestoneReminder) async throws
}

enum ReminderError: LocalizedError {
    case notAuthorized
    case invalidLead

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "没有获得通知权限。你可以在系统设置中允许 Selno 通知，或关闭提醒后再保存。"
        case .invalidLead:
            "提醒提前量需要在 0 到 365 天之间。"
        }
    }
}

@MainActor enum ReminderPermission {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func request() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) { return }
        }
    }
}

@MainActor struct SystemReminderGateway: ReminderGateway {
    private let center = UNUserNotificationCenter.current()

    init() {
        center.delegate = NotificationCenterCoordinator.shared
        NotificationCenterCoordinator.shared.registerCategories()
    }

    func authorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func pending() async -> [String: String] {
        var result: [String: String] = [:]
        for item in await center.pendingNotificationRequests() where item.identifier.hasPrefix("selno.") {
            result[item.identifier] = item.content.userInfo[SelnoNotifications.signatureKey] as? String ?? ""
        }
        return result
    }

    func remove(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func add(_ reminder: MilestoneReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = reminder.categoryIdentifier
        var userInfo: [String: Any] = [SelnoNotifications.signatureKey: reminder.signature]
        if let taskID = reminder.taskID { userInfo[SelnoNotifications.taskIDKey] = taskID.uuidString }
        if reminder.id.hasPrefix("selno.task.") {
            userInfo[SelnoNotifications.reminderIDKey] = String(reminder.id.dropFirst("selno.task.".count))
        }
        content.userInfo = userInfo
        content.threadIdentifier = reminder.taskID?.uuidString ?? "selno"
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.firesAt)
        components.timeZone = Calendar.current.timeZone
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

@MainActor struct ReminderService {
    let context: ModelContext
    let gateway: any ReminderGateway
    var quietHours: QuietHours = .current
    var calendar: Calendar = .current

    func reconcile(now: Date = .now) async throws {
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let nodes = try context.fetch(FetchDescriptor<TaskMilestone>())
        let reminders = try context.fetch(FetchDescriptor<TaskReminder>())
        let allowed = await gateway.authorized()

        var desired: [String: MilestoneReminder] = [:]
        var nodeStates: [UUID: String] = [:]
        var reminderStates: [UUID: String] = [:]

        for node in nodes {
            guard let lead = node.reminderLeadMinutes else {
                nodeStates[node.id] = "none"
                continue
            }
            guard let task = node.task else {
                nodeStates[node.id] = TaskReminderState.unconfigured.rawValue
                continue
            }
            guard task.status.isActive, !task.isArchived else {
                nodeStates[node.id] = TaskReminderState.paused.rawValue
                continue
            }
            let unshifted = node.date.addingTimeInterval(-Double(max(0, lead)) * 60)
            // Quiet hours must never resurrect a reminder whose own time has already
            // passed; only shift reminders that are still in the future.
            guard unshifted > now else {
                nodeStates[node.id] = TaskReminderState.expired.rawValue
                continue
            }
            let fire = quietHours.adjusted(unshifted, calendar: calendar)
            guard fire > now else {
                nodeStates[node.id] = TaskReminderState.expired.rawValue
                continue
            }
            guard allowed else {
                nodeStates[node.id] = TaskReminderState.blocked.rawValue
                continue
            }
            desired[node.notificationID] = MilestoneReminder(
                id: node.notificationID,
                title: task.title,
                body: "\(node.title) · \(CalendarMath.time(node.date, calendar: calendar))",
                firesAt: fire,
                taskID: task.id,
                categoryIdentifier: SelnoNotifications.milestoneCategory
            )
            nodeStates[node.id] = TaskReminderState.scheduled.rawValue
        }

        // Keep one row per task/kind. Older duplicate rows are retained for audit but
        // never registered, so a repeated import cannot create duplicate notifications.
        var preferred: [String: TaskReminder] = [:]
        for reminder in reminders {
            guard let taskID = reminder.taskID else { continue }
            let key = "\(taskID.uuidString)|\(reminder.kindRaw)"
            if let existing = preferred[key] {
                if reminder.updatedAt > existing.updatedAt ||
                    (reminder.updatedAt == existing.updatedAt && reminder.id.uuidString > existing.id.uuidString) {
                    preferred[key] = reminder
                }
            } else {
                preferred[key] = reminder
            }
        }
        let preferredIDs = Set(preferred.values.map(\.id))

        for reminder in reminders {
            guard let taskID = reminder.taskID else {
                reminderStates[reminder.id] = TaskReminderState.unconfigured.rawValue
                continue
            }
            guard preferredIDs.contains(reminder.id) else {
                reminderStates[reminder.id] = TaskReminderState.duplicate.rawValue
                continue
            }
            guard let task = tasksByID[taskID] else {
                reminderStates[reminder.id] = TaskReminderState.unconfigured.rawValue
                continue
            }
            guard task.status.isActive, !task.isArchived else {
                reminderStates[reminder.id] = TaskReminderState.paused.rawValue
                continue
            }
            guard let base = reminder.baseFireDate(for: task) else {
                reminderStates[reminder.id] = TaskReminderState.unconfigured.rawValue
                continue
            }
            // A snooze deliberately overrides the original time. Once it passes, the
            // reminder expires instead of falling back and firing twice.
            let target = reminder.snoozeUntil ?? base
            guard target > now else {
                reminderStates[reminder.id] = TaskReminderState.expired.rawValue
                continue
            }
            let fire = quietHours.adjusted(target, calendar: calendar)
            guard fire > now else {
                reminderStates[reminder.id] = TaskReminderState.expired.rawValue
                continue
            }
            guard allowed else {
                reminderStates[reminder.id] = TaskReminderState.blocked.rawValue
                continue
            }
            let body: String
            switch reminder.kind {
            case .due:
                let due = task.dueAt.map { CalendarMath.time($0, calendar: calendar) } ?? ""
                body = "\(reminder.leadDescription) · 截止 \(due)"
            case .scheduled:
                body = "提醒时间 \(reminder.scheduledAt.map { CalendarMath.time($0, calendar: calendar) } ?? "")"
            }
            desired[reminder.notificationID] = MilestoneReminder(
                id: reminder.notificationID,
                title: task.title,
                body: body,
                firesAt: fire,
                taskID: task.id,
                categoryIdentifier: SelnoNotifications.taskCategory
            )
            reminderStates[reminder.id] = TaskReminderState.scheduled.rawValue
        }

        let pending = await gateway.pending()
        gateway.remove(pending.keys.filter { desired[$0] == nil })
        for (id, item) in desired where pending[id] != item.signature {
            do {
                try await gateway.add(item)
            } catch {
                gateway.remove([id])
                if let node = nodes.first(where: { $0.notificationID == id }) {
                    nodeStates[node.id] = TaskReminderState.failed.rawValue
                }
                if let reminder = reminders.first(where: { $0.notificationID == id }) {
                    reminderStates[reminder.id] = TaskReminderState.failed.rawValue
                }
            }
        }

        var changed = false
        for node in nodes where node.reminderStateRaw != nodeStates[node.id] {
            node.reminderStateRaw = nodeStates[node.id] ?? "none"
            changed = true
        }
        for reminder in reminders where reminder.stateRaw != reminderStates[reminder.id] {
            reminder.stateRaw = reminderStates[reminder.id] ?? TaskReminderState.pending.rawValue
            changed = true
        }
        if changed {
            do { try context.save() }
            catch { context.rollback(); throw error }
        }
    }
}