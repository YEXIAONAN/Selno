import Foundation

nonisolated struct WorkspaceModuleDescriptor: Identifiable, Equatable, Sendable {
    let kind: WorkspaceModuleKind
    let title: String
    let symbolName: String
    let purpose: String
    let category: ModuleCatalogCategory
    let supportedSizes: [ModuleSize]
    let defaultSize: ModuleSize
    let defaultConfig: WorkspaceModuleConfig

    var id: String { kind.rawValue }

    func supports(_ size: ModuleSize) -> Bool {
        supportedSizes.contains(size)
    }

    var sizeList: String {
        supportedSizes.map(\.title).joined(separator: " / ")
    }
}

nonisolated enum WorkspaceModuleRegistry {
    static let all: [WorkspaceModuleDescriptor] = [
        WorkspaceModuleDescriptor(
            kind: .focus, title: "今日聚焦", symbolName: "scope",
            purpose: "把今天截止、已逾期和最重要的任务放在一处。",
            category: .focus, supportedSizes: [.medium, .large], defaultSize: .large,
            defaultConfig: WorkspaceModuleConfig(limit: 6)
        ),
        WorkspaceModuleDescriptor(
            kind: .upcoming, title: "近期安排", symbolName: "calendar.badge.clock",
            purpose: "查看未来 3 或 7 天每件事的下一次承诺。",
            category: .calendar, supportedSizes: [.medium, .large], defaultSize: .medium,
            defaultConfig: WorkspaceModuleConfig(days: 3, limit: 6)
        ),
        WorkspaceModuleDescriptor(
            kind: .month, title: "紧凑月历", symbolName: "calendar",
            purpose: "用日期标记扫视本月任务与日程。",
            category: .calendar, supportedSizes: [.medium, .large], defaultSize: .medium,
            defaultConfig: .default
        ),
        WorkspaceModuleDescriptor(
            kind: .inbox, title: "收件箱", symbolName: "tray",
            purpose: "快速记下想法，并处理尚未安排的事项。",
            category: .tasks, supportedSizes: [.small, .medium, .large], defaultSize: .medium,
            defaultConfig: WorkspaceModuleConfig(limit: 4)
        ),
        WorkspaceModuleDescriptor(
            kind: .projects, title: "项目进度", symbolName: "folder",
            purpose: "查看项目完成比例与逾期数量。",
            category: .tasks, supportedSizes: [.small, .medium, .large], defaultSize: .medium,
            defaultConfig: WorkspaceModuleConfig(limit: 3)
        ),
        WorkspaceModuleDescriptor(
            kind: .taskList, title: "任务列表", symbolName: "list.bullet.rectangle",
            purpose: "展示符合自定义规则的任务，可选择或直接编辑筛选。",
            category: .tasks, supportedSizes: [.medium, .large], defaultSize: .medium,
            defaultConfig: WorkspaceModuleConfig(filter: .activeOnly, limit: 8)
        ),
        WorkspaceModuleDescriptor(
            kind: .stats, title: "任务统计", symbolName: "chart.bar",
            purpose: "用真实任务数据呈现待办、今日完成、逾期与临近截止。",
            category: .focus, supportedSizes: [.small, .medium], defaultSize: .small,
            defaultConfig: .default
        ),
        WorkspaceModuleDescriptor(
            kind: .quickActions, title: "快捷操作", symbolName: "bolt",
            purpose: "新建任务、从模板创建、新建日程或直接进入今天。",
            category: .actions, supportedSizes: [.small, .medium], defaultSize: .small,
            defaultConfig: .default
        )
    ]

    static func descriptor(for kind: WorkspaceModuleKind) -> WorkspaceModuleDescriptor? {
        all.first { $0.kind == kind }
    }

    static func descriptor(forRaw rawValue: String) -> WorkspaceModuleDescriptor? {
        WorkspaceModuleKind(rawValue: rawValue).flatMap(descriptor(for:))
    }

    static func descriptors(in category: ModuleCatalogCategory) -> [WorkspaceModuleDescriptor] {
        all.filter { $0.category == category }
    }
}