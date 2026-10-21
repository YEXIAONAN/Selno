import Foundation

nonisolated enum TemplateFieldKind: String, Codable, CaseIterable, Identifiable {
    case text, multiline, dateTime, url
    var id: String { rawValue }
    var title: String { switch self { case .text: "文本"; case .multiline: "多行文本"; case .dateTime: "日期与时间"; case .url: "网址" } }
}

nonisolated enum MilestoneSemantic: String, CaseIterable, Identifiable, Codable {
    case date, registrationStarts, registrationEnds, activityStarts, activityEnds, submissionEnds
    var id: String { rawValue }
    var title: String {
        switch self {
        case .date: "一般时间"
        case .registrationStarts: "报名开始"
        case .registrationEnds: "报名截止"
        case .activityStarts: "活动开始"
        case .activityEnds: "活动结束"
        case .submissionEnds: "材料提交截止"
        }
    }
}

nonisolated struct TemplateField: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kindRaw: String = TemplateFieldKind.text.rawValue
    var group: String = "基本信息"
    var isOptional = true
    var isVisible = true
    var defaultText = ""
    var defaultDate: Date?
    var semanticRaw = MilestoneSemantic.date.rawValue
    var kind: TemplateFieldKind { TemplateFieldKind(rawValue: kindRaw) ?? .text }
    var isSupported: Bool { TemplateFieldKind(rawValue: kindRaw) != nil }
    init(_ name: String, kind: TemplateFieldKind = .text, group: String = "基本信息", semantic: MilestoneSemantic = .date) {
        self.name = name; kindRaw = kind.rawValue; self.group = group; semanticRaw = semantic.rawValue
    }
    private enum CodingKeys: CodingKey { case id, name, kindRaw, group, isOptional, isVisible, defaultText, defaultDate, semanticRaw }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "未命名字段"
        kindRaw = (try? c.decode(String.self, forKey: .kindRaw)) ?? "text"
        group = (try? c.decode(String.self, forKey: .group)) ?? "基本信息"
        isOptional = (try? c.decode(Bool.self, forKey: .isOptional)) ?? true
        isVisible = (try? c.decode(Bool.self, forKey: .isVisible)) ?? true
        defaultText = (try? c.decode(String.self, forKey: .defaultText)) ?? ""
        defaultDate = try? c.decode(Date.self, forKey: .defaultDate)
        semanticRaw = (try? c.decode(String.self, forKey: .semanticRaw)) ?? "date"
    }
}

nonisolated struct TemplateDefinition: Codable, Equatable {
    var version = 1
    var defaultImportanceRaw = "normal"
    var defaultTagIDs: [UUID] = []
    var fields: [TemplateField] = []
    init() { }
    private enum CodingKeys: CodingKey { case version, defaultImportanceRaw, defaultTagIDs, fields }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        defaultImportanceRaw = (try? c.decode(String.self, forKey: .defaultImportanceRaw)) ?? "normal"
        defaultTagIDs = (try? c.decode([UUID].self, forKey: .defaultTagIDs)) ?? []
        fields = try c.decode([TemplateField].self, forKey: .fields)
    }
}

nonisolated struct FieldAnswer: Codable, Identifiable, Equatable {
    var fieldID: UUID
    var text = ""
    var date: Date?
    var showOnCalendar = false
    var reminderMinutes: Int?
    var id: UUID { fieldID }
    init(fieldID: UUID, text: String = "", date: Date? = nil) { self.fieldID = fieldID; self.text = text; self.date = date }
    private enum CodingKeys: CodingKey { case fieldID, text, date, showOnCalendar, reminderMinutes }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fieldID = try values.decode(UUID.self, forKey: .fieldID)
        text = (try? values.decode(String.self, forKey: .text)) ?? ""
        date = try? values.decode(Date.self, forKey: .date)
        showOnCalendar = (try? values.decode(Bool.self, forKey: .showOnCalendar)) ?? false
        reminderMinutes = try? values.decode(Int.self, forKey: .reminderMinutes)
    }
}

nonisolated struct TemplatePayload: Codable, Equatable {
    var version = 1
    var fields: [TemplateField]
    var answers: [FieldAnswer]
    init(definition: TemplateDefinition) {
        fields = definition.fields
        answers = fields.map { FieldAnswer(fieldID: $0.id, text: $0.defaultText, date: $0.defaultDate) }
    }
    var isEditable: Bool { version == 1 && fields.allSatisfy(\.isSupported) }
    func answer(_ field: TemplateField) -> FieldAnswer { answers.first { $0.fieldID == field.id } ?? FieldAnswer(fieldID: field.id) }
}

nonisolated enum TemplateCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, data: Data?) -> T? {
        guard let data else { return nil }; return try? JSONDecoder().decode(type, from: data)
    }
}

nonisolated struct TemplateTaskDraft: Equatable {
    var templateID: UUID?
    var name: String
    var revision: Int
    var payload: TemplatePayload
}

nonisolated enum TemplateValidation {
    static func validate(_ payload: TemplatePayload) throws {
        guard payload.isEditable else { throw TemplateError.unsupportedVersion }
        guard Set(payload.fields.map(\.id)).count == payload.fields.count else { throw TemplateError.invalidFields }
        for field in payload.fields {
            let answer = payload.answer(field)
            if field.isVisible && !field.isOptional && ((field.kind == .dateTime && answer.date == nil) || (field.kind != .dateTime && answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) { throw TemplateError.missing(field.name) }
            if field.kind == .url && !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let parts = URLComponents(string: answer.text), ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false else { throw TemplateError.invalidURL(field.name) }
            }
            if let minutes = answer.reminderMinutes, minutes < 0 || minutes > 525600 { throw TemplateError.invalidFields }
            if let date = answer.date, !date.timeIntervalSince1970.isFinite { throw TemplateError.invalidFields }
        }
        let ranges: [(MilestoneSemantic, MilestoneSemantic)] = [(.registrationStarts, .registrationEnds), (.activityStarts, .activityEnds)]
        for (start, end) in ranges {
            let first = payload.fields.first { $0.semanticRaw == start.rawValue }.flatMap { payload.answer($0).date }
            let last = payload.fields.first { $0.semanticRaw == end.rawValue }.flatMap { payload.answer($0).date }
            if let first, let last, first > last { throw TemplateError.invalidRange(start.title, end.title) }
        }
    }
}

nonisolated enum TemplateError: LocalizedError {
    case missing(String), invalidURL(String), invalidRange(String, String), unsupportedVersion, invalidFields
    var errorDescription: String? {
        switch self {
        case .missing(let name): "请填写“\(name)”。"
        case .invalidURL(let name): "“\(name)”需要有效的 http 或 https 网址。"
        case .invalidRange(let start, let end): "\(start)不能晚于\(end)。"
        case .unsupportedVersion: "部分结构化数据来自更新的版本，已保留原始数据。请升级后编辑这些字段。"
        case .invalidFields: "字段标识或提醒设置无效，请检查模板。"
        }
    }
}
