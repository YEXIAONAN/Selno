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
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Selno", isDirectory: true)
        .appendingPathComponent("Selno.store")
    }

    static func makeContainer(storage: Storage = .local) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SelnoSchemaV3.self)
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
