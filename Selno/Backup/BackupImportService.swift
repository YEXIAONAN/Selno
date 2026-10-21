import Foundation
import SwiftData

enum BackupImportMode: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: "合并导入"
        case .replace: "替换恢复"
        }
    }

    var explanation: String {
        switch self {
        case .merge:
            "按稳定标识匹配。已存在的记录与工作台配置保持本地内容不变，只补充备份中新增的记录；重复导入同一文件不会产生重复数据。"
        case .replace:
            "先自动备份当前数据，再用文件内容替换全部任务、日程、项目、标签、模板、提醒、工作台布局与任务视图。此模式不做逐条合并。"
        }
    }
}

struct BackupImportPreview: Identifiable {
    let id = UUID()
    let document: BackupDocument
    let existingCounts: BackupCounts
    let mergeInserted: BackupCounts
    let mergeSkipped: BackupCounts
}

struct BackupImportResult {
    let mode: BackupImportMode
    let inserted: BackupCounts
    let skipped: BackupCounts
    let safetyBackupURL: URL?
}

@MainActor
struct BackupImportService {
    let context: ModelContext
    /// Overridable in tests; the app uses Application Support/Selno/Backups.
    var backupDirectory: URL? = nil

    func makePreview(document: BackupDocument) throws -> BackupImportPreview {
        let index = try ExistingIndex.load(from: context)
        let plan = Self.mergePlan(for: document.backup.data, existing: index)
        return BackupImportPreview(
            document: document,
            existingCounts: try currentCounts(),
            mergeInserted: plan.insertedCounts,
            mergeSkipped: plan.skipped
        )
    }

    func currentCounts() throws -> BackupCounts {
        BackupCounts(
            projects: try context.fetchCount(FetchDescriptor<TodoProject>()),
            tags: try context.fetchCount(FetchDescriptor<TaskCategory>()),
            templates: try context.fetchCount(FetchDescriptor<TaskTemplate>()),
            tasks: try context.fetchCount(FetchDescriptor<TodoTask>()),
            steps: try context.fetchCount(FetchDescriptor<TaskStep>()),
            templateInstances: try context.fetchCount(FetchDescriptor<TaskTemplateInstance>()),
            milestones: try context.fetchCount(FetchDescriptor<TaskMilestone>()),
            events: try context.fetchCount(FetchDescriptor<CalendarEvent>()),
            reminders: try context.fetchCount(FetchDescriptor<TaskReminder>()),
            workspaces: try context.fetchCount(FetchDescriptor<Workspace>()),
            modules: try context.fetchCount(FetchDescriptor<WorkspaceModule>()),
            savedViews: try context.fetchCount(FetchDescriptor<SavedTaskView>())
        )
    }

    /// Applies a previously decoded and validated document.
    /// `beforeSave` exists so tests can simulate a failure after all mutations but before
    /// the single transactional save; any error rolls the context back.
    func apply(
        document: BackupDocument,
        mode: BackupImportMode,
        now: Date = .now,
        beforeSave: ((ModelContext) throws -> Void)? = nil
    ) throws -> BackupImportResult {
        // Re-validate defensively: callers may hand us a document built in memory.
        try BackupCodec.validate(document.backup)

        switch mode {
        case .merge:
            return try applyMerge(document, now: now, beforeSave: beforeSave)
        case .replace:
            return try applyReplace(document, now: now, beforeSave: beforeSave)
        }
    }

    // MARK: Merge

    private func applyMerge(
        _ document: BackupDocument,
        now: Date,
        beforeSave: ((ModelContext) throws -> Void)?
    ) throws -> BackupImportResult {
        let index = try ExistingIndex.load(from: context)
        let plan = Self.mergePlan(for: document.backup.data, existing: index)
        let existingWorkspaces = try context.fetchCount(FetchDescriptor<Workspace>())
        let existingGlobal = try context.fetchCount(FetchDescriptor<Workspace>(
            predicate: #Predicate { $0.isGlobal }
        )) > 0
        let needsSeededGlobal = !existingGlobal && !plan.workspaces.contains(where: \.isGlobal)
        let workspaceBudget = WorkspaceLimits.maximumWorkspaces - (needsSeededGlobal ? 1 : 0)
        guard existingWorkspaces + plan.workspaces.count <= workspaceBudget else {
            throw BackupError.invalidData(
                "合并后工作台将超过 \(WorkspaceLimits.maximumWorkspaces) 个；请先删除部分场景再导入。"
            )
        }

        do {
            var projects = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TodoProject>()).map { ($0.id, $0) })
            var tags = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskCategory>()).map { ($0.id, $0) })
            insertProjects(plan.projects, into: &projects)
            insertTags(plan.tags, into: &tags)
            try insertTemplates(plan.templates)
            insertTasks(plan.tasks, projects: projects, tags: tags)
            insertEvents(plan.events)
            insertReminders(plan.reminders)
            insertSavedViews(plan.savedViews)
            insertWorkspaces(plan.workspaces)
            // A version 1 backup, or a version 2 file from a build without a
            // global workspace, still leaves the user with the required global
            // board. Business rows are untouched by this step.
            try WorkspaceSeeder.insertDefaultGlobalIfNeeded(in: context, now: now)
            try WorkspaceSanitizer.normalize(in: context, now: now)
            try beforeSave?(context)
            try context.save()
        } catch let error as BackupError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw BackupError.importFailed(error.localizedDescription)
        }

        return BackupImportResult(mode: .merge, inserted: plan.insertedCounts,
                                  skipped: plan.skipped, safetyBackupURL: nil)
    }

    // MARK: Replace

    private func applyReplace(
        _ document: BackupDocument,
        now: Date,
        beforeSave: ((ModelContext) throws -> Void)?
    ) throws -> BackupImportResult {
        // A logical backup is written and flushed before any deletion. If this step
        // fails, the replacement never starts.
        let safetyURL = try writeSafetyBackup(now: now)
        let data = document.backup.data

        do {
            try deleteAllUserData()
            var projects: [UUID: TodoProject] = [:]
            var tags: [UUID: TaskCategory] = [:]
            insertProjects(data.projects, into: &projects)
            insertTags(data.tags, into: &tags)
            try insertTemplates(data.templates)
            insertTasks(data.tasks, projects: projects, tags: tags)
            insertEvents(data.events)
            insertReminders(data.reminders)
            insertSavedViews(data.savedViews)
            insertWorkspaces(data.workspaces)
            try WorkspaceSeeder.insertDefaultGlobalIfNeeded(in: context, now: now)
            try WorkspaceSanitizer.normalize(in: context, now: now)
            try beforeSave?(context)
            try context.save()
        } catch let error as BackupError {
            context.rollback()
            throw BackupError.importFailed(error.localizedDescription)
        } catch {
            context.rollback()
            throw BackupError.importFailed(error.localizedDescription)
        }

        let inserted = BackupCounts(document: document.backup)
        return BackupImportResult(mode: .replace, inserted: inserted,
                                  skipped: .zero, safetyBackupURL: safetyURL)
    }

    private func writeSafetyBackup(now: Date) throws -> URL {
        let export = BackupExportService(context: context)
        let backup = try export.makeBackup(now: now)
        let data = try BackupCodec.encode(backup)
        let directory = try backupDirectory ?? PersistenceController.automaticBackupDirectoryURL()
        let url = try BackupFileIO.uniqueURL(
            in: directory,
            fileName: BackupExportService.automaticBackupFileName(now: now)
        )
        try BackupFileIO.write(data, to: url)
        return url
    }

    private func deleteAllUserData() throws {
        // Delete every entity explicitly. Rows are removed in dependency order so a
        // replace cannot strand children even if an older store contains orphans.
        for value in try context.fetch(FetchDescriptor<TaskReminder>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<TaskStep>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<TaskMilestone>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<TaskTemplateInstance>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<TodoTask>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<CalendarEvent>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<TaskTemplate>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<TaskCategory>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<TodoProject>()) { context.delete(value) }
        // Configuration rows are removed last so a failed restore can still be
        // rolled back to the exact previous layout.
        for value in try context.fetch(FetchDescriptor<WorkspaceModule>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<Workspace>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<SavedTaskView>()) { context.delete(value) }
    }

    // MARK: Insertion

    private func insertProjects(_ values: [BackupProject], into map: inout [UUID: TodoProject]) {
        for value in values {
            let model = TodoProject(id: value.id, name: value.name, notes: value.notes, now: value.createdAt)
            model.updatedAt = value.updatedAt
            model.archivedAt = value.archivedAt
            context.insert(model)
            map[value.id] = model
        }
    }

    private func insertTags(_ values: [BackupTag], into map: inout [UUID: TaskCategory]) {
        for value in values {
            let model = TaskCategory(id: value.id, name: value.name, symbolName: value.symbolName,
                                     colorHex: value.colorHex, sortOrder: value.sortOrder, now: value.createdAt)
            model.isArchived = value.isArchived
            model.emoji = value.emoji
            context.insert(model)
            map[value.id] = model
        }
    }

    private func insertTemplates(_ values: [BackupTemplate]) throws {
        for value in values {
            let model = TaskTemplate(name: value.name, emoji: value.emoji, definition: value.definition ?? .init())
            model.id = value.id
            model.revision = value.revision
            model.createdAt = value.createdAt
            model.updatedAt = value.updatedAt
            model.definitionData = try resolvedDefinitionData(value)
            context.insert(model)
        }
    }

    private func insertTasks(_ values: [BackupTask], projects: [UUID: TodoProject], tags: [UUID: TaskCategory]) {
        for value in values {
            let task = TodoTask(
                id: value.id, title: value.title, notes: value.notes,
                status: TaskStatus(rawValue: value.status) ?? .pending,
                importance: TaskImportance(rawValue: value.importance) ?? .normal,
                now: value.createdAt
            )
            task.updatedAt = value.updatedAt
            task.completedAt = value.completedAt
            task.plannedStartAt = value.plannedStartAt
            task.plannedAt = value.plannedAt
            task.dueAt = value.dueAt
            task.archivedAt = value.archivedAt
            task.project = value.projectID.flatMap { projects[$0] }
            task.category = value.categoryID.flatMap { tags[$0] }
            var tagModels = value.tagIDs.compactMap { tags[$0] }
            if let category = task.category, !tagModels.contains(where: { $0.id == category.id }) {
                tagModels.append(category)
            }
            task.tags = tagModels
            context.insert(task)

            for stepValue in value.steps {
                let step = TaskStep(id: stepValue.id, title: stepValue.title,
                                    sortOrder: stepValue.sortOrder, now: stepValue.createdAt)
                step.isCompleted = stepValue.isCompleted
                step.completedAt = stepValue.completedAt
                context.insert(step)
                step.parentTask = task
            }

            if let instanceValue = value.templateInstance {
                let instance = TaskTemplateInstance(
                    id: instanceValue.id, templateID: instanceValue.templateID,
                    name: instanceValue.templateName, revision: instanceValue.templateRevision,
                    payloadData: Self.resolvedPayloadData(instanceValue)
                )
                context.insert(instance)
                task.templateInstance = instance
            }

            for milestoneValue in value.milestones {
                let milestone = TaskMilestone(fieldID: milestoneValue.fieldID,
                                              title: milestoneValue.title,
                                              semantic: milestoneValue.semantic,
                                              date: milestoneValue.date)
                milestone.id = milestoneValue.id
                milestone.isOnCalendar = milestoneValue.isOnCalendar
                milestone.reminderLeadMinutes = milestoneValue.reminderLeadMinutes
                milestone.reminderStateRaw = TaskReminderState.pending.rawValue
                context.insert(milestone)
                milestone.task = task
            }
        }
    }

    private func insertEvents(_ values: [BackupEvent]) {
        for value in values {
            let model = CalendarEvent(id: value.id, title: value.title, notes: value.notes,
                                      startsAt: value.startsAt, endsAt: value.endsAt,
                                      isAllDay: value.isAllDay, location: value.location,
                                      now: value.createdAt)
            model.updatedAt = value.updatedAt
            context.insert(model)
        }
    }

    private func insertReminders(_ values: [BackupTaskReminder]) {
        for value in values {
            let model = TaskReminder(
                id: value.id, taskID: value.taskID,
                kind: TaskReminderKind(rawValue: value.kind) ?? .due,
                leadMinutes: value.leadMinutes,
                scheduledAt: value.scheduledAt,
                now: value.createdAt
            )
            model.updatedAt = value.updatedAt
            model.stateRaw = TaskReminderState.pending.rawValue
            context.insert(model)
        }
    }

    private func insertSavedViews(_ values: [BackupSavedView]) {
        for value in values {
            let model = SavedTaskView(
                id: value.id,
                name: value.name.trimmingCharacters(in: .whitespacesAndNewlines),
                emoji: Self.normalizedEmoji(value.emoji, fallback: "🔎"),
                colorHex: Self.normalizedColor(value.colorHex),
                filter: value.filter ?? .unrestricted,
                sort: TaskSortMode(rawValue: value.sortRaw) ?? .standard,
                limit: min(max(value.limit, 1), WorkspaceLimits.taskListLimitRange.upperBound),
                now: value.createdAt
            )
            // Raw bytes win when present so fields introduced by a newer build
            // are not discarded by this build's typed representation.
            model.filterData = Self.resolvedFilterData(filter: value.filter,
                                                       rawBase64: value.filterRawBase64)
            model.createdAt = value.createdAt
            model.updatedAt = value.updatedAt
            context.insert(model)
        }
    }

    private func insertWorkspaces(_ values: [BackupWorkspace]) {
        for value in values {
            let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let workspace = Workspace(
                id: value.id,
                name: name,
                emoji: Self.normalizedEmoji(value.emoji,
                                            fallback: value.isGlobal
                                                ? DefaultWorkspaceFactory.globalEmoji : "🗂"),
                accent: WorkspaceAccent(rawValue: value.accent) ?? .sage,
                sortOrder: value.sortOrder,
                isGlobal: value.isGlobal,
                filter: value.filter ?? .unrestricted,
                now: value.createdAt
            )
            // Keep an unrecognized accent string until the sanitizer repairs it.
            workspace.accentRaw = value.accent
            workspace.filterData = Self.resolvedFilterData(filter: value.filter,
                                                           rawBase64: value.filterRawBase64)
            workspace.createdAt = value.createdAt
            workspace.updatedAt = value.updatedAt
            context.insert(workspace)

            for moduleValue in value.modules {
                let module = WorkspaceModule(
                    id: moduleValue.id,
                    kindRaw: moduleValue.kind,
                    sizeRaw: moduleValue.size,
                    sortOrder: moduleValue.sortOrder,
                    scopeRaw: moduleValue.scope,
                    savedViewID: moduleValue.savedViewID,
                    configData: Self.resolvedConfigData(moduleValue),
                    now: moduleValue.createdAt
                )
                module.createdAt = moduleValue.createdAt
                module.updatedAt = moduleValue.updatedAt
                context.insert(module)
                module.workspace = workspace
            }
        }
    }

    private static func resolvedFilterData(
        filter: TaskFilterExpression?,
        rawBase64: String?
    ) -> Data? {
        if let rawBase64, let data = Data(base64Encoded: rawBase64) { return data }
        return WorkspaceCoding.filterData(filter ?? .unrestricted)
    }

    private static func resolvedConfigData(_ value: BackupWorkspaceModule) -> Data? {
        if let rawBase64 = value.configRawBase64, let data = Data(base64Encoded: rawBase64) {
            return data
        }
        return value.config?.sanitized().encoded()
    }

    private static func normalizedColor(_ raw: String) -> String {
        let hex = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return "#4F7A69" }
        return "#\(hex)"
    }

    private static func normalizedEmoji(_ raw: String, fallback: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return fallback }
        return String(value.prefix(WorkspaceLimits.maximumEmojiLength))
    }

    private func resolvedDefinitionData(_ value: BackupTemplate) throws -> Data? {
        let supported = value.definition.map { $0.version == 1 && $0.fields.allSatisfy(\.isSupported) } ?? false
        if !supported, let raw = value.definitionRawBase64, let data = Data(base64Encoded: raw) {
            return data
        }
        if let definition = value.definition {
            return try TemplateCodec.encode(definition)
        }
        if let raw = value.definitionRawBase64 {
            return Data(base64Encoded: raw)
        }
        return nil
    }

    private static func resolvedPayloadData(_ value: BackupTemplateInstance) -> Data? {
        let supported = value.payload?.isEditable ?? false
        if !supported, let raw = value.payloadRawBase64, let data = Data(base64Encoded: raw) {
            return data
        }
        if let payload = value.payload, let data = try? TemplateCodec.encode(payload) {
            return data
        }
        if let raw = value.payloadRawBase64 {
            return Data(base64Encoded: raw)
        }
        return nil
    }

    // MARK: Merge planning

    private struct ExistingIndex {
        var projects: Set<UUID> = []
        var tags: Set<UUID> = []
        var templates: Set<UUID> = []
        var tasks: Set<UUID> = []
        var steps: Set<UUID> = []
        var instances: Set<UUID> = []
        var milestones: Set<UUID> = []
        var events: Set<UUID> = []
        var reminders: Set<UUID> = []
        var reminderKinds: Set<String> = []
        var workspaces: Set<UUID> = []
        var modules: Set<UUID> = []
        var savedViews: Set<UUID> = []
        var hasGlobalWorkspace = false

        static func load(from context: ModelContext) throws -> ExistingIndex {
            var index = ExistingIndex()
            index.projects = Set(try context.fetch(FetchDescriptor<TodoProject>()).map(\.id))
            index.tags = Set(try context.fetch(FetchDescriptor<TaskCategory>()).map(\.id))
            index.templates = Set(try context.fetch(FetchDescriptor<TaskTemplate>()).map(\.id))
            index.tasks = Set(try context.fetch(FetchDescriptor<TodoTask>()).map(\.id))
            index.steps = Set(try context.fetch(FetchDescriptor<TaskStep>()).map(\.id))
            index.instances = Set(try context.fetch(FetchDescriptor<TaskTemplateInstance>()).map(\.id))
            index.milestones = Set(try context.fetch(FetchDescriptor<TaskMilestone>()).map(\.id))
            index.events = Set(try context.fetch(FetchDescriptor<CalendarEvent>()).map(\.id))
            let reminders = try context.fetch(FetchDescriptor<TaskReminder>())
            index.reminders = Set(reminders.map(\.id))
            index.reminderKinds = Set(reminders.compactMap { reminder in
                reminder.taskID.map { "\($0.uuidString)|\(reminder.kindRaw)" }
            })
            let workspaces = try context.fetch(FetchDescriptor<Workspace>())
            index.workspaces = Set(workspaces.map(\.id))
            index.hasGlobalWorkspace = workspaces.contains(where: \.isGlobal)
            index.modules = Set(try context.fetch(FetchDescriptor<WorkspaceModule>()).map(\.id))
            index.savedViews = Set(try context.fetch(FetchDescriptor<SavedTaskView>()).map(\.id))
            return index
        }
    }

    private struct MergePlan {
        var projects: [BackupProject] = []
        var tags: [BackupTag] = []
        var templates: [BackupTemplate] = []
        var tasks: [BackupTask] = []
        var events: [BackupEvent] = []
        var reminders: [BackupTaskReminder] = []
        var workspaces: [BackupWorkspace] = []
        var savedViews: [BackupSavedView] = []
        var skipped = BackupCounts.zero
        /// IDs of backup tasks that are represented by a local row, so their embedded
        /// reminders must stay local as well.
        var skippedTaskIDs = Set<UUID>()

        var insertedCounts: BackupCounts {
            BackupCounts(
                projects: projects.count,
                tags: tags.count,
                templates: templates.count,
                tasks: tasks.count,
                steps: tasks.reduce(0) { $0 + $1.steps.count },
                templateInstances: tasks.reduce(0) { $0 + ($1.templateInstance == nil ? 0 : 1) },
                milestones: tasks.reduce(0) { $0 + $1.milestones.count },
                events: events.count,
                reminders: reminders.count,
                workspaces: workspaces.count,
                modules: workspaces.reduce(0) { $0 + $1.modules.count },
                savedViews: savedViews.count
            )
        }
    }

    private static func mergePlan(for data: SelnoBackupData, existing: ExistingIndex) -> MergePlan {
        var plan = MergePlan()
        plan.projects = data.projects.filter { !existing.projects.contains($0.id) }
        plan.skipped.projects = data.projects.count - plan.projects.count

        plan.tags = data.tags.filter { !existing.tags.contains($0.id) }
        plan.skipped.tags = data.tags.count - plan.tags.count

        plan.templates = data.templates.filter { !existing.templates.contains($0.id) }
        plan.skipped.templates = data.templates.count - plan.templates.count

        for task in data.tasks {
            let childConflict = task.steps.contains { existing.steps.contains($0.id) }
                || task.milestones.contains { existing.milestones.contains($0.id) }
                || (task.templateInstance.map { existing.instances.contains($0.id) } ?? false)
            if existing.tasks.contains(task.id) || childConflict {
                plan.skippedTaskIDs.insert(task.id)
                plan.skipped.tasks += 1
                plan.skipped.steps += task.steps.count
                plan.skipped.templateInstances += task.templateInstance == nil ? 0 : 1
                plan.skipped.milestones += task.milestones.count
            } else {
                plan.tasks.append(task)
            }
        }

        plan.events = data.events.filter { !existing.events.contains($0.id) }
        plan.skipped.events = data.events.count - plan.events.count

        var reminderKinds = existing.reminderKinds
        for reminder in data.reminders {
            let key = "\(reminder.taskID.uuidString)|\(reminder.kind)"
            if existing.reminders.contains(reminder.id)
                || plan.skippedTaskIDs.contains(reminder.taskID)
                || reminderKinds.contains(key) {
                plan.skipped.reminders += 1
            } else {
                plan.reminders.append(reminder)
                reminderKinds.insert(key)
            }
        }

        // Configuration merges by UUID exactly like business rows. A scenario
        // whose UUID already exists is left entirely alone, including its
        // modules. When the local store already owns a global workspace, an
        // incoming global workspace is skipped so there can never be two.
        plan.savedViews = data.savedViews.filter { !existing.savedViews.contains($0.id) }
        plan.skipped.savedViews = data.savedViews.count - plan.savedViews.count

        for workspace in data.workspaces {
            if existing.workspaces.contains(workspace.id)
                || (workspace.isGlobal && existing.hasGlobalWorkspace) {
                plan.skipped.workspaces += 1
                plan.skipped.modules += workspace.modules.count
                continue
            }
            var imported = workspace
            imported.modules = workspace.modules.filter { module in
                if existing.modules.contains(module.id) {
                    plan.skipped.modules += 1
                    return false
                }
                return true
            }
            plan.workspaces.append(imported)
        }
        return plan
    }
}