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
            let container = try PersistenceController.makeContainer(storage: launchStorage())
            try DefaultDataSeeder.seedIfNeeded(in: container.mainContext)
            try TemplatePresets.seed(in: container.mainContext)
            self.container = container
            failureMessage = nil
        } catch {
            container = nil
            let details = String(describing: error as NSError)
            failureMessage = "无法打开或初始化本地数据库。现有数据库会保留，请检查磁盘空间和访问权限后重试。\n\n\(error.localizedDescription)\n\n\(details)"
        }
    }

    private func launchStorage() throws -> PersistenceController.Storage {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--selno-ui-testing") {
            guard let value = process.environment["SELNO_UI_TEST_STORE_ID"],
                  let id = UUID(uuidString: value) else {
                throw PersistenceError.invalidUITestStore
            }
            let root = try PersistenceController.localStoreURL().deletingLastPathComponent()
            return .disk(root.appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("Selno.store"))
        }
        if process.environment["SELNO_TESTING"] == "1"
            || process.environment["XCTestConfigurationFilePath"] != nil {
            return .inMemory
        }
        #endif
        return .local
    }
}
