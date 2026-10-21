import Foundation
import SwiftData

@MainActor
enum PersistenceController {
    enum Storage {
        case local
        case inMemory
        case disk(URL)
    }

    static func localStoreURL() throws -> URL {
        try applicationSupportDirectory()
        .appendingPathComponent("Selno", isDirectory: true)
        .appendingPathComponent("Selno.store")
    }

    /// Selects an isolated store for UI tests and for any XCTest host.
    ///
    /// This decision deliberately does not depend on `DEBUG`: a Release test
    /// build must never fall through to the user's real Application Support
    /// store. The arguments and environment are injectable so the decision can
    /// be tested without mutating the current process.
    static func launchStorage(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Storage {
        if arguments.contains("--selno-ui-testing") {
            guard let value = environment["SELNO_UI_TEST_STORE_ID"],
                  let id = UUID(uuidString: value) else {
                throw PersistenceError.invalidUITestStore
            }
            let root = try localStoreURL().deletingLastPathComponent()
            return .disk(root.appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("Selno.store"))
        }
        if environment["SELNO_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil {
            return .inMemory
        }
        return .local
    }

    /// Logical JSON backups written before a destructive "replace" import.
    /// UI tests use a folder beside their own store, so test rows never appear
    /// among the real automatic backups.
    static func automaticBackupDirectoryURL() throws -> URL {
        var directory = try applicationSupportDirectory()
            .appendingPathComponent("Selno", isDirectory: true)
        if ProcessInfo.processInfo.arguments.contains("--selno-ui-testing"),
           let value = ProcessInfo.processInfo.environment["SELNO_UI_TEST_STORE_ID"],
           let id = UUID(uuidString: value) {
            directory = directory
                .appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
        }
        return directory.appendingPathComponent("Backups", isDirectory: true)
    }

    private static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    static func makeContainer(storage: Storage = .local) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SelnoSchemaV5.self)
        let configuration: ModelConfiguration

        switch storage {
        case .inMemory:
            configuration = ModelConfiguration(
                "SelnoTests", schema: schema, isStoredInMemoryOnly: true,
                groupContainer: .none, cloudKitDatabase: .none
            )
        case .local:
            configuration = try diskConfiguration(schema: schema, url: localStoreURL())
        case .disk(let url):
            configuration = try diskConfiguration(schema: schema, url: url)
        }

        let container = try ModelContainer(
            for: schema,
            migrationPlan: SelnoMigrationPlan.self,
            configurations: [configuration]
        )
        container.mainContext.autosaveEnabled = false
        return container
    }

    private static func diskConfiguration(schema: Schema, url: URL) throws -> ModelConfiguration {
        guard url.isFileURL else { throw PersistenceError.invalidStoreURL }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return ModelConfiguration("Selno", schema: schema, url: url, cloudKitDatabase: .none)
    }
}

enum PersistenceError: LocalizedError {
    case invalidStoreURL
    case invalidUITestStore

    var errorDescription: String? {
        switch self {
        case .invalidStoreURL: "数据库地址必须是本地文件地址。"
        case .invalidUITestStore: "UI 测试缺少独立的数据库标识，已停止启动以保护正式数据。"
        }
    }
}
