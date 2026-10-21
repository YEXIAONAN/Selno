import Foundation

// MARK: - Document

/// Versioned, human-readable JSON backup of every user-owned entity in Selno.
/// This is intentionally a plain Codable document rather than a database copy:
/// it survives store-format changes, can be inspected by a person, and never
/// contains sandbox credentials or system authorization state.
nonisolated struct SelnoBackup: Codable {
    static let formatIdentifier = "com.yexiaonan.selno.backup"
    /// Version 1 contained business rows only. Version 2 adds the workspace
    /// layout configuration and reusable saved task views. Both versions remain
    /// readable; a version 1 file simply imports without workspace rows.
    static let currentSchemaVersion = 2
    static let minimumSupportedSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var timeZone: String
    var data: SelnoBackupData

    init(
        exportedAt: Date = .now,
        appVersion: String = SelnoBackupMetadata.currentAppVersion,
        timeZone: String = TimeZone.current.identifier,
        data: SelnoBackupData
    ) {
        self.format = Self.formatIdentifier
        self.schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.timeZone = timeZone
        self.data = data
    }

    private enum CodingKeys: CodingKey { case format, schemaVersion, exportedAt, appVersion, timeZone, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? container.decode(String.self, forKey: .format)) ?? ""
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 0
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        appVersion = (try? container.decode(String.self, forKey: .appVersion)) ?? "unknown"
        timeZone = (try? container.decode(String.self, forKey: .timeZone)) ?? "UTC"
        data = try container.decode(SelnoBackupData.self, forKey: .data)
    }
}

nonisolated struct SelnoBackupData: Codable {
    var projects: [BackupProject] = []
    var tags: [BackupTag] = []
    var templates: [BackupTemplate] = []
    var tasks: [BackupTask] = []
    var events: [BackupEvent] = []
    var reminders: [BackupTaskReminder] = []
    /// Absent in version 1 files; decoding therefore yields an empty array.
    var workspaces: [BackupWorkspace] = []
    var savedViews: [BackupSavedView] = []

    private enum CodingKeys: CodingKey {
        case projects, tags, templates, tasks, events, reminders, workspaces, savedViews
    }

    init() {}

    init(
        projects: [BackupProject], tags: [BackupTag], templates: [BackupTemplate],
        tasks: [BackupTask], events: [BackupEvent], reminders: [BackupTaskReminder],
        workspaces: [BackupWorkspace] = [], savedViews: [BackupSavedView] = []
    ) {
        self.projects = projects
        self.tags = tags
        self.templates = templates
        self.tasks = tasks
        self.events = events
        self.reminders = reminders
        self.workspaces = workspaces
        self.savedViews = savedViews
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A missing key is valid in v1 files; a present-but-malformed element is
        // not. Silently turning the whole collection into [] here would let a
        // replace import erase local data because validation never saw the rows.
        projects = try container.decodeIfPresent([BackupProject].self, forKey: .projects) ?? []
        tags = try container.decodeIfPresent([BackupTag].self, forKey: .tags) ?? []
        templates = try container.decodeIfPresent([BackupTemplate].self, forKey: .templates) ?? []
        tasks = try container.decodeIfPresent([BackupTask].self, forKey: .tasks) ?? []
        events = try container.decodeIfPresent([BackupEvent].self, forKey: .events) ?? []
        reminders = try container.decodeIfPresent([BackupTaskReminder].self, forKey: .reminders) ?? []
        workspaces = try container.decodeIfPresent([BackupWorkspace].self, forKey: .workspaces) ?? []
        savedViews = try container.decodeIfPresent([BackupSavedView].self, forKey: .savedViews) ?? []
    }
}

// MARK: - Workspace configuration

nonisolated struct BackupWorkspaceModule: Codable {
    var id: UUID
    /// Raw strings are deliberate: a module type introduced by a newer Selno is
    /// restored unchanged and rendered as an inert placeholder here.
    var kind: String
    var size: String
    var sortOrder: Int
    var scope: String
    var savedViewID: UUID?
    var config: WorkspaceModuleConfig?
    /// Set when `config` cannot round-trip through this version, so unknown
    /// fields survive an export/import cycle byte-for-byte.
    var configRawBase64: String?
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: CodingKey {
        case id, kind, size, sortOrder, scope, savedViewID, config, configRawBase64
        case createdAt, updatedAt
    }

    init(
        id: UUID, kind: String, size: String, sortOrder: Int, scope: String,
        savedViewID: UUID?, config: WorkspaceModuleConfig?, configRawBase64: String?,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.kind = kind; self.size = size; self.sortOrder = sortOrder
        self.scope = scope; self.savedViewID = savedViewID
        self.config = config; self.configRawBase64 = configRawBase64
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        size = (try? c.decode(String.self, forKey: .size)) ?? ModuleSize.medium.rawValue
        sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
        scope = (try? c.decode(String.self, forKey: .scope)) ?? ModuleDataScope.inherit.rawValue
        savedViewID = try c.decodeIfPresent(UUID.self, forKey: .savedViewID)
        config = try c.decodeIfPresent(WorkspaceModuleConfig.self, forKey: .config)
        configRawBase64 = try c.decodeIfPresent(String.self, forKey: .configRawBase64)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }
}

nonisolated struct BackupWorkspace: Codable {
    var id: UUID
    var name: String
    var emoji: String
    var accent: String
    var sortOrder: Int
    var isGlobal: Bool
    var filter: TaskFilterExpression?
    /// Raw filter bytes when the structured value would lose fields.
    var filterRawBase64: String?
    var createdAt: Date
    var updatedAt: Date
    var modules: [BackupWorkspaceModule]

    private enum CodingKeys: CodingKey {
        case id, name, emoji, accent, sortOrder, isGlobal, filter, filterRawBase64
        case createdAt, updatedAt, modules
    }

    init(
        id: UUID, name: String, emoji: String, accent: String, sortOrder: Int,
        isGlobal: Bool, filter: TaskFilterExpression?, filterRawBase64: String?,
        createdAt: Date, updatedAt: Date, modules: [BackupWorkspaceModule]
    ) {
        self.id = id; self.name = name; self.emoji = emoji; self.accent = accent
        self.sortOrder = sortOrder; self.isGlobal = isGlobal
        self.filter = filter; self.filterRawBase64 = filterRawBase64
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.modules = modules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? "🗂"
        accent = (try? c.decode(String.self, forKey: .accent)) ?? WorkspaceAccent.sage.rawValue
        sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
        isGlobal = (try? c.decode(Bool.self, forKey: .isGlobal)) ?? false
        filter = try c.decodeIfPresent(TaskFilterExpression.self, forKey: .filter)
        filterRawBase64 = try c.decodeIfPresent(String.self, forKey: .filterRawBase64)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        modules = try c.decodeIfPresent([BackupWorkspaceModule].self, forKey: .modules) ?? []
    }
}

nonisolated struct BackupSavedView: Codable {
    var id: UUID
    var name: String
    var emoji: String
    var colorHex: String
    var filter: TaskFilterExpression?
    var filterRawBase64: String?
    var sortRaw: String
    var limit: Int
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: CodingKey {
        case id, name, emoji, colorHex, filter, filterRawBase64, sortRaw, limit
        case createdAt, updatedAt
    }

    init(
        id: UUID, name: String, emoji: String, colorHex: String,
        filter: TaskFilterExpression?, filterRawBase64: String?,
        sortRaw: String, limit: Int, createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.name = name; self.emoji = emoji; self.colorHex = colorHex
        self.filter = filter; self.filterRawBase64 = filterRawBase64
        self.sortRaw = sortRaw; self.limit = limit
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? "🔎"
        colorHex = (try? c.decode(String.self, forKey: .colorHex)) ?? "#4F7A69"
        filter = try c.decodeIfPresent(TaskFilterExpression.self, forKey: .filter)
        filterRawBase64 = try c.decodeIfPresent(String.self, forKey: .filterRawBase64)
        sortRaw = (try? c.decode(String.self, forKey: .sortRaw)) ?? TaskSortMode.standard.rawValue
        limit = (try? c.decode(Int.self, forKey: .limit)) ?? 8
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }
}

// MARK: - Entities

nonisolated struct BackupProject: Codable {
    var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    private enum CodingKeys: CodingKey { case id, name, notes, createdAt, updatedAt, archivedAt }

    init(id: UUID, name: String, notes: String, createdAt: Date, updatedAt: Date, archivedAt: Date?) {
        self.id = id; self.name = name; self.notes = notes
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.archivedAt = archivedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}

nonisolated struct BackupTag: Codable {
    var id: UUID
    var name: String
    var symbolName: String
    var colorHex: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var emoji: String

    private enum CodingKeys: CodingKey { case id, name, symbolName, colorHex, sortOrder, isArchived, createdAt, emoji }

    init(id: UUID, name: String, symbolName: String, colorHex: String, sortOrder: Int,
         isArchived: Bool, createdAt: Date, emoji: String) {
        self.id = id; self.name = name; self.symbolName = symbolName; self.colorHex = colorHex
        self.sortOrder = sortOrder; self.isArchived = isArchived; self.createdAt = createdAt; self.emoji = emoji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        symbolName = (try? c.decode(String.self, forKey: .symbolName)) ?? "tag"
        colorHex = (try? c.decode(String.self, forKey: .colorHex)) ?? "#808080"
        sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
        isArchived = (try? c.decode(Bool.self, forKey: .isArchived)) ?? false
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? ""
    }
}

nonisolated struct BackupTemplate: Codable {
    var id: UUID
    var name: String
    var emoji: String
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
    var definition: TemplateDefinition?
    /// Preserved byte-for-byte when the definition is a future/unreadable version.
    var definitionRawBase64: String?

    private enum CodingKeys: CodingKey {
        case id, name, emoji, revision, createdAt, updatedAt, definition, definitionRawBase64
    }

    init(id: UUID, name: String, emoji: String, revision: Int, createdAt: Date, updatedAt: Date,
         definition: TemplateDefinition?, definitionRawBase64: String?) {
        self.id = id; self.name = name; self.emoji = emoji; self.revision = revision
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.definition = definition; self.definitionRawBase64 = definitionRawBase64
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? ""
        revision = (try? c.decode(Int.self, forKey: .revision)) ?? 1
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        definition = try? c.decodeIfPresent(TemplateDefinition.self, forKey: .definition)
        definitionRawBase64 = try? c.decodeIfPresent(String.self, forKey: .definitionRawBase64)
    }
}

nonisolated struct BackupTask: Codable {
    var id: UUID
    var title: String
    var notes: String
    var status: String
    var importance: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var plannedStartAt: Date?
    var plannedAt: Date?
    var dueAt: Date?
    var archivedAt: Date?
    var projectID: UUID?
    var categoryID: UUID?
    var tagIDs: [UUID]
    var steps: [BackupStep]
    var templateInstance: BackupTemplateInstance?
    var milestones: [BackupMilestone]

    private enum CodingKeys: CodingKey {
        case id, title, notes, status, importance, createdAt, updatedAt, completedAt
        case plannedStartAt, plannedAt, dueAt, archivedAt, projectID, categoryID, tagIDs
        case steps, templateInstance, milestones
    }

    init(
        id: UUID, title: String, notes: String, status: String, importance: String,
        createdAt: Date, updatedAt: Date, completedAt: Date?, plannedStartAt: Date?,
        plannedAt: Date?, dueAt: Date?, archivedAt: Date?, projectID: UUID?,
        categoryID: UUID?, tagIDs: [UUID], steps: [BackupStep],
        templateInstance: BackupTemplateInstance?, milestones: [BackupMilestone]
    ) {
        self.id = id; self.title = title; self.notes = notes
        self.status = status; self.importance = importance
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.completedAt = completedAt
        self.plannedStartAt = plannedStartAt; self.plannedAt = plannedAt; self.dueAt = dueAt
        self.archivedAt = archivedAt; self.projectID = projectID; self.categoryID = categoryID
        self.tagIDs = tagIDs; self.steps = steps
        self.templateInstance = templateInstance; self.milestones = milestones
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? TaskStatus.pending.rawValue
        importance = (try? c.decode(String.self, forKey: .importance)) ?? TaskImportance.normal.rawValue
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        plannedStartAt = try c.decodeIfPresent(Date.self, forKey: .plannedStartAt)
        plannedAt = try c.decodeIfPresent(Date.self, forKey: .plannedAt)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        tagIDs = try c.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
        steps = try c.decodeIfPresent([BackupStep].self, forKey: .steps) ?? []
        templateInstance = try c.decodeIfPresent(BackupTemplateInstance.self, forKey: .templateInstance)
        milestones = try c.decodeIfPresent([BackupMilestone].self, forKey: .milestones) ?? []
    }
}

nonisolated struct BackupStep: Codable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date
    var completedAt: Date?

    private enum CodingKeys: CodingKey { case id, title, isCompleted, sortOrder, createdAt, completedAt }

    init(id: UUID, title: String, isCompleted: Bool, sortOrder: Int, createdAt: Date, completedAt: Date?) {
        self.id = id; self.title = title; self.isCompleted = isCompleted
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        isCompleted = (try? c.decode(Bool.self, forKey: .isCompleted)) ?? false
        sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

nonisolated struct BackupTemplateInstance: Codable {
    var id: UUID
    var templateID: UUID?
    var templateName: String
    var templateRevision: Int
    var payload: TemplatePayload?
    /// Preserved byte-for-byte when the payload is corrupt or from a future version.
    var payloadRawBase64: String?

    private enum CodingKeys: CodingKey {
        case id, templateID, templateName, templateRevision, payload, payloadRawBase64
    }

    init(id: UUID, templateID: UUID?, templateName: String, templateRevision: Int,
         payload: TemplatePayload?, payloadRawBase64: String?) {
        self.id = id; self.templateID = templateID; self.templateName = templateName
        self.templateRevision = templateRevision; self.payload = payload
        self.payloadRawBase64 = payloadRawBase64
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        templateID = try c.decodeIfPresent(UUID.self, forKey: .templateID)
        templateName = (try? c.decode(String.self, forKey: .templateName)) ?? ""
        templateRevision = (try? c.decode(Int.self, forKey: .templateRevision)) ?? 1
        payload = try? c.decodeIfPresent(TemplatePayload.self, forKey: .payload)
        payloadRawBase64 = try? c.decodeIfPresent(String.self, forKey: .payloadRawBase64)
    }
}

nonisolated struct BackupMilestone: Codable {
    var id: UUID
    var fieldID: UUID
    var title: String
    var semantic: String
    var date: Date
    var isOnCalendar: Bool
    var reminderLeadMinutes: Int?

    private enum CodingKeys: CodingKey {
        case id, fieldID, title, semantic, date, isOnCalendar, reminderLeadMinutes
    }

    init(id: UUID, fieldID: UUID, title: String, semantic: String, date: Date,
         isOnCalendar: Bool, reminderLeadMinutes: Int?) {
        self.id = id; self.fieldID = fieldID; self.title = title; self.semantic = semantic
        self.date = date; self.isOnCalendar = isOnCalendar; self.reminderLeadMinutes = reminderLeadMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fieldID = try c.decode(UUID.self, forKey: .fieldID)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        semantic = (try? c.decode(String.self, forKey: .semantic)) ?? MilestoneSemantic.date.rawValue
        date = (try? c.decode(Date.self, forKey: .date)) ?? BackupDateCoding.epoch
        isOnCalendar = (try? c.decode(Bool.self, forKey: .isOnCalendar)) ?? false
        reminderLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes)
    }
}

nonisolated struct BackupEvent: Codable {
    var id: UUID
    var title: String
    var notes: String
    var startsAt: Date
    var endsAt: Date
    var isAllDay: Bool
    var location: String?
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: CodingKey {
        case id, title, notes, startsAt, endsAt, isAllDay, location, createdAt, updatedAt
    }

    init(id: UUID, title: String, notes: String, startsAt: Date, endsAt: Date,
         isAllDay: Bool, location: String?, createdAt: Date, updatedAt: Date) {
        self.id = id; self.title = title; self.notes = notes
        self.startsAt = startsAt; self.endsAt = endsAt; self.isAllDay = isAllDay
        self.location = location; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        startsAt = try c.decode(Date.self, forKey: .startsAt)
        endsAt = try c.decode(Date.self, forKey: .endsAt)
        isAllDay = (try? c.decode(Bool.self, forKey: .isAllDay)) ?? false
        location = try c.decodeIfPresent(String.self, forKey: .location)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }
}

nonisolated struct BackupTaskReminder: Codable {
    var id: UUID
    var taskID: UUID
    var kind: String
    var leadMinutes: Int
    var scheduledAt: Date?
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: CodingKey {
        case id, taskID, kind, leadMinutes, scheduledAt, createdAt, updatedAt
    }

    init(id: UUID, taskID: UUID, kind: String, leadMinutes: Int, scheduledAt: Date?,
         createdAt: Date, updatedAt: Date) {
        self.id = id; self.taskID = taskID; self.kind = kind; self.leadMinutes = leadMinutes
        self.scheduledAt = scheduledAt; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        taskID = try c.decode(UUID.self, forKey: .taskID)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? TaskReminderKind.due.rawValue
        leadMinutes = (try? c.decode(Int.self, forKey: .leadMinutes)) ?? 0
        scheduledAt = try c.decodeIfPresent(Date.self, forKey: .scheduledAt)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? BackupDateCoding.epoch
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }
}

// MARK: - Counts

nonisolated struct BackupCounts: Codable, Equatable, Sendable {
    var projects = 0
    var tags = 0
    var templates = 0
    var tasks = 0
    var steps = 0
    var templateInstances = 0
    var milestones = 0
    var events = 0
    var reminders = 0
    var workspaces = 0
    var modules = 0
    var savedViews = 0

    static let zero = BackupCounts()

    var total: Int {
        projects + tags + templates + tasks + steps + templateInstances + milestones
            + events + reminders + workspaces + modules + savedViews
    }

    static func - (lhs: BackupCounts, rhs: BackupCounts) -> BackupCounts {
        BackupCounts(
            projects: max(0, lhs.projects - rhs.projects),
            tags: max(0, lhs.tags - rhs.tags),
            templates: max(0, lhs.templates - rhs.templates),
            tasks: max(0, lhs.tasks - rhs.tasks),
            steps: max(0, lhs.steps - rhs.steps),
            templateInstances: max(0, lhs.templateInstances - rhs.templateInstances),
            milestones: max(0, lhs.milestones - rhs.milestones),
            events: max(0, lhs.events - rhs.events),
            reminders: max(0, lhs.reminders - rhs.reminders),
            workspaces: max(0, lhs.workspaces - rhs.workspaces),
            modules: max(0, lhs.modules - rhs.modules),
            savedViews: max(0, lhs.savedViews - rhs.savedViews)
        )
    }
}

nonisolated extension BackupCounts {
    init(document: SelnoBackup) {
        let data = document.data
        projects = data.projects.count
        tags = data.tags.count
        templates = data.templates.count
        tasks = data.tasks.count
        steps = data.tasks.reduce(0) { $0 + $1.steps.count }
        templateInstances = data.tasks.reduce(0) { $0 + ($1.templateInstance == nil ? 0 : 1) }
        milestones = data.tasks.reduce(0) { $0 + $1.milestones.count }
        events = data.events.count
        reminders = data.reminders.count
        workspaces = data.workspaces.count
        modules = data.workspaces.reduce(0) { $0 + $1.modules.count }
        savedViews = data.savedViews.count
    }
}

// MARK: - Metadata

nonisolated enum SelnoBackupMetadata {
    static var currentAppVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

// MARK: - Date coding

nonisolated enum BackupDateCoding {
    static let epoch = Date(timeIntervalSince1970: 0)

    /// One formatter is created per codec, not per date. A backup with 10,000
    /// tasks contains tens of thousands of dates; allocating an
    /// `ISO8601DateFormatter` for each one dominated encode/decode time.
    static func makeEncodingStrategy() -> JSONEncoder.DateEncodingStrategy {
        let style = Date.ISO8601FormatStyle(
            includingFractionalSeconds: true,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
        )
        return .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(style))
        }
    }

    static func makeDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        let fractional = Date.ISO8601FormatStyle(
            includingFractionalSeconds: true,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
        )
        let plain = Date.ISO8601FormatStyle(timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt)
        return .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = (try? fractional.parse(value)) ?? (try? plain.parse(value)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "无效的 ISO 8601 日期：\(value)")
            }
            return date
        }
    }
}