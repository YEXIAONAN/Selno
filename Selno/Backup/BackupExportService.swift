import Foundation
import SwiftData

struct BackupDocument {
    let backup: SelnoBackup
    let counts: BackupCounts
    let fileName: String
    let sourceURL: URL?
    let byteCount: Int?

    init(backup: SelnoBackup, fileName: String, sourceURL: URL? = nil, byteCount: Int? = nil) {
        self.backup = backup
        self.counts = BackupCounts(document: backup)
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.byteCount = byteCount
    }
}

@MainActor
struct BackupExportService {
    let context: ModelContext

    func makeDocument(now: Date = .now) throws -> BackupDocument {
        let backup = try makeBackup(now: now)
        return BackupDocument(backup: backup, fileName: Self.suggestedFileName(now: now))
    }

    /// Fetches every user-owned entity without inserting, updating or saving anything.
    /// Relationships are flattened into stable UUID references so the JSON survives a
    /// future store rebuild and can be merged record-by-record.
    func makeBackup(now: Date = .now) throws -> SelnoBackup {
        let projects = try context.fetch(FetchDescriptor<TodoProject>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let tags = try context.fetch(FetchDescriptor<TaskCategory>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let events = try context.fetch(FetchDescriptor<CalendarEvent>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let reminders = try context.fetch(FetchDescriptor<TaskReminder>())
            .filter { reminder in
                guard let taskID = reminder.taskID else { return false }
                return tasks.contains { $0.id == taskID }
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let workspaces = try context.fetch(FetchDescriptor<Workspace>())
            .sorted(by: Self.workspaceSort)
        let savedViews = try context.fetch(FetchDescriptor<SavedTaskView>())
            .sorted { $0.id.uuidString < $1.id.uuidString }

        return SelnoBackup(
            exportedAt: now,
            data: SelnoBackupData(
                projects: projects.map(Self.project),
                tags: tags.map(Self.tag),
                templates: templates.map(Self.template),
                tasks: tasks.map(Self.task),
                events: events.map(Self.event),
                reminders: reminders.compactMap(Self.reminder),
                workspaces: workspaces.map(Self.workspace),
                savedViews: savedViews.map(Self.savedView)
            )
        )
    }

    func encode(_ backup: SelnoBackup) throws -> Data {
        try BackupCodec.validate(backup)
        return try BackupCodec.encode(backup)
    }

    func write(_ backup: SelnoBackup, to url: URL) throws {
        let data = try encode(backup)
        try BackupFileIO.write(data, to: url)
    }

    static func suggestedFileName(now: Date = .now, prefix: String = "Selno-Backup") -> String {
        "\(prefix)-\(dayStamp(now)).json"
    }

    static func automaticBackupFileName(now: Date = .now) -> String {
        "\(prefixPreRestore)-\(timestamp(now)).json"
    }

    static let prefixPreRestore = "Selno-PreRestore"

    private static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    // MARK: Mapping

    private static func workspaceSort(_ lhs: Workspace, _ rhs: Workspace) -> Bool {
        if lhs.isGlobal != rhs.isGlobal { return lhs.isGlobal }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// The structured filter is preferred for readability. Raw bytes are added
    /// only when re-encoding would drop something this version does not know
    /// about, so an import through a newer Selno build stays lossless.
    private static func filterPayload(
        _ data: Data?
    ) -> (filter: TaskFilterExpression?, rawBase64: String?) {
        guard let data else { return (nil, nil) }
        guard let decoded = WorkspaceCoding.decode(TaskFilterExpression.self, from: data) else {
            return (nil, data.base64EncodedString())
        }
        if WorkspaceCoding.filterData(decoded) == data { return (decoded, nil) }
        return (decoded, data.base64EncodedString())
    }

    private static func workspace(_ value: Workspace) -> BackupWorkspace {
        let payload = filterPayload(value.filterData)
        return BackupWorkspace(
            id: value.id, name: value.name, emoji: value.emoji,
            accent: value.accentRaw, sortOrder: value.sortOrder,
            isGlobal: value.isGlobal, filter: payload.filter,
            filterRawBase64: payload.rawBase64,
            createdAt: value.createdAt, updatedAt: value.updatedAt,
            modules: value.orderedModules.map(Self.module)
        )
    }

    private static func module(_ value: WorkspaceModule) -> BackupWorkspaceModule {
        let decoded = value.configData.flatMap {
            WorkspaceCoding.decode(WorkspaceModuleConfig.self, from: $0)
        }
        let canonical = decoded.map { $0.sanitized().encoded() } ?? nil
        let rawBase64: String? = if let data = value.configData, canonical != data {
            data.base64EncodedString()
        } else {
            nil
        }
        return BackupWorkspaceModule(
            id: value.id, kind: value.kindRaw, size: value.sizeRaw,
            sortOrder: value.sortOrder, scope: value.scopeRaw,
            savedViewID: value.savedViewID, config: decoded,
            configRawBase64: rawBase64,
            createdAt: value.createdAt, updatedAt: value.updatedAt
        )
    }

    private static func savedView(_ value: SavedTaskView) -> BackupSavedView {
        let payload = filterPayload(value.filterData)
        return BackupSavedView(
            id: value.id, name: value.name, emoji: value.emoji,
            colorHex: value.colorHex, filter: payload.filter,
            filterRawBase64: payload.rawBase64, sortRaw: value.sortRaw,
            limit: value.limit, createdAt: value.createdAt, updatedAt: value.updatedAt
        )
    }

    private static func project(_ value: TodoProject) -> BackupProject {
        BackupProject(id: value.id, name: value.name, notes: value.notes,
                      createdAt: value.createdAt, updatedAt: value.updatedAt,
                      archivedAt: value.archivedAt)
    }

    private static func tag(_ value: TaskCategory) -> BackupTag {
        BackupTag(id: value.id, name: value.name, symbolName: value.symbolName,
                  colorHex: value.colorHex, sortOrder: value.sortOrder,
                  isArchived: value.isArchived, createdAt: value.createdAt, emoji: value.emoji)
    }

    private static func template(_ value: TaskTemplate) -> BackupTemplate {
        let definition = value.definition
        let supported = definition.map { $0.version == 1 && $0.fields.allSatisfy(\.isSupported) } ?? false
        let raw: String? = supported ? nil : value.definitionData?.base64EncodedString()
        return BackupTemplate(id: value.id, name: value.name, emoji: value.emoji,
                              revision: value.revision, createdAt: value.createdAt,
                              updatedAt: value.updatedAt, definition: definition,
                              definitionRawBase64: raw)
    }

    private static func task(_ value: TodoTask) -> BackupTask {
        var seen = Set<UUID>()
        let tagIDs = (value.tags ?? []).map(\.id).filter { seen.insert($0).inserted }
        let instance: BackupTemplateInstance? = value.templateInstance.map { source in
            let payload = source.payload
            let supported = payload?.isEditable ?? false
            return BackupTemplateInstance(
                id: source.id, templateID: source.templateID,
                templateName: source.templateName, templateRevision: source.templateRevision,
                payload: payload,
                payloadRawBase64: supported ? nil : source.payloadData?.base64EncodedString()
            )
        }
        return BackupTask(
            id: value.id, title: value.title, notes: value.notes,
            status: value.statusRaw, importance: value.importanceRaw,
            createdAt: value.createdAt, updatedAt: value.updatedAt,
            completedAt: value.completedAt, plannedStartAt: value.plannedStartAt,
            plannedAt: value.plannedAt, dueAt: value.dueAt, archivedAt: value.archivedAt,
            projectID: value.project?.id, categoryID: value.category?.id,
            tagIDs: tagIDs,
            steps: value.orderedSteps.map {
                BackupStep(id: $0.id, title: $0.title, isCompleted: $0.isCompleted,
                           sortOrder: $0.sortOrder, createdAt: $0.createdAt,
                           completedAt: $0.completedAt)
            },
            templateInstance: instance,
            milestones: (value.milestones ?? [])
                .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
                .map {
                    BackupMilestone(id: $0.id, fieldID: $0.fieldID, title: $0.title,
                                    semantic: $0.semanticRaw, date: $0.date,
                                    isOnCalendar: $0.isOnCalendar,
                                    reminderLeadMinutes: $0.reminderLeadMinutes)
                }
        )
    }

    private static func event(_ value: CalendarEvent) -> BackupEvent {
        BackupEvent(id: value.id, title: value.title, notes: value.notes,
                    startsAt: value.startsAt, endsAt: value.endsAt,
                    isAllDay: value.isAllDay, location: value.location,
                    createdAt: value.createdAt, updatedAt: value.updatedAt)
    }

    private static func reminder(_ value: TaskReminder) -> BackupTaskReminder? {
        guard let taskID = value.taskID else { return nil }
        return BackupTaskReminder(id: value.id, taskID: taskID, kind: value.kindRaw,
                                  leadMinutes: value.leadMinutes,
                                  scheduledAt: value.scheduledAt,
                                  createdAt: value.createdAt, updatedAt: value.updatedAt)
    }
}

nonisolated enum BackupFileIO {
    static let maximumByteCount = 128 * 1024 * 1024

    static func read(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == false {
                throw BackupError.unreadableFile("这是一个文件夹或特殊文件。")
            }
            if let size = values.fileSize, size > maximumByteCount {
                throw BackupError.fileTooLarge(size, maximumByteCount)
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= maximumByteCount else {
                throw BackupError.fileTooLarge(data.count, maximumByteCount)
            }
            return data
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.unreadableFile(error.localizedDescription)
        }
    }

    static func write(_ data: Data, to url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            throw BackupError.ioFailure(error.localizedDescription)
        }
    }

    static func uniqueURL(in directory: URL, fileName: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}