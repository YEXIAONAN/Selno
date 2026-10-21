import Foundation

enum BackupError: LocalizedError, Equatable {
    case unreadableFile(String)
    case fileTooLarge(Int, Int)
    case invalidJSON(String)
    case invalidFormat(String)
    case unsupportedVersion(found: Int, supported: Int)
    case invalidData(String)
    case ioFailure(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let reason):
            return "无法读取所选文件：\(reason)"
        case .fileTooLarge(let size, let limit):
            return "备份文件过大（\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))），超过 \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) 上限。"
        case .invalidJSON(let detail):
            return "文件不是有效的 Selno 备份 JSON：\(detail)"
        case .invalidFormat(let found):
            return "文件格式标识不正确（\(found.isEmpty ? "缺失" : found)）。请选择由 Selno 导出的备份文件。"
        case .unsupportedVersion(let found, let supported):
            return "备份格式版本为 \(found)，当前 Selno 支持版本 1–\(supported)。请升级 Selno 后重试；不会导入未知版本的数据。"
        case .invalidData(let detail):
            return "备份数据校验失败：\(detail)"
        case .ioFailure(let detail):
            return "文件读写失败：\(detail)"
        case .importFailed(let detail):
            return "导入未完成，现有数据已恢复原状：\(detail)"
        }
    }
}

nonisolated enum BackupCodec {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = BackupDateCoding.encodingStrategy
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = BackupDateCoding.decodingStrategy
        return decoder
    }

    static func encode(_ backup: SelnoBackup) throws -> Data {
        do { return try makeEncoder().encode(backup) }
        catch { throw BackupError.invalidData("无法生成 JSON：\(error.localizedDescription)") }
    }

    static func decode(_ data: Data) throws -> SelnoBackup {
        do {
            return try makeDecoder().decode(SelnoBackup.self, from: data)
        } catch let error as DecodingError {
            throw BackupError.invalidJSON(describe(error))
        } catch {
            throw BackupError.invalidJSON(error.localizedDescription)
        }
    }

    static func validate(_ backup: SelnoBackup) throws {
        guard backup.format == SelnoBackup.formatIdentifier else {
            throw BackupError.invalidFormat(backup.format)
        }
        guard (SelnoBackup.minimumSupportedSchemaVersion...SelnoBackup.currentSchemaVersion)
            .contains(backup.schemaVersion) else {
            throw BackupError.unsupportedVersion(found: backup.schemaVersion,
                                                 supported: SelnoBackup.currentSchemaVersion)
        }
        guard isFinite(backup.exportedAt) else {
            throw BackupError.invalidData("导出时间无效。")
        }
        try validate(backup.data)
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let value = context.codingPath.map { key in
                key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)"
            }.joined()
            return value.isEmpty ? "根对象" : String(value.dropFirst())
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "缺少必需字段 \(path(context)).\(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "字段 \(path(context)) 的类型不正确"
        case .dataCorrupted(let context):
            return "\(path(context))：\(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func validate(_ data: SelnoBackupData) throws {
        let projectIDs = try uniqueIDs(data.projects.map(\.id), entity: "项目")
        let tagIDs = try uniqueIDs(data.tags.map(\.id), entity: "标签")
        _ = try uniqueIDs(data.templates.map(\.id), entity: "模板")
        let taskIDs = try uniqueIDs(data.tasks.map(\.id), entity: "任务")
        _ = try uniqueIDs(data.events.map(\.id), entity: "日程")
        _ = try uniqueIDs(data.reminders.map(\.id), entity: "提醒")

        for project in data.projects {
            guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidData("项目 \(shortID(project.id)) 缺少名称。")
            }
            try requireFinite(project.createdAt, "项目创建时间")
            try requireFinite(project.updatedAt, "项目更新时间")
            if let archivedAt = project.archivedAt {
                try requireFinite(archivedAt, "项目归档时间")
            }
        }

        for tag in data.tags {
            guard !tag.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidData("标签 \(shortID(tag.id)) 缺少名称。")
            }
            try requireFinite(tag.createdAt, "标签创建时间")
        }

        for template in data.templates {
            guard !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidData("模板 \(shortID(template.id)) 缺少名称。")
            }
            try requireFinite(template.createdAt, "模板创建时间")
            try requireFinite(template.updatedAt, "模板更新时间")
            try validateBase64(template.definitionRawBase64, label: "模板 \(shortID(template.id)) 的原始定义")
        }

        var stepIDs = Set<UUID>()
        var instanceIDs = Set<UUID>()
        var milestoneIDs = Set<UUID>()

        for task in data.tasks {
            guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidData("任务 \(shortID(task.id)) 缺少标题。")
            }
            guard TaskStatus(rawValue: task.status) != nil else {
                throw BackupError.invalidData("任务 \(shortID(task.id)) 的状态值“\(task.status)”无法识别。")
            }
            guard TaskImportance(rawValue: task.importance) != nil else {
                throw BackupError.invalidData("任务 \(shortID(task.id)) 的重要性值“\(task.importance)”无法识别。")
            }
            if let projectID = task.projectID, !projectIDs.contains(projectID) {
                throw BackupError.invalidData("任务 \(shortID(task.id)) 关联的项目 \(shortID(projectID)) 不存在。")
            }
            if let categoryID = task.categoryID, !tagIDs.contains(categoryID) {
                throw BackupError.invalidData("任务 \(shortID(task.id)) 的分类标签 \(shortID(categoryID)) 不存在。")
            }
            for tagID in task.tagIDs where !tagIDs.contains(tagID) {
                throw BackupError.invalidData("任务 \(shortID(task.id)) 关联的标签 \(shortID(tagID)) 不存在。")
            }
            guard Set(task.tagIDs).count == task.tagIDs.count else {
                throw BackupError.invalidData("任务 \(shortID(task.id)) 含有重复的标签关联。")
            }
            try requireFinite(task.createdAt, "任务创建时间")
            try requireFinite(task.updatedAt, "任务更新时间")
            for (date, label) in [(task.completedAt, "完成时间"), (task.plannedStartAt, "计划开始时间"),
                                  (task.plannedAt, "计划日期"), (task.dueAt, "截止日期"), (task.archivedAt, "归档时间")] {
                if let date { try requireFinite(date, label) }
            }
            for step in task.steps {
                guard stepIDs.insert(step.id).inserted else {
                    throw BackupError.invalidData("子任务标识 \(shortID(step.id)) 重复。")
                }
                guard !step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BackupError.invalidData("子任务 \(shortID(step.id)) 缺少标题。")
                }
                try requireFinite(step.createdAt, "子任务创建时间")
                if let completedAt = step.completedAt { try requireFinite(completedAt, "子任务完成时间") }
            }
            if let instance = task.templateInstance {
                guard instanceIDs.insert(instance.id).inserted else {
                    throw BackupError.invalidData("模板实例标识 \(shortID(instance.id)) 重复。")
                }
                try validateBase64(instance.payloadRawBase64, label: "任务 \(shortID(task.id)) 的模板快照")
            }
            for milestone in task.milestones {
                guard milestoneIDs.insert(milestone.id).inserted else {
                    throw BackupError.invalidData("时间节点标识 \(shortID(milestone.id)) 重复。")
                }
                try requireFinite(milestone.date, "时间节点日期")
                if let lead = milestone.reminderLeadMinutes, !(0...525_600).contains(lead) {
                    throw BackupError.invalidData("时间节点 \(shortID(milestone.id)) 的提醒提前量超出范围。")
                }
            }
        }

        for event in data.events {
            guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidData("日程 \(shortID(event.id)) 缺少标题。")
            }
            try requireFinite(event.startsAt, "日程开始时间")
            try requireFinite(event.endsAt, "日程结束时间")
            if event.isAllDay {
                guard event.endsAt > event.startsAt else {
                    throw BackupError.invalidData("全天日程 \(shortID(event.id)) 的结束日期必须晚于开始日期。")
                }
            } else {
                guard event.endsAt >= event.startsAt else {
                    throw BackupError.invalidData("日程 \(shortID(event.id)) 的结束时间早于开始时间。")
                }
            }
            try requireFinite(event.createdAt, "日程创建时间")
            try requireFinite(event.updatedAt, "日程更新时间")
        }

        let tasksByID = Dictionary(uniqueKeysWithValues: data.tasks.map { ($0.id, $0) })
        for reminder in data.reminders {
            guard let task = tasksByID[reminder.taskID] else {
                throw BackupError.invalidData("提醒 \(shortID(reminder.id)) 关联的任务 \(shortID(reminder.taskID)) 不存在。")
            }
            guard let kind = TaskReminderKind(rawValue: reminder.kind) else {
                throw BackupError.invalidData("提醒 \(shortID(reminder.id)) 的类型“\(reminder.kind)”无法识别。")
            }
            guard (0...525_600).contains(reminder.leadMinutes) else {
                throw BackupError.invalidData("提醒 \(shortID(reminder.id)) 的提前量超出范围。")
            }
            switch kind {
            case .due:
                guard task.dueAt != nil else {
                    throw BackupError.invalidData("任务 \(shortID(task.id)) 没有截止日期，无法恢复截止提醒。")
                }
            case .scheduled:
                guard let scheduledAt = reminder.scheduledAt else {
                    throw BackupError.invalidData("提醒 \(shortID(reminder.id)) 缺少指定时间。")
                }
                try requireFinite(scheduledAt, "提醒时间")
            }
            try requireFinite(reminder.createdAt, "提醒创建时间")
            try requireFinite(reminder.updatedAt, "提醒更新时间")
        }

        // Version 1 files have no configuration rows at all. Version 2 files must
        // describe a self-contained layout so a merge can never leave a module
        // pointing at a workspace or saved view that does not exist afterwards.
        _ = try uniqueIDs(data.workspaces.map(\.id), entity: "工作台")
        let savedViewIDs = try uniqueIDs(data.savedViews.map(\.id), entity: "任务视图")
        var moduleIDs = Set<UUID>()
        var globalCount = 0

        guard data.workspaces.count <= WorkspaceLimits.maximumWorkspaces else {
            throw BackupError.invalidData("备份中的工作台超过 \(WorkspaceLimits.maximumWorkspaces) 个。")
        }

        for workspace in data.workspaces {
            guard !workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidData("工作台 \(shortID(workspace.id)) 缺少名称。")
            }
            guard workspace.modules.count <= WorkspaceLimits.maximumModulesPerWorkspace else {
                throw BackupError.invalidData(
                    "工作台 \(shortID(workspace.id)) 的模块超过 \(WorkspaceLimits.maximumModulesPerWorkspace) 个。"
                )
            }
            if workspace.isGlobal { globalCount += 1 }
            try requireFinite(workspace.createdAt, "工作台创建时间")
            try requireFinite(workspace.updatedAt, "工作台更新时间")
            try validateBase64(workspace.filterRawBase64,
                               label: "工作台 \(shortID(workspace.id)) 的原始筛选")
            try validateFilter(workspace.filter, label: "工作台 \(shortID(workspace.id))")

            for module in workspace.modules {
                guard moduleIDs.insert(module.id).inserted else {
                    throw BackupError.invalidData("模块标识 \(shortID(module.id)) 重复。")
                }
                guard !module.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BackupError.invalidData("模块 \(shortID(module.id)) 缺少类型。")
                }
                guard !module.size.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BackupError.invalidData("模块 \(shortID(module.id)) 缺少尺寸。")
                }
                guard !module.scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BackupError.invalidData("模块 \(shortID(module.id)) 缺少数据范围。")
                }
                if let viewID = module.savedViewID, !savedViewIDs.contains(viewID) {
                    throw BackupError.invalidData(
                        "模块 \(shortID(module.id)) 关联的任务视图 \(shortID(viewID)) 不存在。"
                    )
                }
                try requireFinite(module.createdAt, "模块创建时间")
                try requireFinite(module.updatedAt, "模块更新时间")
                try validateBase64(module.configRawBase64,
                                   label: "模块 \(shortID(module.id)) 的原始配置")
                try validateFilter(module.config?.filter, label: "模块 \(shortID(module.id))")
            }
        }

        guard globalCount <= 1 else {
            throw BackupError.invalidData("备份中包含多个全局工作台。")
        }

        for view in data.savedViews {
            guard !view.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidData("任务视图 \(shortID(view.id)) 缺少名称。")
            }
            let hex = view.colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else {
                throw BackupError.invalidData("任务视图 \(shortID(view.id)) 的颜色值无效。")
            }
            try requireFinite(view.createdAt, "任务视图创建时间")
            try requireFinite(view.updatedAt, "任务视图更新时间")
            try validateBase64(view.filterRawBase64,
                               label: "任务视图 \(shortID(view.id)) 的原始筛选")
            try validateFilter(view.filter, label: "任务视图 \(shortID(view.id))")
        }
        _ = taskIDs
    }

    /// Invalid custom ranges are rejected instead of silently widened. Values a
    /// newer build may have introduced (status, importance, sort modes) are left
    /// for the sanitizer, which repairs only configuration rows.
    private static func validateFilter(_ filter: TaskFilterExpression?, label: String) throws {
        guard let filter else { return }
        for date in [filter.customStart, filter.customEnd].compactMap({ $0 }) {
            try requireFinite(date, "\(label)的筛选日期")
        }
        if filter.dateRange == .custom {
            guard let start = filter.customStart, let end = filter.customEnd else {
                throw BackupError.invalidData("\(label)的自定义日期范围不完整。")
            }
            guard start <= end else {
                throw BackupError.invalidData("\(label)的自定义日期范围结束早于开始。")
            }
        }
    }

    private static func uniqueIDs(_ ids: [UUID], entity: String) throws -> Set<UUID> {
        let unique = Set(ids)
        guard unique.count == ids.count else {
            throw BackupError.invalidData("备份中包含重复的\(entity)标识。")
        }
        return unique
    }

    private static func requireFinite(_ date: Date, _ label: String) throws {
        guard isFinite(date) else { throw BackupError.invalidData("\(label)无效。") }
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite
    }

    private static func validateBase64(_ value: String?, label: String) throws {
        guard let value else { return }
        guard Data(base64Encoded: value) != nil else {
            throw BackupError.invalidData("\(label)不是有效的 Base64 数据。")
        }
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}