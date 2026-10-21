import Foundation
import SwiftData

@MainActor struct TemplateService {
    let context: ModelContext
    @discardableResult func save(_ template: TaskTemplate? = nil, name: String, emoji: String, definition: TemplateDefinition) throws -> TaskTemplate {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TemplateError.missing("模板名称") }
        if let template {
            guard let original = template.definition, original.version == 1, original.fields.allSatisfy(\.isSupported) else { throw TemplateError.unsupportedVersion }
        }
        guard definition.version == 1, Set(definition.fields.map(\.id)).count == definition.fields.count,
              definition.fields.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.isSupported }) else { throw TemplateError.invalidFields }
        var normalized = definition
        normalized.fields = normalized.fields.map { field in
            var field = field
            field.group = field.group.trimmingCharacters(in: .whitespacesAndNewlines)
            if field.group.isEmpty { field.group = "其他" }
            return field
        }
        let bytes = try TemplateCodec.encode(normalized)
        let result = template ?? TaskTemplate(name: name)
        if template == nil { context.insert(result) } else { result.revision += 1 }
        result.name = name; result.emoji = emoji; result.definitionData = bytes; result.updatedAt = .now
        try commit(); return result
    }
    @discardableResult func duplicate(_ template: TaskTemplate) throws -> TaskTemplate {
        guard let definition = template.definition else { throw TemplateError.unsupportedVersion }
        return try save(name: template.name + " 副本", emoji: template.emoji, definition: definition)
    }
    func delete(_ template: TaskTemplate) throws { context.delete(template); try commit() }
    @discardableResult func saveTaskAsTemplate(_ task: TodoTask, name: String) throws -> TaskTemplate {
        if task.templateInstance != nil && task.templateInstance?.payload == nil { throw TemplateError.unsupportedVersion }
        var definition = TemplateDefinition()
        definition.defaultImportanceRaw = task.importanceRaw; definition.defaultTagIDs = task.visibleTags.map(\.id)
        if let payload = task.templateInstance?.payload {
            guard payload.isEditable else { throw TemplateError.unsupportedVersion }
            definition.fields = payload.fields.map { field in
                var copy = field
                copy.defaultText = payload.answer(field).text
                // Dates and reminder choices belong to an instance; never carry stale schedules into a reusable template.
                copy.defaultDate = nil
                return copy
            }
        } else if !task.notes.isEmpty { var field = TemplateField("说明", kind: .multiline); field.defaultText = task.notes; definition.fields = [field] }
        return try save(name: name, emoji: "", definition: definition)
    }
    private func commit() throws { do { try context.save() } catch { context.rollback(); throw error } }
}

enum TemplatePresets {
    static var all: [(String, String, TemplateDefinition)] {
        let campus: [TemplateField] = [
            TemplateField("活动名称"), TemplateField("活动说明", kind: .multiline),
            TemplateField("报名开始时间", kind: .dateTime, group: "报名", semantic: .registrationStarts),
            TemplateField("报名截止时间", kind: .dateTime, group: "报名", semantic: .registrationEnds),
            TemplateField("活动开始时间", kind: .dateTime, group: "活动", semantic: .activityStarts),
            TemplateField("活动结束时间", kind: .dateTime, group: "活动", semantic: .activityEnds),
            TemplateField("活动地点", group: "活动"),
            TemplateField("材料提交截止时间", kind: .dateTime, group: "材料", semantic: .submissionEnds),
            TemplateField("材料提交地点", group: "材料"), TemplateField("报名入口", kind: .url, group: "报名"),
            TemplateField("活动附件说明", group: "材料"), TemplateField("备注", kind: .multiline, group: "其他")]
        var activity = TemplateDefinition(); activity.fields = campus
        var homework = TemplateDefinition(); homework.fields = [TemplateField("课程"), TemplateField("作业要求", kind: .multiline), TemplateField("提交截止", kind: .dateTime, semantic: .submissionEnds), TemplateField("提交入口", kind: .url)]
        var competition = TemplateDefinition(); competition.fields = [TemplateField("比赛说明", kind: .multiline), TemplateField("报名截止", kind: .dateTime, semantic: .registrationEnds), TemplateField("比赛开始", kind: .dateTime, semantic: .activityStarts), TemplateField("报名入口", kind: .url)]
        return [("普通任务", "📝", .init()), ("校园二课活动", "🏫", activity), ("课程作业", "📚", homework), ("比赛报名", "🏆", competition)]
    }
    @MainActor static func seed(in context: ModelContext) throws {
        let key = "task-templates-v3"
        guard try context.fetchCount(FetchDescriptor<SeedRecord>(predicate: #Predicate { $0.key == key })) == 0 else { return }
        do {
            for (name, emoji, definition) in all { context.insert(TaskTemplate(name: name, emoji: emoji, definition: definition)) }
            context.insert(SeedRecord(key: key)); try context.save()
        } catch { context.rollback(); throw error }
    }
}
