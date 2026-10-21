import SwiftUI
import SwiftData

@MainActor private enum ReminderCoordinator {
    static var pending: Task<Void, Never>?
    static var revision = 0
    static func request(_ context: ModelContext) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--selno-ui-testing") || ProcessInfo.processInfo.environment["SELNO_TESTING"] == "1" { return }
        #endif
        revision += 1
        guard pending == nil else { return }
        pending = Task {
            repeat {
                let current = revision
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    try await ReminderService(context: context, gateway: SystemReminderGateway()).reconcile()
                } catch { }
                if current == revision { break }
            } while !Task.isCancelled
            pending = nil
        }
    }
}

struct ReminderReconciliation: ViewModifier {
    @Environment(\.modelContext) private var context
    func body(content: Content) -> some View {
        content.onAppear { ReminderCoordinator.request(context) }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { note in
                if let saved = note.object as? ModelContext, saved !== context { return }
                ReminderCoordinator.request(context)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in ReminderCoordinator.request(context) }
            .onReceive(NotificationCenter.default.publisher(for: .selnoReminderNeedsReconcile)) { _ in ReminderCoordinator.request(context) }
    }
}
