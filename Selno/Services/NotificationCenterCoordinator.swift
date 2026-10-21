import AppKit
import Foundation
import SwiftData
import UserNotifications

/// Owns the notification-center delegate, categories, deep links and snooze actions.
/// It is configured before the first window appears so a notification cold launch can
/// still route to the right task.
@MainActor
final class NotificationCenterCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterCoordinator()

    private let center = UNUserNotificationCenter.current()
    private var context: ModelContext?
    private var pendingTaskID: UUID?
    private var pendingSnoozes: [(id: UUID, minutes: Int)] = []
    private var categoriesRegistered = false

    func configure(with container: ModelContainer) {
        configure(context: container.mainContext)
    }

    func configure(context: ModelContext) {
        self.context = context
        center.delegate = self
        registerCategories()
        let queued = pendingSnoozes
        pendingSnoozes.removeAll()
        for item in queued { snooze(reminderID: item.id, minutes: item.minutes) }
    }

    func registerCategories() {
        guard !categoriesRegistered else { return }
        categoriesRegistered = true
        let open = UNNotificationAction(identifier: SelnoNotifications.openAction,
                                        title: "查看任务", options: [.foreground])
        let snooze10 = UNNotificationAction(identifier: SelnoNotifications.snooze10Action,
                                            title: "10 分钟后提醒", options: [])
        let snooze60 = UNNotificationAction(identifier: SelnoNotifications.snooze60Action,
                                            title: "1 小时后提醒", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: SelnoNotifications.taskCategory,
                                   actions: [open, snooze10, snooze60], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: SelnoNotifications.milestoneCategory,
                                   actions: [open], intentIdentifiers: [], options: [])
        ])
    }

    /// Consumed by the main window when it appears, covering cold launches where the
    /// delegate response arrives before SwiftUI has subscribed to the notification.
    func consumePendingTaskID() -> UUID? {
        defer { pendingTaskID = nil }
        return pendingTaskID
    }

    func openTask(_ id: UUID) {
        pendingTaskID = id
        NotificationCenter.default.post(name: .selnoOpenTask, object: nil, userInfo: ["taskID": id])
    }

    func snooze(reminderID: UUID, minutes: Int) {
        guard let context else {
            pendingSnoozes.append((reminderID, minutes))
            return
        }
        let id = reminderID
        guard let reminder = try? context.fetch(
            FetchDescriptor<TaskReminder>(predicate: #Predicate { $0.id == id })
        ).first else { return }
        reminder.snoozeUntil = .now.addingTimeInterval(Double(minutes * 60))
        reminder.stateRaw = TaskReminderState.pending.rawValue
        reminder.updatedAt = .now
        do { try context.save() }
        catch { context.rollback() }
        NotificationCenter.default.post(name: .selnoReminderNeedsReconcile, object: nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let taskID = (info[SelnoNotifications.taskIDKey] as? String).flatMap(UUID.init(uuidString:))
        let reminderID = (info[SelnoNotifications.reminderIDKey] as? String).flatMap(UUID.init(uuidString:))

        Task { @MainActor in
            if action == SelnoNotifications.snooze10Action, let reminderID {
                self.snooze(reminderID: reminderID, minutes: 10)
            } else if action == SelnoNotifications.snooze60Action, let reminderID {
                self.snooze(reminderID: reminderID, minutes: 60)
            } else if action == UNNotificationDefaultActionIdentifier || action == SelnoNotifications.openAction {
                if let taskID { self.openTask(taskID) }
            }
            completionHandler()
        }
    }
}