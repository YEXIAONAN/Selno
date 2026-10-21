import Foundation
import SwiftData

// MARK: - Codable helpers

nonisolated enum WorkspaceCoding {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func filterData(_ filter: TaskFilterExpression) -> Data? {
        encode(filter.sanitized())
    }

    /// Rewrites the fields this build owns while leaving keys introduced by a
    /// newer build in place. This is used when a stored filter is edited, not
    /// when a brand-new filter is created.
    static func filterData(_ filter: TaskFilterExpression, preserving raw: Data?) -> Data? {
        let canonical = filterData(filter)
        guard let raw,
              var object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let canonical,
              let canonicalObject = (try? JSONSerialization.jsonObject(with: canonical)) as? [String: Any] else {
            return canonical
        }
        for key in TaskFilterExpression.persistedKeys {
            object.removeValue(forKey: key)
        }
        for (key, value) in canonicalObject {
            object[key] = value
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func filter(from data: Data?) -> TaskFilterExpression {
        (decode(TaskFilterExpression.self, from: data) ?? .unrestricted).sanitized()
    }
}

// MARK: - Module configuration

/// A deliberately small configuration shared by every built-in module. Keeping
/// one tolerant Codable shape means an empty or partially unknown config can
/// never prevent the rest of a workspace from loading.
nonisolated struct WorkspaceModuleConfig: Codable, Equatable, Hashable {
    var filter: TaskFilterExpression?
    var days: Int
    var limit: Int
    var sortRaw: String

    init(
        filter: TaskFilterExpression? = nil,
        days: Int = 3,
        limit: Int = 8,
        sortRaw: String = TaskSortMode.standard.rawValue
    ) {
        self.filter = filter
        self.days = days
        self.limit = limit
        self.sortRaw = sortRaw
    }

    static var `default`: WorkspaceModuleConfig { WorkspaceModuleConfig() }

    var sort: TaskSortMode { TaskSortMode(rawValue: sortRaw) ?? .standard }
    var effectiveLimit: Int { min(max(limit, WorkspaceLimits.taskListLimitRange.lowerBound), WorkspaceLimits.taskListLimitRange.upperBound) }
    var effectiveDays: Int { days == 7 ? 7 : 3 }

    private enum CodingKeys: String, CodingKey { case filter, days, limit, sortRaw }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filter = try? c.decodeIfPresent(TaskFilterExpression.self, forKey: .filter)
        days = (try? c.decode(Int.self, forKey: .days)) ?? 3
        limit = (try? c.decode(Int.self, forKey: .limit)) ?? 8
        sortRaw = (try? c.decode(String.self, forKey: .sortRaw)) ?? TaskSortMode.standard.rawValue
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(filter, forKey: .filter)
        try c.encode(days, forKey: .days)
        try c.encode(limit, forKey: .limit)
        try c.encode(sortRaw, forKey: .sortRaw)
    }

    func sanitized() -> WorkspaceModuleConfig {
        var value = self
        value.filter = filter?.sanitized()
        value.days = effectiveDays
        value.limit = effectiveLimit
        if TaskSortMode(rawValue: sortRaw) == nil { value.sortRaw = TaskSortMode.standard.rawValue }
        return value
    }

    static func decode(from data: Data?) -> WorkspaceModuleConfig {
        guard let data, let value = WorkspaceCoding.decode(WorkspaceModuleConfig.self, from: data) else {
            return .default
        }
        return value.sanitized()
    }

    func encoded() -> Data? { WorkspaceCoding.encode(self) }

    /// Writes the four known fields while retaining any keys a newer Selno may
    /// have stored in the same configuration object. This keeps a known module's
    /// future display options alive when the user resizes or reorders it here.
    func encoded(preserving raw: Data?) -> Data? {
        guard let raw,
              var object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
            return encoded()
        }
        if let filter, let filterData = WorkspaceCoding.encode(filter),
           let filterObject = try? JSONSerialization.jsonObject(with: filterData) {
            object["filter"] = filterObject
        } else {
            object.removeValue(forKey: "filter")
        }
        object["days"] = days
        object["limit"] = limit
        object["sortRaw"] = sortRaw
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

// MARK: - Workspace

@Model
final class Workspace {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🗂"
    var accentRaw: String = WorkspaceAccent.sage.rawValue
    var sortOrder: Int = 0
    /// Exactly one workspace is global. It is created by the first Phase 05
    /// launch, cannot be deleted, and its layout may still be customized.
    var isGlobal: Bool = false
    var filterData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \WorkspaceModule.workspace)
    var modules: [WorkspaceModule]? = []

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🗂",
        accent: WorkspaceAccent = .sage,
        sortOrder: Int = 0,
        isGlobal: Bool = false,
        filter: TaskFilterExpression = .unrestricted,
        now: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.accentRaw = accent.rawValue
        self.sortOrder = sortOrder
        self.isGlobal = isGlobal
        self.filterData = WorkspaceCoding.filterData(filter)
        self.createdAt = now
        self.updatedAt = now
    }

    var accent: WorkspaceAccent {
        get { WorkspaceAccent(rawValue: accentRaw) ?? .sage }
        set { accentRaw = newValue.rawValue }
    }

    var filter: TaskFilterExpression {
        get { WorkspaceCoding.filter(from: filterData) }
        set { filterData = WorkspaceCoding.filterData(newValue, preserving: filterData) }
    }

    var orderedModules: [WorkspaceModule] {
        (modules ?? []).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var snapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: id,
            name: name,
            emoji: emoji,
            accentRaw: accentRaw,
            sortOrder: sortOrder,
            isGlobal: isGlobal,
            filter: filter,
            createdAt: createdAt,
            updatedAt: updatedAt,
            modules: orderedModules.map(\.snapshot)
        )
    }
}

// MARK: - Module

@Model
final class WorkspaceModule {
    var id: UUID = UUID()
    /// Stored as a raw string on purpose: a module written by a newer Selno is
    /// preserved and shown as an inert placeholder instead of being discarded.
    var kindRaw: String = WorkspaceModuleKind.focus.rawValue
    var sizeRaw: String = ModuleSize.medium.rawValue
    var sortOrder: Int = 0
    var scopeRaw: String = ModuleDataScope.inherit.rawValue
    var savedViewID: UUID?
    var configData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var workspace: Workspace?

    init(
        id: UUID = UUID(),
        kind: WorkspaceModuleKind,
        size: ModuleSize,
        sortOrder: Int,
        scope: ModuleDataScope = .inherit,
        savedViewID: UUID? = nil,
        config: WorkspaceModuleConfig = .default,
        now: Date = .now
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.sizeRaw = size.rawValue
        self.sortOrder = sortOrder
        self.scopeRaw = scope.rawValue
        self.savedViewID = savedViewID
        self.configData = config.encoded()
        self.createdAt = now
        self.updatedAt = now
    }

    /// Used by copy/import so a module type introduced by a newer Selno keeps its
    /// raw kind/size/scope/config bytes exactly as stored.
    init(
        id: UUID,
        kindRaw: String,
        sizeRaw: String,
        sortOrder: Int,
        scopeRaw: String,
        savedViewID: UUID?,
        configData: Data?,
        now: Date
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.sizeRaw = sizeRaw
        self.sortOrder = sortOrder
        self.scopeRaw = scopeRaw
        self.savedViewID = savedViewID
        self.configData = configData
        self.createdAt = now
        self.updatedAt = now
    }

    init(snapshot: WorkspaceModuleSnapshot, sortOrder: Int, now: Date) {
        self.id = snapshot.id
        self.kindRaw = snapshot.kindRaw
        self.sizeRaw = snapshot.sizeRaw
        self.sortOrder = sortOrder
        self.scopeRaw = snapshot.scopeRaw
        self.savedViewID = snapshot.savedViewID
        self.configData = snapshot.rawConfigData
        self.createdAt = now
        self.updatedAt = now
    }

    var kind: WorkspaceModuleKind? { WorkspaceModuleKind(rawValue: kindRaw) }
    var isKnownKind: Bool { kind != nil }
    var size: ModuleSize { ModuleSize(rawValue: sizeRaw) ?? .medium }
    var scope: ModuleDataScope { ModuleDataScope(rawValue: scopeRaw) ?? .inherit }

    var config: WorkspaceModuleConfig {
        get { WorkspaceModuleConfig.decode(from: configData) }
        set { configData = newValue.sanitized().encoded(preserving: configData) }
    }

    var snapshot: WorkspaceModuleSnapshot {
        WorkspaceModuleSnapshot(
            id: id,
            kindRaw: kindRaw,
            sizeRaw: sizeRaw,
            sortOrder: sortOrder,
            scopeRaw: scopeRaw,
            savedViewID: savedViewID,
            config: config,
            rawConfigData: configData,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Saved view

@Model
final class SavedTaskView {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🔎"
    var colorHex: String = "#4F7A69"
    var filterData: Data?
    var sortRaw: String = TaskSortMode.standard.rawValue
    var limit: Int = 8
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🔎",
        colorHex: String = "#4F7A69",
        filter: TaskFilterExpression,
        sort: TaskSortMode = .standard,
        limit: Int = 8,
        now: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.filterData = WorkspaceCoding.filterData(filter)
        self.sortRaw = sort.rawValue
        self.limit = limit
        self.createdAt = now
        self.updatedAt = now
    }

    var filter: TaskFilterExpression {
        get { WorkspaceCoding.filter(from: filterData) }
        set { filterData = WorkspaceCoding.filterData(newValue, preserving: filterData) }
    }

    var sort: TaskSortMode { TaskSortMode(rawValue: sortRaw) ?? .standard }
    var effectiveLimit: Int { min(max(limit, 1), WorkspaceLimits.taskListLimitRange.upperBound) }

    var snapshot: SavedTaskViewSnapshot {
        SavedTaskViewSnapshot(
            id: id, name: name, emoji: emoji, colorHex: colorHex,
            filter: filter, sortRaw: sortRaw, limit: limit,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Immutable snapshots

nonisolated struct WorkspaceModuleSnapshot: Identifiable, Equatable, Hashable {
    var id: UUID
    var kindRaw: String
    var sizeRaw: String
    var sortOrder: Int
    var scopeRaw: String
    var savedViewID: UUID?
    var config: WorkspaceModuleConfig
    var rawConfigData: Data?
    var createdAt: Date
    var updatedAt: Date

    var kind: WorkspaceModuleKind? { WorkspaceModuleKind(rawValue: kindRaw) }
    var isKnownKind: Bool { kind != nil }
    var descriptor: WorkspaceModuleDescriptor? {
        kind.flatMap { WorkspaceModuleRegistry.descriptor(for: $0) }
    }
    var title: String { descriptor?.title ?? "未知模块" }
    var symbolName: String { descriptor?.symbolName ?? "questionmark.square.dashed" }

    var size: ModuleSize { ModuleSize(rawValue: sizeRaw) ?? .medium }
    var dataScope: ModuleDataScope { ModuleDataScope(rawValue: scopeRaw) ?? .inherit }
    var scope: ModuleDataScope { dataScope }

    /// The persisted size is honored only when the module supports it. Old or
    /// hand-edited data therefore renders at a valid size instead of breaking
    /// the board; the sanitizer writes the repair back on the next import.
    var effectiveSize: ModuleSize {
        guard let descriptor else { return .medium }
        return descriptor.supports(size) ? size : descriptor.defaultSize
    }

    var signature: String {
        "\(id.uuidString)|\(kindRaw)|\(effectiveSize.rawValue)|\(scopeRaw)|\(savedViewID?.uuidString ?? "")|\(config.hashValue)|\(rawConfigData?.base64EncodedString() ?? "")"
    }

    func with(sortOrder: Int) -> WorkspaceModuleSnapshot {
        var value = self
        value.sortOrder = sortOrder
        return value
    }
}

nonisolated struct WorkspaceSnapshot: Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    var accentRaw: String
    var sortOrder: Int
    var isGlobal: Bool
    var filter: TaskFilterExpression
    var createdAt: Date
    var updatedAt: Date
    var modules: [WorkspaceModuleSnapshot]

    var accent: WorkspaceAccent { WorkspaceAccent(rawValue: accentRaw) ?? .sage }
    var orderedModules: [WorkspaceModuleSnapshot] {
        modules.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var layoutSignature: String {
        "\(id.uuidString)|\(updatedAt.timeIntervalSince1970)|" + orderedModules.map(\.signature).joined(separator: ";")
    }
}

nonisolated struct SavedTaskViewSnapshot: Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    var colorHex: String
    var filter: TaskFilterExpression
    var sortRaw: String
    var limit: Int
    var createdAt: Date
    var updatedAt: Date

    var sort: TaskSortMode { TaskSortMode(rawValue: sortRaw) ?? .standard }
    var effectiveLimit: Int { min(max(limit, 1), WorkspaceLimits.taskListLimitRange.upperBound) }
}