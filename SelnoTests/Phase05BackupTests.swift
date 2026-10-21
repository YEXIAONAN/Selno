import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct Phase05BackupTests {
    private let base = Date(timeIntervalSince1970: 1_790_003_000.125)

    private struct ConfigFixture {
        let globalID: UUID
        let workspaceID: UUID
        let savedViewID: UUID
        let taskListModuleID: UUID
        let unknownModuleID: UUID
        let taskID: UUID
        let unknownConfig: Data
        let viewFilter: TaskFilterExpression
        let taskListConfig: WorkspaceModuleConfig
    }

    private struct InjectedFailure: Error {}

    private func make() throws -> (ModelContainer, ModelContext) {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        return (container, container.mainContext)
    }

    private func seed(_ context: ModelContext) throws -> Workspace {
        try WorkspaceSeeder.seedIfNeeded(in: context, now: base)
        return try #require(try WorkspaceService(context: context).globalWorkspace())
    }

    private func exportDocument(from context: ModelContext) throws -> BackupDocument {
        try BackupExportService(context: context).makeDocument(now: base)
    }

    private func apply(
        _ document: BackupDocument,
        to context: ModelContext,
        mode: BackupImportMode,
        directory: URL? = nil,
        beforeSave: ((ModelContext) throws -> Void)? = nil
    ) throws -> BackupImportResult {
        let resolved = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase05Backups-\(UUID().uuidString)", isDirectory: true)
        defer {
            if directory == nil { try? FileManager.default.removeItem(at: resolved) }
        }
        return try BackupImportService(context: context, backupDirectory: resolved)
            .apply(document: document, mode: mode, now: base, beforeSave: beforeSave)
    }

    /// Builds a representative v2 document: two workspaces, a saved view, a
    /// configured task list, an unknown future module with raw bytes, and a task.
    private func makeConfiguredSource() throws -> (BackupDocument, ConfigFixture) {
        let (container, context) = try make()
        _ = container
        let global = try seed(context)
        let service = WorkspaceService(context: context)
        try service.updateWorkspace(
            global.id, name: global.name, emoji: global.emoji, accent: .ocean,
            filter: TaskFilterExpression(statuses: [TaskStatus.pending.rawValue,
                                                    TaskStatus.completed.rawValue]),
            now: base
        )

        let scenario = try service.createWorkspace(
            name: "校园", emoji: "🎓", accent: .ocean,
            filter: .activeOnly, preset: .campus, now: base
        )
        let viewFilter = TaskFilterExpression(
            statuses: [TaskStatus.completed.rawValue],
            importances: [TaskImportance.high.rawValue],
            dateField: .due, dateRange: .next7Days,
            searchText: "复盘"
        )
        let view = try SavedViewService(context: context).create(
            name: "本周复盘", emoji: "🧭", colorHex: "#4F7A69",
            filter: viewFilter, sort: .dueDate, limit: 12, now: base
        )

        let moduleFilter = TaskFilterExpression(
            statuses: [TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue],
            tagIDs: [],
            dateField: .planned, dateRange: .next3Days,
            dueState: .hasDue
        )
        let taskListConfig = WorkspaceModuleConfig(
            filter: moduleFilter, days: 7, limit: 9,
            sortRaw: TaskSortMode.importance.rawValue
        )
        let taskList = try service.addModule(to: scenario.id, kind: .taskList,
                                             size: .medium, now: base)
        try service.updateModule(id: taskList.id, size: .large, scope: .inherit,
                                 savedViewID: view.id, config: taskListConfig,
                                 now: base.addingTimeInterval(10))

        let unknownID = UUID()
        let unknownConfig = Data(#"{"version":9,"opaque":"保留","nested":{"x":1}}"#.utf8)
        let unknown = WorkspaceModule(
            id: unknownID, kindRaw: "futureWidget", sizeRaw: "galaxy",
            sortOrder: 99, scopeRaw: "edge", savedViewID: nil,
            configData: unknownConfig, now: base
        )
        context.insert(unknown)
        unknown.workspace = scenario

        let taskID = UUID()
        let task = TodoTask(id: taskID, title: "备份任务", notes: "导出与恢复",
                            status: .pending, importance: .high, now: base)
        task.dueAt = base.addingTimeInterval(86_400)
        context.insert(task)
        try context.save()

        let document = try exportDocument(from: context)
        let fixture = ConfigFixture(
            globalID: global.id, workspaceID: scenario.id, savedViewID: view.id,
            taskListModuleID: taskList.id, unknownModuleID: unknownID,
            taskID: taskID, unknownConfig: unknownConfig,
            viewFilter: viewFilter,
            taskListConfig: taskListConfig.sanitized()
        )
        return (document, fixture)
    }

    // MARK: - Export

    @Test func exportIncludesWorkspacesLayoutSavedViewsAndForwardCompatibleBytes() throws {
        let (document, fixture) = try makeConfiguredSource()
        let backup = document.backup

        #expect(backup.schemaVersion == 2)
        #expect(backup.format == SelnoBackup.formatIdentifier)
        #expect(backup.data.workspaces.count == 2)
        #expect(backup.data.savedViews.count == 1)
        let moduleCount = backup.data.workspaces.reduce(0) { $0 + $1.modules.count }
        #expect(moduleCount == DefaultWorkspaceFactory.globalSpecs.count + 5 + 1 + 1)
        #expect(document.counts.workspaces == 2)
        #expect(document.counts.modules == moduleCount)
        #expect(document.counts.savedViews == 1)
        #expect(document.counts.tasks == 1)

        let global = try #require(backup.data.workspaces.first { $0.id == fixture.globalID })
        #expect(global.isGlobal)
        #expect(global.accent == WorkspaceAccent.ocean.rawValue)
        #expect(global.filter?.statuses
                == [TaskStatus.pending.rawValue, TaskStatus.completed.rawValue])

        let scenario = try #require(backup.data.workspaces.first { $0.id == fixture.workspaceID })
        #expect(scenario.name == "校园")
        #expect(scenario.emoji == "🎓")
        #expect(!scenario.isGlobal)
        #expect(scenario.filter == TaskFilterExpression.activeOnly)

        let view = try #require(backup.data.savedViews.first { $0.id == fixture.savedViewID })
        #expect(view.name == "本周复盘")
        #expect(view.emoji == "🧭")
        #expect(view.colorHex == "#4F7A69")
        #expect(view.sortRaw == TaskSortMode.dueDate.rawValue)
        #expect(view.limit == 12)
        #expect(view.filter == fixture.viewFilter)

        let taskList = try #require(scenario.modules.first { $0.id == fixture.taskListModuleID })
        #expect(taskList.kind == WorkspaceModuleKind.taskList.rawValue)
        #expect(taskList.size == ModuleSize.large.rawValue)
        #expect(taskList.scope == ModuleDataScope.custom.rawValue)
        #expect(taskList.savedViewID == fixture.savedViewID)
        #expect(taskList.config == fixture.taskListConfig)
        #expect(taskList.config?.filter == fixture.taskListConfig.filter)

        let unknown = try #require(scenario.modules.first { $0.id == fixture.unknownModuleID })
        #expect(unknown.kind == "futureWidget")
        #expect(unknown.size == "galaxy")
        #expect(unknown.scope == "edge")
        #expect(unknown.configRawBase64.flatMap { Data(base64Encoded: $0) }
                == fixture.unknownConfig)

        // Encoding is deterministic and decoding preserves the structured shape.
        let first = try BackupCodec.encode(backup)
        let second = try BackupCodec.encode(backup)
        #expect(first == second)
        let decoded = try BackupCodec.decode(first)
        try BackupCodec.validate(decoded)
        #expect(decoded.data.workspaces.count == 2)
        #expect(decoded.data.savedViews.count == 1)
        #expect(decoded.data.workspaces
            .first { $0.id == fixture.workspaceID }?
            .modules.first { $0.id == fixture.unknownModuleID }?
            .configRawBase64.flatMap { Data(base64Encoded: $0) } == fixture.unknownConfig)
    }

    @Test func exportNeverMutatesOrSavesTheLiveContext() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        _ = try WorkspaceService(context: context).createWorkspace(
            name: "场景", emoji: "🧪", accent: .sage,
            filter: .activeOnly, preset: .campus, now: base
        )
        #expect(context.hasChanges == false)
        let before = try BackupImportService(context: context).currentCounts()
        let document = try exportDocument(from: context)
        #expect(context.hasChanges == false)
        #expect(try BackupImportService(context: context).currentCounts() == before)
        #expect(document.counts.workspaces == 2)
    }

    // MARK: - Replace round trip

    @Test func replaceRestoresFullWorkspaceConfigurationAndUnknownModules() throws {
        let (document, fixture) = try makeConfiguredSource()
        let target = try PersistenceController.makeContainer(storage: .inMemory)
        let context = target.mainContext
        let oldTask = TodoTask(title: "旧任务", now: base)
        context.insert(oldTask)
        try context.save()

        let result = try apply(document, to: context, mode: .replace)
        #expect(result.mode == .replace)
        #expect(result.safetyBackupURL != nil)
        #expect(result.inserted == BackupCounts(document: document.backup))

        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 1)
        let task = try #require(try context.fetch(FetchDescriptor<TodoTask>()).first)
        #expect(task.id == fixture.taskID)
        #expect(task.title == "备份任务")
        #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<WorkspaceModule>())
                == DefaultWorkspaceFactory.globalSpecs.count + 5 + 1 + 1)
        #expect(try context.fetchCount(FetchDescriptor<SavedTaskView>()) == 1)

        let service = WorkspaceService(context: context)
        let workspaces = try service.allWorkspaces()
        #expect(workspaces.filter(\.isGlobal).count == 1)
        let global = try #require(workspaces.first { $0.isGlobal })
        #expect(global.id == fixture.globalID)
        #expect(global.accent == .ocean)
        let scenario = try #require(try service.fetchWorkspace(id: fixture.workspaceID))
        #expect(scenario.filter == TaskFilterExpression.activeOnly)
        #expect(scenario.orderedModules.count == 7)

        let taskList = try #require(scenario.orderedModules
            .first { $0.id == fixture.taskListModuleID })
        #expect(taskList.size == .large)
        #expect(taskList.scope == .custom)
        #expect(taskList.savedViewID == fixture.savedViewID)
        #expect(taskList.config == fixture.taskListConfig)
        #expect(taskList.config.filter == fixture.taskListConfig.filter)

        let unknown = try #require(scenario.orderedModules
            .first { $0.id == fixture.unknownModuleID })
        #expect(unknown.kindRaw == "futureWidget")
        #expect(unknown.sizeRaw == "galaxy")
        #expect(unknown.scopeRaw == "edge")
        #expect(unknown.configData == fixture.unknownConfig)

        let view = try #require(try SavedViewService(context: context)
            .fetch(fixture.savedViewID))
        #expect(view.filter == fixture.viewFilter)
        #expect(view.sort == .dueDate)
    }

    // MARK: - Version 1 compatibility

    @Test func versionOneJSONWithoutConfigurationImportsAndCreatesOneGlobalWorkspace() throws {
        let taskID = UUID()
        let json = """
        {
          "format": "com.yexiaonan.selno.backup",
          "schemaVersion": 1,
          "exportedAt": "2026-10-21T04:00:00.123Z",
          "appVersion": "0.9",
          "timeZone": "Asia/Shanghai",
          "data": {
            "tasks": [
              { "id": "\(taskID.uuidString)", "title": "旧版任务", "status": "pending" }
            ]
          },
          "unknownTopLevelKey": { "ignored": true }
        }
        """
        let backup = try BackupCodec.decode(Data(json.utf8))
        try BackupCodec.validate(backup)
        #expect(backup.data.workspaces.isEmpty)
        #expect(backup.data.savedViews.isEmpty)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        let context = target.mainContext
        let first = try apply(BackupDocument(backup: backup, fileName: "v1.json"),
                              to: context, mode: .merge)
        #expect(first.inserted.tasks == 1)
        #expect(first.inserted.workspaces == 0)
        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkspaceModule>())
                == DefaultWorkspaceFactory.globalSpecs.count)
        let global = try #require(try WorkspaceService(context: context).globalWorkspace())
        #expect(global.isGlobal)
        #expect(global.orderedModules.compactMap(\.kind)
                == DefaultWorkspaceFactory.globalSpecs.map(\.kind))

        // Re-importing the same v1 file is a no-op.
        let second = try apply(BackupDocument(backup: backup, fileName: "v1.json"),
                               to: context, mode: .merge)
        #expect(second.inserted.total == 0)
        #expect(second.skipped.tasks == 1)
        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkspaceModule>())
                == DefaultWorkspaceFactory.globalSpecs.count)
    }

    // MARK: - Merge semantics

    @Test func mergeIsIdempotentKeepsLocalConflictsAndNeverDuplicatesTheGlobal() throws {
        let localTaskID = UUID()
        let remoteOnlyTaskID = UUID()
        let localTask = TodoTask(id: localTaskID, title: "本地版本", now: base)
        localTask.dueAt = base.addingTimeInterval(3_600)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        let context = target.mainContext
        let global = try seed(context)
        context.insert(localTask)
        let localScenario = try WorkspaceService(context: context).createWorkspace(
            name: "本地场景", emoji: "🏠", accent: .sage,
            filter: .unrestricted, preset: .blank, now: base
        )
        try context.save()

        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let sourceContext = source.mainContext
        _ = try seed(sourceContext)
        let sourceService = WorkspaceService(context: sourceContext)
        let remoteScenario = try sourceService.createWorkspace(
            name: "远端场景", emoji: "🛰", accent: .slate,
            filter: TaskFilterExpression(statuses: [TaskStatus.completed.rawValue]),
            preset: .development, now: base
        )
        let duplicate = TodoTask(id: localTaskID, title: "远端版本", now: base)
        let unique = TodoTask(id: remoteOnlyTaskID, title: "远端新增", now: base)
        sourceContext.insert(duplicate)
        sourceContext.insert(unique)
        try sourceContext.save()
        let document = try exportDocument(from: sourceContext)
        #expect(document.backup.data.workspaces.count == 2)

        let first = try apply(document, to: context, mode: .merge)
        #expect(first.inserted.tasks == 1)
        #expect(first.inserted.workspaces == 1) // remote global is skipped
        #expect(first.skipped.workspaces >= 1)

        #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 3)
        let workspaces = try WorkspaceService(context: context).allWorkspaces()
        #expect(workspaces.filter(\.isGlobal).count == 1)
        #expect(workspaces.first(where: \.isGlobal)?.id == global.id)
        #expect(Set(workspaces.map(\.name)) == ["全局工作台", "本地场景", "远端场景"])
        let imported = try #require(workspaces.first { $0.id == remoteScenario.id })
        #expect(imported.filter == TaskFilterExpression(
            statuses: [TaskStatus.completed.rawValue]
        ))
        #expect(imported.orderedModules.count
                == DefaultWorkspaceFactory.specs(for: .development).count)

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        #expect(tasks.count == 2)
        let local = try #require(tasks.first { $0.id == localTaskID })
        #expect(local.title == "本地版本", "合并必须保留本地冲突记录")
        #expect(local.dueAt == base.addingTimeInterval(3_600))
        let added = try #require(tasks.first { $0.id == remoteOnlyTaskID })
        #expect(added.title == "远端新增")
        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 2)
        #expect(localScenario.orderedModules.isEmpty)

        let counts = try BackupImportService(context: context).currentCounts()
        let second = try apply(document, to: context, mode: .merge)
        #expect(second.inserted.total == 0)
        #expect(try BackupImportService(context: context).currentCounts() == counts)
        #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 3)
    }

    @Test func mergeKeepsModulesAttachedWhenALocalSavedViewWinsTheUUIDConflict() throws {
        let viewID = UUID()
        let local = try PersistenceController.makeContainer(storage: .inMemory)
        let localContext = local.mainContext
        _ = try seed(localContext)
        let localView = SavedTaskView(id: viewID, name: "本地视图", emoji: "🏠",
                                      colorHex: "#4F7A69", filter: .activeOnly,
                                      sort: .standard, limit: 8, now: base)
        localContext.insert(localView)
        try localContext.save()

        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let sourceContext = source.mainContext
        let sourceService = WorkspaceService(context: sourceContext)
        let remoteView = SavedTaskView(id: viewID, name: "远端视图", emoji: "🛰",
                                       colorHex: "#A33E3C",
                                       filter: TaskFilterExpression(
                                           statuses: [TaskStatus.completed.rawValue]
                                       ),
                                       sort: .dueDate, limit: 20, now: base)
        sourceContext.insert(remoteView)
        try sourceContext.save()
        let workspace = try sourceService.createWorkspace(
            name: "引用视图", emoji: "🔗", accent: .ocean,
            filter: .unrestricted, preset: .blank, now: base
        )
        let module = try sourceService.addModule(to: workspace.id, kind: .taskList,
                                                 size: .large, now: base)
        try sourceService.updateModule(id: module.id, size: .large, scope: .custom,
                                       savedViewID: viewID,
                                       config: WorkspaceModuleConfig(filter: .activeOnly),
                                       now: base)
        let document = try exportDocument(from: sourceContext)

        _ = try apply(document, to: localContext, mode: .merge)
        #expect(try localContext.fetchCount(FetchDescriptor<SavedTaskView>()) == 1)
        let keptView = try #require(try SavedViewService(context: localContext).fetch(viewID))
        #expect(keptView.name == "本地视图")
        #expect(keptView.filter == .activeOnly)

        let imported = try #require(try WorkspaceService(context: localContext)
            .allWorkspaces().first { $0.id == workspace.id })
        let importedModule = try #require(imported.orderedModules.first)
        #expect(importedModule.savedViewID == viewID)
        #expect(importedModule.scope == .custom)
        try BackupCodec.validate(document.backup)
    }

    // MARK: - Safety backup and rollback

    @Test func replaceWritesRestorableSafetyBackupAndRollsBackInjectedFailures() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase05Safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backups = root.appendingPathComponent("Backups", isDirectory: true)

        let (document, fixture) = try makeConfiguredSource()
        let target = try PersistenceController.makeContainer(storage: .inMemory)
        let context = target.mainContext
        _ = try seed(context)
        let oldTask = TodoTask(title: "旧任务", now: base)
        context.insert(oldTask)
        let oldScenario = try WorkspaceService(context: context).createWorkspace(
            name: "旧场景", emoji: "🗄", accent: .rose,
            filter: .unrestricted, preset: .life, now: base
        )
        try context.save()
        let oldScenarioID = oldScenario.id

        let first = try apply(document, to: context, mode: .replace, directory: backups)
        let safetyURL = try #require(first.safetyBackupURL)
        #expect(FileManager.default.fileExists(atPath: safetyURL.path))
        let safetyData = try BackupFileIO.read(from: safetyURL)
        let safety = try BackupCodec.decode(safetyData)
        try BackupCodec.validate(safety)
        #expect(safety.data.tasks.contains { $0.title == "旧任务" })
        #expect(safety.data.workspaces.contains { $0.id == oldScenarioID })
        #expect(safety.data.workspaces.contains { $0.isGlobal })
        #expect(safety.schemaVersion == 2)

        // The successful replace removed the old state and installed the source.
        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 1)
        #expect(try context.fetch(FetchDescriptor<TodoTask>()).first?.title == "备份任务")
        #expect(try WorkspaceService(context: context).fetchWorkspace(id: oldScenarioID) == nil)

        // A failure between mutation and save must restore the exact previous
        // content, including the restored workspace layout.
        let sentinel = TodoTask(title: "回滚哨兵", now: base)
        context.insert(sentinel)
        try context.save()
        let before = try BackupImportService(context: context).currentCounts()
        let beforeWorkspaces = try WorkspaceService(context: context).allWorkspaces()
        let beforeModules = beforeWorkspaces.map { ($0.id, $0.orderedModules.map(\.id)) }
        let beforeTasks = Set(try context.fetch(FetchDescriptor<TodoTask>()).map(\.title))

        #expect(throws: BackupError.self) {
            try apply(document, to: context, mode: .replace, directory: backups,
                      beforeSave: { _ in throw InjectedFailure() })
        }
        #expect(try BackupImportService(context: context).currentCounts() == before)
        let afterWorkspaces = try WorkspaceService(context: context).allWorkspaces()
        #expect(afterWorkspaces.map(\.id) == beforeWorkspaces.map(\.id))
        #expect(afterWorkspaces.map { $0.orderedModules.map(\.id) } == beforeModules.map(\.1))
        #expect(Set(try context.fetch(FetchDescriptor<TodoTask>()).map(\.title)) == beforeTasks)
        #expect(try context.fetch(FetchDescriptor<TodoTask>()).contains { $0.id == sentinel.id })
        #expect(try WorkspaceService(context: context).fetchWorkspace(id: fixture.workspaceID) != nil)
    }

    // MARK: - Validation and revalidation

    @Test func invalidConfigurationReferencesAreRejectedBeforeImport() throws {
        let (document, fixture) = try makeConfiguredSource()
        let good = document.backup
        try BackupCodec.validate(good)

        var missingView = good
        let workspaceIndex = try #require(missingView.data.workspaces.firstIndex {
            $0.id == fixture.workspaceID
        })
        let moduleIndex = try #require(missingView.data.workspaces[workspaceIndex].modules
            .firstIndex { $0.id == fixture.taskListModuleID })
        missingView.data.workspaces[workspaceIndex].modules[moduleIndex].savedViewID = UUID()
        #expect(throws: BackupError.self) { try BackupCodec.validate(missingView) }

        var duplicateModule = good
        let moduleID = duplicateModule.data.workspaces[0].modules[0].id
        duplicateModule.data.workspaces[1].modules[0].id = moduleID
        #expect(throws: BackupError.self) { try BackupCodec.validate(duplicateModule) }

        var twoGlobals = good
        twoGlobals.data.workspaces[1].isGlobal = true
        #expect(throws: BackupError.self) { try BackupCodec.validate(twoGlobals) }

        var tooManyWorkspaces = good
        let workspaceTemplate = tooManyWorkspaces.data.workspaces[1]
        tooManyWorkspaces.data.workspaces = (0..<25).map { index in
            var workspace = workspaceTemplate
            workspace.id = UUID()
            workspace.name = "场景 \(index)"
            workspace.isGlobal = false
            workspace.modules = []
            return workspace
        }
        #expect(throws: BackupError.self) { try BackupCodec.validate(tooManyWorkspaces) }

        var tooManyModules = good
        let moduleTemplate = tooManyModules.data.workspaces[1].modules[0]
        tooManyModules.data.workspaces[1].modules = (0..<49).map { index in
            var module = moduleTemplate
            module.id = UUID()
            module.sortOrder = index
            return module
        }
        #expect(throws: BackupError.self) { try BackupCodec.validate(tooManyModules) }

        var emptyKind = good
        emptyKind.data.workspaces[1].modules[0].kind = "   "
        #expect(throws: BackupError.self) { try BackupCodec.validate(emptyKind) }

        var emptySize = good
        emptySize.data.workspaces[1].modules[0].size = ""
        #expect(throws: BackupError.self) { try BackupCodec.validate(emptySize) }

        var badColor = good
        badColor.data.savedViews[0].colorHex = "red"
        #expect(throws: BackupError.self) { try BackupCodec.validate(badColor) }

        var duplicateView = good
        let repeatedView = duplicateView.data.savedViews[0]
        duplicateView.data.savedViews.append(repeatedView)
        #expect(throws: BackupError.self) { try BackupCodec.validate(duplicateView) }

        var reversedRange = good
        reversedRange.data.workspaces[1].filter = TaskFilterExpression(
            dateRange: .custom,
            customStart: base.addingTimeInterval(86_400),
            customEnd: base
        )
        #expect(throws: BackupError.self) { try BackupCodec.validate(reversedRange) }

        var future = good
        future.schemaVersion = 3
        #expect(throws: BackupError.unsupportedVersion(found: 3, supported: 2)) {
            try BackupCodec.validate(future)
        }
        let futureDocument = BackupDocument(backup: future, fileName: "future.json")
        let target = try PersistenceController.makeContainer(storage: .inMemory)
        let existing = TodoTask(title: "现有", now: base)
        target.mainContext.insert(existing)
        try target.mainContext.save()
        #expect(throws: BackupError.self) {
            try apply(futureDocument, to: target.mainContext, mode: .replace)
        }
        #expect(try target.mainContext.fetch(FetchDescriptor<TodoTask>()).map(\.id) == [existing.id])
    }

    @Test func malformedElementsAndReferencesAreRejectedInsteadOfBecomingEmpty() throws {
        let (document, _) = try makeConfiguredSource()
        let encoded = try BackupCodec.encode(document.backup)

        func malformed(_ mutate: (inout [[String: Any]]) -> Void) throws -> Data {
            var root = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            var data = try #require(root["data"] as? [String: Any])
            var tasks = try #require(data["tasks"] as? [[String: Any]])
            mutate(&tasks)
            data["tasks"] = tasks
            root["data"] = data
            return try JSONSerialization.data(withJSONObject: root)
        }

        // One bad task must invalidate the document. Treating the whole array as
        // [] would let a replace import delete local data and import nothing.
        let badID = try malformed { $0[0]["id"] = "not-a-uuid" }
        #expect(throws: BackupError.self) { _ = try BackupCodec.decode(badID) }

        // A present-but-malformed reference must not silently become "unassigned".
        let badReference = try malformed { $0[0]["projectID"] = 123 }
        #expect(throws: BackupError.self) { _ = try BackupCodec.decode(badReference) }

        let badDate = try malformed { $0[0]["dueAt"] = "yesterday" }
        #expect(throws: BackupError.self) { _ = try BackupCodec.decode(badDate) }
    }

    @Test func restoreRepairsKnownModuleConfigurationButPreservesUnknownModules() throws {
        let (document, fixture) = try makeConfiguredSource()
        var backup = document.backup
        let globalIndex = try #require(backup.data.workspaces.firstIndex { $0.isGlobal })
        let scenarioIndex = try #require(backup.data.workspaces.firstIndex {
            $0.id == fixture.workspaceID
        })
        let focusIndex = try #require(backup.data.workspaces[globalIndex].modules
            .firstIndex { $0.kind == WorkspaceModuleKind.focus.rawValue })
        backup.data.workspaces[globalIndex].modules[focusIndex].size = "huge"
        backup.data.workspaces[globalIndex].modules[focusIndex].scope = "futureScope"
        backup.data.workspaces[globalIndex].modules[focusIndex].config = WorkspaceModuleConfig(
            filter: TaskFilterExpression(statuses: [
                TaskStatus.pending.rawValue, "futureStatus"
            ]),
            days: 99, limit: 999, sortRaw: "futureSort"
        )
        // No saved view reference, so the module remains configurable.
        backup.data.workspaces[globalIndex].modules[focusIndex].savedViewID = nil
        // An unknown module with an unsupported size/scope must not be repaired.
        let unknownIndex = try #require(backup.data.workspaces[scenarioIndex].modules
            .firstIndex { $0.id == fixture.unknownModuleID })
        backup.data.workspaces[scenarioIndex].modules[unknownIndex].size = "galaxy"
        try BackupCodec.validate(backup)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        _ = try apply(BackupDocument(backup: backup, fileName: "repair.json"),
                      to: target.mainContext, mode: .replace)
        let context = target.mainContext
        let global = try #require(try WorkspaceService(context: context)
            .fetchWorkspace(id: fixture.globalID))
        let inbox = try #require(global.orderedModules
            .first { $0.kind == .focus })
        #expect(inbox.size == .large) // descriptor default for focus
        #expect(inbox.scope == .inherit)
        #expect(inbox.config.days == 3)
        #expect(inbox.config.limit == WorkspaceLimits.taskListLimitRange.upperBound)
        #expect(inbox.config.sort == .standard)
        #expect(inbox.config.filter?.statuses == [TaskStatus.pending.rawValue])

        let scenario = try #require(try WorkspaceService(context: context)
            .fetchWorkspace(id: fixture.workspaceID))
        let unknown = try #require(scenario.orderedModules
            .first { $0.id == fixture.unknownModuleID })
        #expect(unknown.kindRaw == "futureWidget")
        #expect(unknown.sizeRaw == "galaxy")
        #expect(unknown.scopeRaw == "edge")
        #expect(unknown.configData == fixture.unknownConfig)
    }
}