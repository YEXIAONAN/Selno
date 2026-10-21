import Foundation
import SwiftData
import UserNotifications

struct MilestoneReminder: Equatable {
    let id: String
    let title: String
    let body: String
    let firesAt: Date
    var signature: String { "\(firesAt.timeIntervalSince1970)|\(title)|\(body)" }
}

@MainActor protocol ReminderGateway {
    func authorized() async -> Bool
    func pending() async -> [String: String]
    func remove(_ identifiers: [String])
    func add(_ reminder: MilestoneReminder) async throws
}

enum ReminderError: LocalizedError {
    case notAuthorized
    var errorDescription: String? { "没有获得通知权限。你可以将节点设为“不提醒”后保存，或在系统设置中允许 Selno 通知。" }
}

@MainActor struct SystemReminderGateway: ReminderGateway {
    private let center = UNUserNotificationCenter.current()
    private static let delegate = ForegroundNotificationDelegate()
    init() { center.delegate = Self.delegate }
    func authorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    func requestPermission() async -> Bool {
        if await authorized() { return true }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }
    func pending() async -> [String: String] {
        var result: [String: String] = [:]
        for item in await center.pendingNotificationRequests() where item.identifier.hasPrefix("selno.node.") {
            result[item.identifier] = item.content.userInfo["selno.signature"] as? String ?? ""
        }
        return result
    }
    func remove(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    func add(_ reminder: MilestoneReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title; content.body = reminder.body; content.sound = .default
        content.userInfo = ["selno.signature": reminder.signature]
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.firesAt)
        components.timeZone = Calendar.current.timeZone
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                             withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor struct ReminderService {
    let context: ModelContext
    let gateway: any ReminderGateway
    func reconcile(now: Date = .now) async throws {
        let nodes = try context.fetch(FetchDescriptor<TaskMilestone>())
        let allowed = await gateway.authorized()
        var desired: [String: MilestoneReminder] = [:]
        var states: [UUID: String] = [:]
        for node in nodes {
            guard let lead = node.reminderLeadMinutes else { states[node.id] = "none"; continue }
            let fire = node.date.addingTimeInterval(-Double(lead) * 60)
            guard node.task?.status.isActive == true else { states[node.id] = "paused"; continue }
            guard fire > now else { states[node.id] = "expired"; continue }
            guard allowed else { states[node.id] = "blocked"; continue }
            desired[node.notificationID] = MilestoneReminder(id: node.notificationID, title: node.task?.title ?? "序宁",
                                                            body: "\(node.title) · \(CalendarMath.time(node.date, calendar: .current))", firesAt: fire)
            states[node.id] = "scheduled"
        }
        let pending = await gateway.pending()
        gateway.remove(pending.keys.filter { desired[$0] == nil })
        for (id, item) in desired where pending[id] != item.signature {
            do { try await gateway.add(item) }
            catch {
                gateway.remove([id])
                if let node = nodes.first(where: { $0.notificationID == id }) { states[node.id] = "failed" }
            }
        }
        var changed = false
        for node in nodes where node.reminderStateRaw != states[node.id] {
            node.reminderStateRaw = states[node.id] ?? "none"; changed = true
        }
        if changed { do { try context.save() } catch { context.rollback(); throw error } }
    }
}
