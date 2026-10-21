import Foundation

// MARK: - Filter dimensions

nonisolated enum FilterDateField: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case due
    case planned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "任意日期"
        case .due: "截止日期"
        case .planned: "计划日期"
        }
    }
}

nonisolated enum FilterDateRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case today
    case next3Days
    case next7Days
    case thisWeek
    case thisMonth
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "不限日期"
        case .today: "今天"
        case .next3Days: "未来 3 天"
        case .next7Days: "未来 7 天"
        case .thisWeek: "本周"
        case .thisMonth: "本月"
        case .custom: "自定义范围"
        }
    }
}

nonisolated enum FilterDueState: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case hasDue
    case noDue
    case overdue
    case notOverdue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "不限截止"
        case .hasDue: "有截止日期"
        case .noDue: "无截止日期"
        case .overdue: "已逾期"
        case .notOverdue: "未逾期"
        }
    }
}

nonisolated enum FilterPresence: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case has
    case missing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "不限"
        case .has: "有计划日期"
        case .missing: "无计划日期"
        }
    }
}

// MARK: - Expression

/// A reusable, serializable task filter. Values inside one dimension are ORed;
/// dimensions are ANDed. Dates are evaluated with the caller's current Calendar
/// and TimeZone, never by slicing UTC strings.
nonisolated struct TaskFilterEvaluationContext {
    let today: Date
    let interval: DateInterval?
    let needle: String
}

nonisolated struct TaskFilterExpression: Codable, Equatable, Hashable {
    var statuses: Set<String>
    var importances: Set<String>
    var projectIDs: Set<UUID>
    var includeUnassignedProject: Bool
    var tagIDs: Set<UUID>
    var dateField: FilterDateField
    var dateRange: FilterDateRange
    var customStart: Date?
    var customEnd: Date?
    var dueState: FilterDueState
    var plannedState: FilterPresence
    var includeArchived: Bool
    var searchText: String

    init(
        statuses: Set<String> = [],
        importances: Set<String> = [],
        projectIDs: Set<UUID> = [],
        includeUnassignedProject: Bool = false,
        tagIDs: Set<UUID> = [],
        dateField: FilterDateField = .any,
        dateRange: FilterDateRange = .any,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        dueState: FilterDueState = .any,
        plannedState: FilterPresence = .any,
        includeArchived: Bool = false,
        searchText: String = ""
    ) {
        self.statuses = statuses
        self.importances = importances
        self.projectIDs = projectIDs
        self.includeUnassignedProject = includeUnassignedProject
        self.tagIDs = tagIDs
        self.dateField = dateField
        self.dateRange = dateRange
        self.customStart = customStart
        self.customEnd = customEnd
        self.dueState = dueState
        self.plannedState = plannedState
        self.includeArchived = includeArchived
        self.searchText = searchText
    }

    static var unrestricted: TaskFilterExpression { TaskFilterExpression() }

    static var activeOnly: TaskFilterExpression {
        TaskFilterExpression(statuses: [TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue])
    }

    var isUnrestricted: Bool {
        statuses.isEmpty && importances.isEmpty && projectIDs.isEmpty
            && !includeUnassignedProject && tagIDs.isEmpty
            && dateField == .any && dateRange == .any
            && dueState == .any && plannedState == .any
            && !includeArchived
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case statuses, importances, projectIDs, includeUnassignedProject, tagIDs
        case dateField, dateRange, customStart, customEnd, dueState, plannedState
        case includeArchived, searchText
    }

    /// Names of the fields this build owns. A newer build's extra keys are left
    /// untouched when the structured value is re-encoded.
    nonisolated static var persistedKeys: [String] {
        CodingKeys.allCases.map(\.rawValue)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statuses = Set((try? c.decode([String].self, forKey: .statuses)) ?? [])
        importances = Set((try? c.decode([String].self, forKey: .importances)) ?? [])
        projectIDs = Set((try? c.decode([UUID].self, forKey: .projectIDs)) ?? [])
        includeUnassignedProject = (try? c.decode(Bool.self, forKey: .includeUnassignedProject)) ?? false
        tagIDs = Set((try? c.decode([UUID].self, forKey: .tagIDs)) ?? [])
        dateField = (try? c.decodeIfPresent(FilterDateField.self, forKey: .dateField)) ?? .any
        dateRange = (try? c.decodeIfPresent(FilterDateRange.self, forKey: .dateRange)) ?? .any
        customStart = try? c.decodeIfPresent(Date.self, forKey: .customStart)
        customEnd = try? c.decodeIfPresent(Date.self, forKey: .customEnd)
        dueState = (try? c.decodeIfPresent(FilterDueState.self, forKey: .dueState)) ?? .any
        plannedState = (try? c.decodeIfPresent(FilterPresence.self, forKey: .plannedState)) ?? .any
        includeArchived = (try? c.decode(Bool.self, forKey: .includeArchived)) ?? false
        searchText = (try? c.decode(String.self, forKey: .searchText)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Sorting keeps exported JSON deterministic even though Sets are unordered.
        try c.encode(statuses.sorted(), forKey: .statuses)
        try c.encode(importances.sorted(), forKey: .importances)
        try c.encode(projectIDs.map(\.uuidString).sorted(), forKey: .projectIDs)
        try c.encode(includeUnassignedProject, forKey: .includeUnassignedProject)
        try c.encode(tagIDs.map(\.uuidString).sorted(), forKey: .tagIDs)
        try c.encode(dateField, forKey: .dateField)
        try c.encode(dateRange, forKey: .dateRange)
        try c.encodeIfPresent(customStart, forKey: .customStart)
        try c.encodeIfPresent(customEnd, forKey: .customEnd)
        try c.encode(dueState, forKey: .dueState)
        try c.encode(plannedState, forKey: .plannedState)
        try c.encode(includeArchived, forKey: .includeArchived)
        try c.encode(searchText, forKey: .searchText)
    }

    /// UUIDs are written as strings (and decoded by Foundation's UUID decoder)
    /// so hand-inspected JSON is readable and stable across platforms.
    private struct UUIDList: Codable {
        var values: [UUID]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            values = try c.decode([UUID].self)
        }
    }

    // MARK: Sanitizing

    /// Repairs values that may come from an older build or a hand-edited backup.
    /// Unknown status/importance values are dropped; an incomplete custom range
    /// falls back to "no date restriction". Business rows are never touched.
    func sanitized() -> TaskFilterExpression {
        var value = self
        let knownStatuses = Set(TaskStatus.allCases.map(\.rawValue))
        let knownImportances = Set(TaskImportance.allCases.map(\.rawValue))
        value.statuses = statuses.intersection(knownStatuses)
        value.importances = importances.intersection(knownImportances)
        value.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if dateRange != .custom {
            value.customStart = nil
            value.customEnd = nil
        } else if customStart == nil || customEnd == nil || customStart! > customEnd! {
            value.dateRange = .any
            value.customStart = nil
            value.customEnd = nil
        }

        if dateField == .any && dateRange == .any {
            // The field only matters when a range is active; keep the enum for
            // forward compatibility but do not let a stale value confuse the UI.
            value.dateField = .any
        }
        return value
    }

    func validated() throws -> TaskFilterExpression {
        let value = sanitized()
        if dateRange == .custom {
            guard let start = customStart, let end = customEnd else {
                throw TaskFilterError.incompleteCustomRange
            }
            guard start <= end else { throw TaskFilterError.reversedCustomRange }
        }
        return value
    }

    // MARK: Matching

    /// Values that do not depend on the task. Build this once per pass instead
    /// of calling `startOfDay` and rebuilding a date interval for every row.
    nonisolated func evaluationContext(now: Date, calendar: Calendar) -> TaskFilterEvaluationContext {
        TaskFilterEvaluationContext(
            today: calendar.startOfDay(for: now),
            interval: TaskFilterEngine.interval(
                for: dateRange, customStart: customStart, customEnd: customEnd,
                now: now, calendar: calendar
            ),
            needle: searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @MainActor
    func matches(_ task: TodoTask, context: TaskFilterEvaluationContext) -> Bool {
        if task.isArchived && !includeArchived { return false }

        if !statuses.isEmpty {
            guard statuses.contains(task.statusRaw) else { return false }
        }

        if !importances.isEmpty {
            guard importances.contains(task.importanceRaw) else { return false }
        }

        if !projectIDs.isEmpty || includeUnassignedProject {
            let assigned = task.project.map { projectIDs.contains($0.id) } ?? false
            let unassigned = task.project == nil && includeUnassignedProject
            guard assigned || unassigned else { return false }
        }

        if !tagIDs.isEmpty {
            var ids = Set((task.tags ?? []).map(\.id))
            if let category = task.category { ids.insert(category.id) }
            guard !ids.isDisjoint(with: tagIDs) else { return false }
        }

        switch dueState {
        case .any:
            break
        case .hasDue:
            guard task.dueAt != nil else { return false }
        case .noDue:
            guard task.dueAt == nil else { return false }
        case .overdue:
            guard task.status.isActive, let due = task.dueAt, due < context.today else { return false }
        case .notOverdue:
            guard let due = task.dueAt, due >= context.today else { return false }
        }

        switch plannedState {
        case .any:
            break
        case .has:
            guard task.plannedAt != nil || task.plannedStartAt != nil else { return false }
        case .missing:
            guard task.plannedAt == nil && task.plannedStartAt == nil else { return false }
        }

        if let interval = context.interval {
            let dates = TaskFilterEngine.dates(for: dateField, task: task)
            guard dates.contains(where: { TaskFilterEngine.contains(interval, $0) }) else { return false }
        }

        if !context.needle.isEmpty && !TaskQueryFilter.matches(task, needle: context.needle) {
            return false
        }
        return true
    }

    @MainActor
    func matches(_ task: TodoTask, now: Date, calendar: Calendar) -> Bool {
        matches(task, context: evaluationContext(now: now, calendar: calendar))
    }

    // MARK: Human readable

    func summary(projectNames: [UUID: String] = [:], tagNames: [UUID: String] = [:]) -> String {
        var parts: [String] = []

        if !statuses.isEmpty {
            let titles = TaskStatus.allCases.filter { statuses.contains($0.rawValue) }.map(\.title)
            parts.append(titles.joined(separator: "、"))
        }
        if !importances.isEmpty {
            let titles = TaskImportance.allCases.filter { importances.contains($0.rawValue) }.map(\.title)
            parts.append(titles.joined(separator: "、"))
        }
        if !projectIDs.isEmpty {
            let names = projectIDs.compactMap { projectNames[$0] }.sorted()
            parts.append(names.isEmpty ? "\(projectIDs.count) 个项目" : names.joined(separator: "、"))
        }
        if includeUnassignedProject { parts.append("含未归属项目") }
        if !tagIDs.isEmpty {
            let names = tagIDs.compactMap { tagNames[$0] }.sorted()
            parts.append(names.isEmpty ? "\(tagIDs.count) 个标签" : names.joined(separator: "、"))
        }
        if dateRange != .any {
            let field = dateField == .any ? "" : "\(dateField.title) · "
            parts.append("\(field)\(dateRange.title)")
        }
        switch dueState {
        case .any: break
        default: parts.append(dueState.title)
        }
        switch plannedState {
        case .any: break
        default: parts.append(plannedState.title)
        }
        if includeArchived { parts.append("包含已归档") }
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty { parts.append("搜索“\(needle)”") }

        return parts.isEmpty ? "全部数据" : parts.joined(separator: " · ")
    }
}

// MARK: - Errors

nonisolated enum TaskFilterError: LocalizedError, Equatable {
    case incompleteCustomRange
    case reversedCustomRange

    var errorDescription: String? {
        switch self {
        case .incompleteCustomRange: "自定义日期范围需要同时选择开始和结束日期。"
        case .reversedCustomRange: "自定义日期范围的结束日期不能早于开始日期。"
        }
    }
}

// MARK: - Engine

enum TaskFilterEngine {
    nonisolated static func resolve(
        scope: ModuleDataScope,
        custom: TaskFilterExpression?,
        workspace: TaskFilterExpression
    ) -> ResolvedTaskFilter {
        switch scope {
        case .inherit:
            return ResolvedTaskFilter(filter: workspace, source: .scenario)
        case .global:
            return ResolvedTaskFilter(filter: .unrestricted, source: .global)
        case .custom:
            return ResolvedTaskFilter(filter: custom ?? .unrestricted, source: .custom)
        }
    }

    nonisolated static func resolve(
        scopeRaw: String,
        custom: TaskFilterExpression?,
        workspace: TaskFilterExpression
    ) -> ResolvedTaskFilter {
        resolve(scope: ModuleDataScope(rawValue: scopeRaw) ?? .inherit, custom: custom, workspace: workspace)
    }

    @MainActor
    static func apply(
        _ filter: TaskFilterExpression,
        to tasks: [TodoTask],
        now: Date,
        calendar: Calendar
    ) -> [TodoTask] {
        let context = filter.evaluationContext(now: now, calendar: calendar)
        return tasks.filter { filter.matches($0, context: context) }
    }

    nonisolated static func interval(
        for range: FilterDateRange,
        customStart: Date?,
        customEnd: Date?,
        now: Date,
        calendar: Calendar
    ) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        func dayInterval(offset: Int = 0, length: Int = 1) -> DateInterval? {
            guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: offset + length, to: today),
                  end > start else { return nil }
            return DateInterval(start: start, end: end)
        }

        switch range {
        case .any:
            return nil
        case .today:
            return dayInterval()
        case .next3Days:
            return dayInterval(length: 3)
        case .next7Days:
            return dayInterval(length: 7)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .custom:
            guard let start = customStart, let end = customEnd else { return nil }
            let first = calendar.startOfDay(for: min(start, end))
            let last = calendar.startOfDay(for: max(start, end))
            guard let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: last),
                  exclusiveEnd > first else { return nil }
            return DateInterval(start: first, end: exclusiveEnd)
        }
    }

    nonisolated static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    @MainActor
    static func dates(for field: FilterDateField, task: TodoTask) -> [Date] {
        switch field {
        case .any:
            return [task.plannedStartAt, task.plannedAt, task.dueAt].compactMap { $0 }
        case .due:
            return [task.dueAt].compactMap { $0 }
        case .planned:
            return [task.plannedStartAt, task.plannedAt].compactMap { $0 }
        }
    }

    /// Requested date window for a filter, used once per board to bound queries.
    nonisolated static func requestedInterval(
        for filter: TaskFilterExpression,
        now: Date,
        calendar: Calendar
    ) -> DateInterval? {
        interval(for: filter.dateRange, customStart: filter.customStart,
                 customEnd: filter.customEnd, now: now, calendar: calendar)
    }
}