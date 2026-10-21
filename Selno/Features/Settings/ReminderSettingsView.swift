import AppKit
import SwiftUI
import UserNotifications

struct ReminderSettingsView: View {
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var quietEnabled = QuietHours.current.isEnabled
    @State private var quietStart = ClockTime.date(minutes: QuietHours.current.startMinute)
    @State private var quietEnd = ClockTime.date(minutes: QuietHours.current.endMinute)
    @State private var reconcileNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("提醒").font(.title2.weight(.semibold))
                    Text("任务提醒使用 macOS 通知中心。Selno 不需要常驻后台，也不会用轮询模拟提醒。")
                        .font(.callout).foregroundStyle(SelnoDesign.secondary)
                }

                WorkspaceCard(emphasis: true) {
                    ModuleHeading(title: "通知权限", symbol: "bell",
                                  detail: permissionDetail)
                    permissionRow
                    Text("通知权限由 macOS 管理。若曾拒绝，需要先在系统设置中允许 Selno 通知，应用内无法再次弹出授权请求。")
                        .font(.caption).foregroundStyle(SelnoDesign.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WorkspaceCard(emphasis: true) {
                    ModuleHeading(title: "安静时段", symbol: "moon.zzz",
                                  detail: quietEnabled ? "\(ClockTime.text(minute: minute(of: quietStart))) – \(ClockTime.text(minute: minute(of: quietEnd)))" : "未启用")
                    Toggle("在安静时段内不投递提醒", isOn: $quietEnabled)
                        .accessibilityIdentifier("reminder.settings.quietEnabled")
                    HStack(spacing: 18) {
                        DatePicker("开始", selection: $quietStart, displayedComponents: .hourAndMinute)
                        DatePicker("结束", selection: $quietEnd, displayedComponents: .hourAndMinute)
                    }
                    .disabled(!quietEnabled)
                    Text("安静时段内到点的提醒会顺延到结束时间，只投递一次。跨午夜（例如 22:00 – 08:00）也可以直接设置。")
                        .font(.caption).foregroundStyle(SelnoDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WorkspaceCard {
                    ModuleHeading(title: "实际行为", symbol: "info.circle")
                    VStack(alignment: .leading, spacing: 9) {
                        Label("任务提醒在保存任务时按截止时间或指定时间排定；修改日期、完成、归档或删除任务后会自动重新核对。", systemImage: "arrow.triangle.2.circlepath")
                        Label("Selno 未运行或 Mac 处于休眠时，已经排定的通知仍由系统尝试投递；但应用内的重新核对要等到下次打开或切回 Selno。", systemImage: "app.badge.clock")
                        Label("错过提醒时间后不会补发，也不会为同一条提醒重复注册通知。", systemImage: "clock.badge.xmark")
                        Label("模板里程碑提醒与任务提醒共用同一套通知标识和核对逻辑。", systemImage: "square.stack.3d.up")
                    }
                    .font(.caption).foregroundStyle(SelnoDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("立即重新核对") { requestReconcile() }
                            .buttonStyle(SelnoButtonStyle())
                            .accessibilityIdentifier("reminder.settings.reconcile")
                        if let reconcileNotice {
                            Text(reconcileNotice).font(.caption).foregroundStyle(SelnoDesign.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SelnoDesign.canvas)
        .onAppear { refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermission()
        }
        .onChange(of: quietEnabled) { _, _ in saveQuietHours() }
        .onChange(of: quietStart) { _, _ in saveQuietHours() }
        .onChange(of: quietEnd) { _, _ in saveQuietHours() }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch permission {
        case .authorized, .provisional:
            Label("通知已允许，提醒可以送达。", systemImage: "checkmark.circle")
                .font(.callout).foregroundStyle(SelnoDesign.success)
        case .denied:
            HStack {
                Label("通知已关闭，提醒不会送达。", systemImage: "bell.slash")
                    .font(.callout).foregroundStyle(SelnoDesign.warning)
                Spacer()
                Button("打开系统设置") { ReminderPermission.openSystemSettings() }
                    .buttonStyle(.link)
            }
        case .notDetermined:
            HStack {
                Label("尚未请求通知权限。", systemImage: "bell")
                    .font(.callout).foregroundStyle(SelnoDesign.secondary)
                Spacer()
                Button("请求权限") { requestPermission() }
                    .buttonStyle(SelnoButtonStyle(primary: true))
                    .accessibilityIdentifier("reminder.settings.request")
            }
        default:
            Label("通知权限状态未知，请检查系统设置。", systemImage: "questionmark.circle")
                .font(.callout).foregroundStyle(SelnoDesign.secondary)
        }
    }

    private var permissionDetail: String {
        switch permission {
        case .authorized, .provisional: "已允许"
        case .denied: "已关闭"
        case .notDetermined: "尚未请求"
        default: "未知"
        }
    }

    private func refreshPermission() {
        Task { permission = await ReminderPermission.status() }
    }

    private func requestPermission() {
        Task {
            let granted = await ReminderPermission.request()
            permission = await ReminderPermission.status()
            if granted { NotificationCenter.default.post(name: .selnoReminderNeedsReconcile, object: nil) }
        }
    }

    private func saveQuietHours() {
        let defaults = UserDefaults.standard
        defaults.set(quietEnabled, forKey: QuietHoursKeys.enabled)
        defaults.set(minute(of: quietStart), forKey: QuietHoursKeys.start)
        defaults.set(minute(of: quietEnd), forKey: QuietHoursKeys.end)
        requestReconcile()
    }

    private func requestReconcile() {
        NotificationCenter.default.post(name: .selnoReminderNeedsReconcile, object: nil)
        reconcileNotice = "已请求重新核对"
        Task {
            try? await Task.sleep(for: .seconds(2))
            if reconcileNotice != nil { reconcileNotice = nil }
        }
    }

    private func minute(of date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return min(max((components.hour ?? 0) * 60 + (components.minute ?? 0), 0), 1_439)
    }
}

private enum ClockTime {
    static func date(minutes: Int) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .minute, value: min(max(minutes, 0), 1_439), to: start) ?? start
    }

    static func text(minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}