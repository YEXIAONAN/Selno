import Foundation
import SwiftData

// MARK: - Errors

nonisolated enum WorkspaceError: LocalizedError, Equatable {
    case emptyName
    case nameTooLong
    case invalidEmoji
    case invalidAccent
    case invalidFilter(String)
    case moduleLimit
    case workspaceLimit
    case duplicateModule
    case moduleNotFound
    case workspaceNotFound
    case unsupportedSize
    case unsupportedModule
    case savedViewNotFound
    case globalCannotBeDeleted
    case onlyGlobalCanRestoreDefault
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName: "工作台名称不能为空。"
        case .nameTooLong: "工作台名称不能超过 \(WorkspaceLimits.maximumNameLength) 个字符。"
        case .invalidEmoji: "Emoji 不能超过 \(WorkspaceLimits.maximumEmojiLength) 个字符。"
        case .invalidAccent: "强调色无效。"
        case .invalidFilter(let detail): "筛选规则无效：\(detail)"
        case .moduleLimit: "每个工作台最多 \(WorkspaceLimits.maximumModulesPerWorkspace) 个模块。"
        case .workspaceLimit: "最多保留 \(WorkspaceLimits.maximumWorkspaces) 个工作台。"
        case .duplicateModule: "布局中包含重复的模块，无法保存。"
        case .moduleNotFound: "模块已不存在，请重新打开工作台。"
        case .workspaceNotFound: "工作台已不存在。"
        case .unsupportedSize: "此模块不支持所选尺寸。"
        case .unsupportedModule: "此模块由更新版本的 Selno 创建，当前版本不能修改它的配置。"
        case .savedViewNotFound: "所选任务视图已不存在。"
        case .globalCannotBeDeleted: "全局工作台不能删除，但可以自定义布局与筛选。"
        case .onlyGlobalCanRestoreDefault: "只有全局工作台可以恢复默认布局。"
        case .persistenceFailed(let detail): "保存工作台失败，已恢复上一次成功的配置：\(detail)"
        }
    }
}

// MARK: - Presets

nonisolated enum WorkspacePreset: String, CaseIterable, Identifiable, Sendable {
    case blank
    case campus
    case development
    case life
    case copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: "空白"
        case .campus: "校园"
        case .development: "开发"
        case .life: "生活"
        case .copy: "复制现有"
        }
    }

    var summary: String {
        switch self {
        case .blank: "从空工作台开始，自己添加模块。"
        case .campus: "聚焦课程、活动与项目进度，近期安排默认查看 7 天。"
        case .development: "更宽的任务列表与统计，适合按视图跟踪开发事项。"
        case .life: "收件箱、月历与快捷操作，保持日常轻量。"
        case .copy: "完整复制一个现有工作台的模块、尺寸与筛选。"
        }
    }

    var defaultName: String {
        switch self {
        case .blank: "新工作台"
        case .campus: "校园"
        case .development: "开发"
        case .life: "生活"
        case .copy: "工作台副本"
        }
    }

    var defaultEmoji: String {
        switch self {
        case .blank: "🗂"
        case .campus: "🎓"
        case .development: "💻"
        case .life: "🌿"
        case .copy: "🗂"
        }
    }

    var defaultAccent: WorkspaceAccent {
        switch self {
        case .blank, .copy: .sage
        case .campus: .ocean
        case .development: .slate
        case .life: .amber
        }
    }
}

nonisolated struct WorkspaceModuleSpec: Equatable {
    var kind: WorkspaceModuleKind
    var size: ModuleSize
    var config: WorkspaceModuleConfig

    init(kind: WorkspaceModuleKind, size: ModuleSize, config: WorkspaceModuleConfig) {
        self.kind = kind
        self.size = size
        self.config = config
    }
}

nonisolated enum DefaultWorkspaceFactory {
    static let globalName = "全局工作台"
    static let globalEmoji = "🧭"

    static var globalSpecs: [WorkspaceModuleSpec] {
        [
            WorkspaceModuleSpec(kind: .focus, size: .large,
                                config: WorkspaceModuleConfig(limit: 6)),
            WorkspaceModuleSpec(kind: .upcoming, size: .medium,
                                config: WorkspaceModuleConfig(days: 7, limit: 6)),
            WorkspaceModuleSpec(kind: .month, size: .medium, config: .default),
            WorkspaceModuleSpec(kind: .inbox, size: .medium,
                                config: WorkspaceModuleConfig(limit: 4)),
            WorkspaceModuleSpec(kind: .projects, size: .medium,
                                config: WorkspaceModuleConfig(limit: 3)),
            WorkspaceModuleSpec(kind: .stats, size: .small, config: .default),
            WorkspaceModuleSpec(kind: .quickActions, size: .small, config: .default),
        ]
    }

    static func specs(for preset: WorkspacePreset) -> [WorkspaceModuleSpec] {
        switch preset {
        case .blank, .copy:
            return []
        case .campus:
            return [
                WorkspaceModuleSpec(kind: .focus, size: .large,
                                    config: WorkspaceModuleConfig(limit: 6)),
                WorkspaceModuleSpec(kind: .upcoming, size: .medium,
                                    config: WorkspaceModuleConfig(days: 7, limit: 5)),
                WorkspaceModuleSpec(kind: .month, size: .medium, config: .default),
                WorkspaceModuleSpec(kind: .taskList, size: .medium,
                                    config: WorkspaceModuleConfig(filter: .activeOnly, limit: 8)),
                WorkspaceModuleSpec(kind: .projects, size: .medium,
                                    config: WorkspaceModuleConfig(limit: 3)),
            ]
        case .development:
            return [
                WorkspaceModuleSpec(kind: .focus, size: .large,
                                    config: WorkspaceModuleConfig(limit: 6)),
                WorkspaceModuleSpec(kind: .taskList, size: .large,
                                    config: WorkspaceModuleConfig(filter: .activeOnly, limit: 10)),
                WorkspaceModuleSpec(kind: .stats, size: .small, config: .default),
                WorkspaceModuleSpec(kind: .quickActions, size: .small, config: .default),
                WorkspaceModuleSpec(kind: .month, size: .medium, config: .default),
                WorkspaceModuleSpec(kind: .projects, size: .medium,
                                    config: WorkspaceModuleConfig(limit: 3)),
            ]
        case .life:
            return [
                WorkspaceModuleSpec(kind: .focus, size: .medium,
                                    config: WorkspaceModuleConfig(limit: 4)),
                WorkspaceModuleSpec(kind: .inbox, size: .medium,
                                    config: WorkspaceModuleConfig(limit: 4)),
                WorkspaceModuleSpec(kind: .month, size: .medium, config: .default),
                WorkspaceModuleSpec(kind: .stats, size: .small, config: .default),
                WorkspaceModuleSpec(kind: .quickActions, size: .small, config: .default),
                WorkspaceModuleSpec(kind: .upcoming, size: .medium,
                                    config: WorkspaceModuleConfig(days: 3, limit: 4)),
            ]
        }
    }
}

// MARK: - Service

@MainActor
struct WorkspaceService {
    let context: ModelContext

    // MARK: Reads

    func allWorkspaces() throws -> [Workspace] {
        try context.fetch(FetchDescriptor<Workspace>()).sorted {
            if $0.isGlobal != $1.isGlobal { return $0.isGlobal }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func globalWorkspace() throws -> Workspace? {
        try allWorkspaces().first(where: \.isGlobal)
    }

    func scenarioWorkspaces() throws -> [Workspace] {
        try allWorkspaces().filter { !$0.isGlobal }
    }

    func fetchWorkspace(id: UUID) throws -> Workspace? {
        var descriptor = FetchDescriptor<Workspace>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchModule(id: UUID) throws -> WorkspaceModule? {
        var descriptor = FetchDescriptor<WorkspaceModule>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func snapshot(for workspace: Workspace) -> WorkspaceSnapshot {
        workspace.snapshot
    }

    func persistedSnapshot(workspaceID: UUID) throws -> WorkspaceSnapshot? {
        try fetchWorkspace(id: workspaceID)?.snapshot
    }

    // MARK: Workspace lifecycle

    @discardableResult
    func createWorkspace(
        name: String,
        emoji: String,
        accent: WorkspaceAccent,
        filter: TaskFilterExpression,
        preset: WorkspacePreset,
        copySourceID: UUID? = nil,
        now: Date = .now
    ) throws -> Workspace {
        let existing = try allWorkspaces()
        guard existing.count < WorkspaceLimits.maximumWorkspaces else {
            throw WorkspaceError.workspaceLimit
        }
        let name = try validatedName(name)
        let emoji = try validatedEmoji(emoji, fallback: preset.defaultEmoji)
        let filter = try validatedFilter(filter)

        var specs: [WorkspaceModuleSpec] = []
        var copiedModules: [WorkspaceModuleSnapshot] = []
        if preset == .copy {
            guard let copySourceID, let source = try fetchWorkspace(id: copySourceID) else {
                throw WorkspaceError.workspaceNotFound
            }
            copiedModules = source.orderedModules.map(\.snapshot)
        } else {
            specs = DefaultWorkspaceFactory.specs(for: preset)
        }

        let scenarioOrders = existing.filter { !$0.isGlobal }.map(\.sortOrder)
        let workspace = Workspace(
            name: name, emoji: emoji, accent: accent,
            sortOrder: (scenarioOrders.max() ?? 0) + 1,
            isGlobal: false, filter: filter, now: now
        )
        context.insert(workspace)

        if !copiedModules.isEmpty {
            for (index, snapshot) in copiedModules.enumerated() {
                // A duplicate is a new configuration row. Keeping the source's
                // module UUIDs would make two workspaces claim the same identity
                // and break UUID-based merge and export.
                let module = WorkspaceModule(
                    id: UUID(),
                    kindRaw: snapshot.kindRaw,
                    sizeRaw: snapshot.sizeRaw,
                    sortOrder: index,
                    scopeRaw: snapshot.scopeRaw,
                    savedViewID: snapshot.savedViewID,
                    configData: snapshot.rawConfigData,
                    now: now
                )
                context.insert(module)
                module.workspace = workspace
            }
        } else {
            try insert(specs: specs, into: workspace, startingAt: 0, now: now)
        }

        try commit()
        return workspace
    }

    @discardableResult
    func duplicateWorkspace(_ source: Workspace, now: Date = .now) throws -> Workspace {
        let name = try uniqueName(base: "\(source.name) 副本")
        return try createWorkspace(
            name: name, emoji: source.emoji, accent: source.accent,
            filter: source.filter, preset: .copy, copySourceID: source.id, now: now
        )
    }

    func updateWorkspace(
        _ workspaceID: UUID,
        name: String,
        emoji: String,
        accent: WorkspaceAccent,
        filter: TaskFilterExpression,
        now: Date = .now
    ) throws {
        guard let workspace = try fetchWorkspace(id: workspaceID) else {
            throw WorkspaceError.workspaceNotFound
        }
        let name = try validatedName(name)
        let emoji = try validatedEmoji(emoji, fallback: workspace.isGlobal ? DefaultWorkspaceFactory.globalEmoji : "🗂")
        let filter = try validatedFilter(filter)
        guard WorkspaceAccent(rawValue: accent.rawValue) != nil else { throw WorkspaceError.invalidAccent }

        workspace.name = name
        workspace.emoji = emoji
        workspace.accentRaw = accent.rawValue
        workspace.filter = filter
        workspace.updatedAt = now
        try commit()
    }

    func deleteWorkspace(_ workspaceID: UUID) throws {
        guard let workspace = try fetchWorkspace(id: workspaceID) else {
            throw WorkspaceError.workspaceNotFound
        }
        guard !workspace.isGlobal else { throw WorkspaceError.globalCannotBeDeleted }

        let workspaces = try allWorkspaces()
        for module in workspace.orderedModules { context.delete(module) }
        context.delete(workspace)

        var order = 1
        for item in workspaces where item.id != workspaceID {
            if item.isGlobal {
                item.sortOrder = 0
            } else {
                item.sortOrder = order
                order += 1
            }
        }
        try commit()
    }

    func reorderWorkspaces(_ orderedIDs: [UUID]) throws {
        let workspaces = try allWorkspaces()
        let scenarios = workspaces.filter { !$0.isGlobal }
        var seen = Set<UUID>()
        var ordered: [Workspace] = []
        for id in orderedIDs {
            guard let workspace = scenarios.first(where: { $0.id == id }) else { continue }
            guard seen.insert(id).inserted else { continue }
            ordered.append(workspace)
        }
        ordered.append(contentsOf: scenarios.filter { !seen.contains($0.id) })
        for (index, workspace) in ordered.enumerated() { workspace.sortOrder = index + 1 }
        if let global = workspaces.first(where: \.isGlobal) { global.sortOrder = 0 }
        try commit()
    }

    // MARK: Module lifecycle

    @discardableResult
    func addModule(
        to workspaceID: UUID,
        kind: WorkspaceModuleKind,
        size: ModuleSize,
        now: Date = .now
    ) throws -> WorkspaceModuleSnapshot {
        guard let workspace = try fetchWorkspace(id: workspaceID) else {
            throw WorkspaceError.workspaceNotFound
        }
        guard workspace.orderedModules.count < WorkspaceLimits.maximumModulesPerWorkspace else {
            throw WorkspaceError.moduleLimit
        }
        guard let descriptor = WorkspaceModuleRegistry.descriptor(for: kind) else {
            throw WorkspaceError.unsupportedModule
        }
        guard descriptor.supports(size) else { throw WorkspaceError.unsupportedSize }

        let order = (workspace.orderedModules.map(\.sortOrder).max() ?? -1) + 1
        let module = WorkspaceModule(
            kind: kind, size: size, sortOrder: order,
            scope: .inherit, config: descriptor.defaultConfig, now: now
        )
        context.insert(module)
        module.workspace = workspace
        workspace.updatedAt = now
        try commit()
        return module.snapshot
    }

    func removeModule(id moduleID: UUID, from workspaceID: UUID, now: Date = .now) throws {
        guard let workspace = try fetchWorkspace(id: workspaceID) else {
            throw WorkspaceError.workspaceNotFound
        }
        guard let module = try fetchModule(id: moduleID),
              module.workspace?.id == workspaceID else {
            throw WorkspaceError.moduleNotFound
        }
        let remaining = workspace.orderedModules.filter { $0.id != moduleID }
        context.delete(module)
        for (index, item) in remaining.enumerated() {
            if item.sortOrder != index {
                item.sortOrder = index
                item.updatedAt = now
            }
        }
        workspace.updatedAt = now
        try commit()
    }

    /// Inserts the moved module immediately before `targetID`, or at the end when
    /// `targetID` is nil. Called once when a drag is dropped, never per mouse move.
    func moveModule(
        id moduleID: UUID,
        before targetID: UUID?,
        in workspaceID: UUID,
        now: Date = .now
    ) throws {
        guard let workspace = try fetchWorkspace(id: workspaceID) else {
            throw WorkspaceError.workspaceNotFound
        }
        var modules = workspace.orderedModules
        guard let sourceIndex = modules.firstIndex(where: { $0.id == moduleID }) else {
            throw WorkspaceError.moduleNotFound
        }
        if targetID == moduleID { return }
        let moved = modules.remove(at: sourceIndex)
        let insertion: Int
        if let targetID, let targetIndex = modules.firstIndex(where: { $0.id == targetID }) {
            insertion = targetIndex
        } else {
            insertion = modules.endIndex
        }
        modules.insert(moved, at: insertion)
        applyOrder(modules, now: now)
        workspace.updatedAt = now
        try commit()
    }

    func moveModule(
        id moduleID: UUID,
        toIndex: Int,
        in workspaceID: UUID,
        now: Date = .now
    ) throws {
        guard let workspace = try fetchWorkspace(id: workspaceID) else {
            throw WorkspaceError.workspaceNotFound
        }
        var modules = workspace.orderedModules
        guard let sourceIndex = modules.firstIndex(where: { $0.id == moduleID }) else {
            throw WorkspaceError.moduleNotFound
        }
        let moved = modules.remove(at: sourceIndex)
        let clamped = min(max(0, toIndex), modules.count)
        modules.insert(moved, at: clamped)
        applyOrder(modules, now: now)
        workspace.updatedAt = now
        try commit()
    }

    func setSize(
        _ size: ModuleSize,
        for moduleID: UUID,
        now: Date = .now
    ) throws {
        guard let module = try fetchModule(id: moduleID),
              let workspace = module.workspace else {
            throw WorkspaceError.moduleNotFound
        }
        guard let kind = module.kind,
              let descriptor = WorkspaceModuleRegistry.descriptor(for: kind) else {
            throw WorkspaceError.unsupportedModule
        }
        guard descriptor.supports(size) else { throw WorkspaceError.unsupportedSize }
        module.sizeRaw = size.rawValue
        module.updatedAt = now
        workspace.updatedAt = now
        try commit()
    }

    func updateModule(
        id moduleID: UUID,
        size: ModuleSize,
        scope: ModuleDataScope,
        savedViewID: UUID?,
        config: WorkspaceModuleConfig,
        now: Date = .now
    ) throws {
        guard let module = try fetchModule(id: moduleID),
              let workspace = module.workspace else {
            throw WorkspaceError.moduleNotFound
        }
        guard let kind = module.kind,
              let descriptor = WorkspaceModuleRegistry.descriptor(for: kind) else {
            throw WorkspaceError.unsupportedModule
        }
        guard descriptor.supports(size) else { throw WorkspaceError.unsupportedSize }

        var resolvedScope = scope
        if let savedViewID {
            var descriptor = FetchDescriptor<SavedTaskView>(predicate: #Predicate { $0.id == savedViewID })
            descriptor.fetchLimit = 1
            guard try context.fetch(descriptor).first != nil else {
                throw WorkspaceError.savedViewNotFound
            }
            // A saved view is a complete rule set. Combining it with the scenario
            // filter would be additive, so the module is always marked custom.
            resolvedScope = .custom
        }

        let config = try validatedConfig(config)
        module.sizeRaw = size.rawValue
        module.scopeRaw = resolvedScope.rawValue
        module.savedViewID = savedViewID
        module.configData = config.encoded(preserving: module.configData)
        module.updatedAt = now
        workspace.updatedAt = now
        try commit()
    }

    func updateUpcomingDays(
        _ days: Int,
        for moduleID: UUID,
        now: Date = .now
    ) throws {
        guard let module = try fetchModule(id: moduleID),
              let workspace = module.workspace,
              module.kind == .upcoming else {
            throw WorkspaceError.unsupportedModule
        }
        var config = module.config
        config.days = days == 7 ? 7 : 3
        module.configData = config.sanitized().encoded(preserving: module.configData)
        module.updatedAt = now
        workspace.updatedAt = now
        try commit()
    }

    func restoreDefaultLayout(for workspaceID: UUID, now: Date = .now) throws {
        guard let workspace = try fetchWorkspace(id: workspaceID) else {
            throw WorkspaceError.workspaceNotFound
        }
        guard workspace.isGlobal else { throw WorkspaceError.onlyGlobalCanRestoreDefault }
        for module in workspace.orderedModules { context.delete(module) }
        try insert(specs: DefaultWorkspaceFactory.globalSpecs, into: workspace, startingAt: 0, now: now)
        workspace.updatedAt = now
        try commit()
    }

    /// Commits an entire draft layout in one transaction. Existing module UUIDs
    /// are preserved; only removed rows are deleted and only genuinely new
    /// modules are inserted. Called once when the user leaves edit mode, never
    /// during a drag.
    func saveLayout(
        workspaceID: UUID,
        modules: [WorkspaceModuleSnapshot],
        now: Date = .now
    ) throws {
        guard let workspace = try fetchWorkspace(id: workspaceID) else {
            throw WorkspaceError.workspaceNotFound
        }
        guard modules.count <= WorkspaceLimits.maximumModulesPerWorkspace else {
            throw WorkspaceError.moduleLimit
        }
        guard Set(modules.map(\.id)).count == modules.count else {
            throw WorkspaceError.duplicateModule
        }

        let savedViewIDs = Set(try context.fetch(FetchDescriptor<SavedTaskView>()).map(\.id))
        let existing = Dictionary(uniqueKeysWithValues: workspace.orderedModules.map { ($0.id, $0) })
        var retained = Set<UUID>()

        // Any validation failure after the first mutation must restore the
        // previously committed layout, not leave a half-applied draft in memory.
        do {
            for (index, snapshot) in modules.enumerated() {
                let module: WorkspaceModule
                if let current = existing[snapshot.id] {
                    module = current
                } else {
                    let created = WorkspaceModule(snapshot: snapshot, sortOrder: index, now: now)
                    context.insert(created)
                    created.workspace = workspace
                    module = created
                }
                retained.insert(module.id)

                // Unknown module kinds are forward-compatible payloads: preserve
                // the raw kind, size, scope and config byte-for-byte and only
                // update the logical position.
                guard let kind = WorkspaceModuleKind(rawValue: snapshot.kindRaw),
                      let descriptor = WorkspaceModuleRegistry.descriptor(for: kind) else {
                    module.sortOrder = index
                    module.updatedAt = now
                    continue
                }
                guard descriptor.supports(snapshot.size) else { throw WorkspaceError.unsupportedSize }
                if let viewID = snapshot.savedViewID, !savedViewIDs.contains(viewID) {
                    throw WorkspaceError.savedViewNotFound
                }
                let config = try validatedConfig(snapshot.config)
                let scope = snapshot.savedViewID == nil ? snapshot.dataScope : .custom
                // Compare semantic values rather than bytes: canonicalizing a
                // known module's JSON would otherwise discard fields written by
                // a newer build even when the user changed only its position.
                let configChanged = module.config != config

                let changed = module.kindRaw != kind.rawValue
                    || module.sizeRaw != snapshot.size.rawValue
                    || module.scopeRaw != scope.rawValue
                    || module.savedViewID != snapshot.savedViewID
                    || module.sortOrder != index
                    || configChanged
                if changed {
                    module.kindRaw = kind.rawValue
                    module.sizeRaw = snapshot.size.rawValue
                    module.scopeRaw = scope.rawValue
                    module.savedViewID = snapshot.savedViewID
                    if configChanged || module.configData == nil {
                        module.configData = config.encoded(preserving: module.configData)
                    }
                    module.sortOrder = index
                    module.updatedAt = now
                }
            }

            for module in existing.values where !retained.contains(module.id) {
                context.delete(module)
            }
            workspace.updatedAt = now
            try commit()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Helpers

    private func insert(
        specs: [WorkspaceModuleSpec],
        into workspace: Workspace,
        startingAt start: Int,
        now: Date
    ) throws {
        for (offset, spec) in specs.enumerated() {
            guard let descriptor = WorkspaceModuleRegistry.descriptor(for: spec.kind) else {
                throw WorkspaceError.unsupportedModule
            }
            let size = descriptor.supports(spec.size) ? spec.size : descriptor.defaultSize
            let config = try validatedConfig(spec.config)
            let module = WorkspaceModule(
                kind: spec.kind, size: size, sortOrder: start + offset,
                scope: .inherit, config: config, now: now
            )
            context.insert(module)
            module.workspace = workspace
        }
    }

    private func applyOrder(_ modules: [WorkspaceModule], now: Date) {
        for (index, module) in modules.enumerated() where module.sortOrder != index {
            module.sortOrder = index
            module.updatedAt = now
        }
    }

    private func validatedName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw WorkspaceError.emptyName }
        guard value.count <= WorkspaceLimits.maximumNameLength else { throw WorkspaceError.nameTooLong }
        return value
    }

    private func validatedEmoji(_ emoji: String, fallback: String) throws -> String {
        let value = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= WorkspaceLimits.maximumEmojiLength else { throw WorkspaceError.invalidEmoji }
        return value.isEmpty ? fallback : value
    }

    private func validatedFilter(_ filter: TaskFilterExpression) throws -> TaskFilterExpression {
        do { return try filter.validated() }
        catch { throw WorkspaceError.invalidFilter(error.localizedDescription) }
    }

    private func validatedConfig(_ config: WorkspaceModuleConfig) throws -> WorkspaceModuleConfig {
        var value = config.sanitized()
        if let filter = value.filter {
            do { value.filter = try filter.validated() }
            catch { throw WorkspaceError.invalidFilter(error.localizedDescription) }
        }
        return value
    }

    private func uniqueName(base: String) throws -> String {
        let existing = Set(try allWorkspaces().map(\.name))
        if !existing.contains(base) { return base }
        var counter = 2
        while existing.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    private func commit() throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw WorkspaceError.persistenceFailed(error.localizedDescription)
        }
    }
}

// MARK: - Saved views

@MainActor
struct SavedViewService {
    let context: ModelContext

    func all() throws -> [SavedTaskView] {
        try context.fetch(FetchDescriptor<SavedTaskView>()).sorted {
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    @discardableResult
    func create(
        name: String,
        emoji: String,
        colorHex: String,
        filter: TaskFilterExpression,
        sort: TaskSortMode,
        limit: Int,
        now: Date = .now
    ) throws -> SavedTaskView {
        let values = try validate(name: name, emoji: emoji, colorHex: colorHex,
                                  filter: filter, limit: limit)
        let view = SavedTaskView(name: values.name, emoji: values.emoji,
                                 colorHex: values.colorHex, filter: values.filter,
                                 sort: sort, limit: values.limit, now: now)
        context.insert(view)
        try commit()
        return view
    }

    func update(
        _ viewID: UUID,
        name: String,
        emoji: String,
        colorHex: String,
        filter: TaskFilterExpression,
        sort: TaskSortMode,
        limit: Int,
        now: Date = .now
    ) throws {
        guard let view = try fetch(viewID) else { throw WorkspaceError.savedViewNotFound }
        let values = try validate(name: name, emoji: emoji, colorHex: colorHex,
                                  filter: filter, limit: limit)
        view.name = values.name
        view.emoji = values.emoji
        view.colorHex = values.colorHex
        view.filter = values.filter
        view.sortRaw = sort.rawValue
        view.limit = values.limit
        view.updatedAt = now
        try commit()
    }

    @discardableResult
    func duplicate(_ viewID: UUID, now: Date = .now) throws -> SavedTaskView {
        guard let view = try fetch(viewID) else { throw WorkspaceError.savedViewNotFound }
        let base = "\(view.name) 副本"
        let existing = Set(try all().map(\.name))
        var name = base
        var counter = 2
        while existing.contains(name) {
            name = "\(base) \(counter)"
            counter += 1
        }
        let copy = SavedTaskView(
            name: name, emoji: view.emoji, colorHex: view.colorHex,
            filter: view.filter, sort: view.sort, limit: view.effectiveLimit, now: now
        )
        context.insert(copy)
        try commit()
        return copy
    }

    /// Deleting a view removes configuration only. Modules pointing at it are
    /// detached in the same transaction so no board can reference a missing view.
    func delete(_ viewID: UUID, now: Date = .now) throws {
        guard let view = try fetch(viewID) else { throw WorkspaceError.savedViewNotFound }
        let modules = try context.fetch(FetchDescriptor<WorkspaceModule>())
        for module in modules where module.savedViewID == viewID {
            module.savedViewID = nil
            module.scopeRaw = ModuleDataScope.inherit.rawValue
            module.updatedAt = now
            module.workspace?.updatedAt = now
        }
        context.delete(view)
        try commit()
    }

    func fetch(_ id: UUID) throws -> SavedTaskView? {
        var descriptor = FetchDescriptor<SavedTaskView>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func validate(
        name: String,
        emoji: String,
        colorHex: String,
        filter: TaskFilterExpression,
        limit: Int
    ) throws -> (name: String, emoji: String, colorHex: String,
                 filter: TaskFilterExpression, limit: Int) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WorkspaceError.emptyName }
        guard name.count <= WorkspaceLimits.maximumNameLength else { throw WorkspaceError.nameTooLong }
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard emoji.count <= WorkspaceLimits.maximumEmojiLength else { throw WorkspaceError.invalidEmoji }
        let hex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else {
            throw WorkspaceError.invalidFilter("视图颜色无效")
        }
        let validatedFilter: TaskFilterExpression
        do { validatedFilter = try filter.validated() }
        catch { throw WorkspaceError.invalidFilter(error.localizedDescription) }
        return (name, emoji.isEmpty ? "🔎" : emoji, "#\(hex)", validatedFilter,
                min(max(limit, 1), WorkspaceLimits.taskListLimitRange.upperBound))
    }

    private func commit() throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw WorkspaceError.persistenceFailed(error.localizedDescription)
        }
    }
}

// MARK: - Seeding and repair

@MainActor
enum WorkspaceSeeder {
    /// Creates the global workspace exactly once. Existing user workspaces are
    /// never replaced; a store that somehow lost its global workspace gets a new
    /// one without touching any task, project, tag, template or event.
    @discardableResult
    static func insertDefaultGlobalIfNeeded(
        in context: ModelContext,
        now: Date = .now
    ) throws -> Workspace? {
        let existing = try context.fetch(FetchDescriptor<Workspace>())
        guard !existing.contains(where: \.isGlobal) else { return nil }

        let global = Workspace(
            name: DefaultWorkspaceFactory.globalName,
            emoji: DefaultWorkspaceFactory.globalEmoji,
            accent: .sage,
            sortOrder: 0,
            isGlobal: true,
            filter: .unrestricted,
            now: now
        )
        context.insert(global)
        for (index, spec) in DefaultWorkspaceFactory.globalSpecs.enumerated() {
            let module = WorkspaceModule(
                kind: spec.kind,
                size: spec.size,
                sortOrder: index,
                scope: .inherit,
                config: spec.config.sanitized(),
                now: now
            )
            context.insert(module)
            module.workspace = global
        }
        return global
    }

    static func seedIfNeeded(in context: ModelContext, now: Date = .now) throws {
        do {
            let inserted = try insertDefaultGlobalIfNeeded(in: context, now: now)
            let repaired = try WorkspaceSanitizer.normalize(in: context, now: now)
            if inserted != nil || repaired || context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
enum WorkspaceSanitizer {
    /// Repairs only configuration rows. Business entities are never read or
    /// modified. Unknown module kinds are preserved byte-for-byte; known kinds
    /// are clamped to supported sizes and valid filter values.
    @discardableResult
    static func normalize(in context: ModelContext, now: Date = .now) throws -> Bool {
        let workspaces = try context.fetch(FetchDescriptor<Workspace>()).sorted {
            if $0.isGlobal != $1.isGlobal { return $0.isGlobal }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let savedViewIDs = Set(try context.fetch(FetchDescriptor<SavedTaskView>()).map(\.id))
        var changed = false
        var seenGlobal = false
        var scenarioOrder = 1

        for workspace in workspaces {
            var workspaceChanged = false

            if workspace.isGlobal {
                if seenGlobal {
                    workspace.isGlobal = false
                    workspaceChanged = true
                } else {
                    seenGlobal = true
                    if workspace.sortOrder != 0 { workspace.sortOrder = 0; workspaceChanged = true }
                }
            }
            if !workspace.isGlobal {
                if workspace.sortOrder != scenarioOrder {
                    workspace.sortOrder = scenarioOrder
                    workspaceChanged = true
                }
                scenarioOrder += 1
            }

            let fallbackName = workspace.isGlobal
                ? DefaultWorkspaceFactory.globalName : "未命名场景"
            let name = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { workspace.name = fallbackName; workspaceChanged = true }
            if workspace.emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workspace.emoji = workspace.isGlobal ? DefaultWorkspaceFactory.globalEmoji : "🗂"
                workspaceChanged = true
            }
            if WorkspaceAccent(rawValue: workspace.accentRaw) == nil {
                workspace.accentRaw = WorkspaceAccent.sage.rawValue
                workspaceChanged = true
            }

            if Self.filterNeedsRepair(workspace.filterData) {
                workspace.filterData = WorkspaceCoding.filterData(workspace.filter,
                                                                 preserving: workspace.filterData)
                workspaceChanged = true
            }

            let modules = workspace.orderedModules
            for (index, module) in modules.enumerated() {
                if module.sortOrder != index {
                    module.sortOrder = index
                    module.updatedAt = now
                    workspaceChanged = true
                }

                if let kind = module.kind,
                   let descriptor = WorkspaceModuleRegistry.descriptor(for: kind) {
                    if ModuleSize(rawValue: module.sizeRaw) == nil || !descriptor.supports(module.size) {
                        module.sizeRaw = descriptor.defaultSize.rawValue
                        module.updatedAt = now
                        workspaceChanged = true
                    }
                    if ModuleDataScope(rawValue: module.scopeRaw) == nil {
                        module.scopeRaw = ModuleDataScope.inherit.rawValue
                        module.updatedAt = now
                        workspaceChanged = true
                    }
                    if let viewID = module.savedViewID, !savedViewIDs.contains(viewID) {
                        module.savedViewID = nil
                        module.updatedAt = now
                        workspaceChanged = true
                    }
                    if module.kind == .taskList, module.savedViewID != nil,
                       module.scope != .custom {
                        module.scopeRaw = ModuleDataScope.custom.rawValue
                        module.updatedAt = now
                        workspaceChanged = true
                    }
                    let config = module.config
                    if Self.configNeedsRepair(module.configData) {
                        module.configData = config.encoded(preserving: module.configData)
                        module.updatedAt = now
                        workspaceChanged = true
                    }
                }
            }

            if workspaceChanged {
                workspace.updatedAt = now
                changed = true
            }
        }
        return changed
    }

    /// A missing or malformed filter is rebuilt, and invalid known values are
    /// clamped. A valid filter is left byte-for-byte alone so unknown keys from
    /// a newer build survive launch.
    private static func filterNeedsRepair(_ data: Data?) -> Bool {
        guard let data,
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any],
              let filter = try? JSONDecoder().decode(TaskFilterExpression.self, from: data) else {
            return true
        }
        return filter.sanitized() != filter
    }

    /// A missing or malformed config is rebuilt, and invalid known values are
    /// clamped. A valid config is left byte-for-byte alone so unknown keys from
    /// a newer build survive launch, even after this build reads the module.
    private static func configNeedsRepair(_ data: Data?) -> Bool {
        guard let data,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return true
        }
        if let rawDays = object["days"] {
            guard let days = rawDays as? Int, days == 3 || days == 7 else { return true }
        }
        if let rawLimit = object["limit"] {
            guard let limit = rawLimit as? Int,
                  WorkspaceLimits.taskListLimitRange.contains(limit) else { return true }
        }
        if let rawSort = object["sortRaw"] {
            guard let sortRaw = rawSort as? String,
                  TaskSortMode(rawValue: sortRaw) != nil else { return true }
        }
        if let rawFilter = object["filter"] {
            guard let filterData = try? JSONSerialization.data(withJSONObject: rawFilter),
                  let filter = try? JSONDecoder().decode(TaskFilterExpression.self,
                                                         from: filterData),
                  filter.sanitized() == filter else { return true }
        }
        return false
    }
}