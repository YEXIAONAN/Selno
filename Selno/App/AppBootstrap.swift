import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppBootstrap {
    private(set) var container: ModelContainer?
    private(set) var failureMessage: String?

    init() {
        load()
    }

    func load() {
        do {
            let container = try PersistenceController.makeContainer(storage: PersistenceController.launchStorage())
            try DefaultDataSeeder.seedIfNeeded(in: container.mainContext)
            try TemplatePresets.seed(in: container.mainContext)
            // Idempotent: creates the global workspace on the first Phase 05 launch
            // (or after a V1 backup restore) and never duplicates it afterwards.
            try WorkspaceSeeder.seedIfNeeded(in: container.mainContext)
            // Set the notification delegate during bootstrap, before the first window.
            // A notification that launched the app can then deliver its task deep link
            // even if SwiftUI has not subscribed yet.
            NotificationCenterCoordinator.shared.configure(with: container)
            self.container = container
            failureMessage = nil
        } catch {
            container = nil
            let details = String(describing: error as NSError)
            failureMessage = "无法打开或初始化本地数据库。现有数据库会保留，请检查磁盘空间和访问权限后重试。\n\n\(error.localizedDescription)\n\n\(details)"
        }
    }

    }
