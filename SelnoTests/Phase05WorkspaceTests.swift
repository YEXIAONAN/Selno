import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct Phase05WorkspaceTests {
    private let base = Date(timeIntervalSince1970: 1_790_003_000.125)

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3_600) ?? .gmt
        value.locale = Locale(identifier: "zh_CN")
        return value
    }

    private func make() throws -> (ModelContainer, ModelContext) {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        return (container, container.mainContext)
    }

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    private func seed(_ context: ModelContext, now: Date? = nil) throws -> Workspace {
        try WorkspaceSeeder.seedIfNeeded(in: context, now: now ?? base)
        return try #require(try WorkspaceService(context: context).globalWorkspace())
    }

    private func snapshot(
        id: UUID = UUID(),
        kind: WorkspaceModuleKind,
        size: ModuleSize,
        order: Int,
        scope: ModuleDataScope = .inherit,
        savedViewID: UUID? = nil,
        config: WorkspaceModuleConfig = .default
    ) -> WorkspaceModuleSnapshot {
        WorkspaceModuleSnapshot(
            id: id, kindRaw: kind.rawValue, sizeRaw: size.rawValue, sortOrder: order,
            scopeRaw: scope.rawValue, savedViewID: savedViewID, config: config,
            rawConfigData: config.encoded(), createdAt: base, updatedAt: base
        )
    }

    // MARK: - Seeding

    @Test func globalWorkspaceSeedsExactlyOnceAndLeavesBusinessRowsUntouched() throws {
        let (container, context) = try make()
        _ = container
        let project = TodoProject(name: "毕业设计", now: base)
        let tag = TaskCategory(name: "学习", symbolName: "book", colorHex: "#3F6852", sortOrder: 1, now: base)
        let task = TodoTask(title: "写论文", status: .pending, importance: .high, now: base)
        task.project = project
        task.tags = [tag]
        task.category = tag
        let event = CalendarEvent(title: "组会", startsAt: base, endsAt: base.addingTimeInterval(3_600),
                                  now: base)
        context.insert(project)
        context.insert(tag)
        context.insert(task)
        context.insert(event)
        try context.save()

        let global = try seed(context)
        #expect(global.isGlobal)
        #expect(global.name == DefaultWorkspaceFactory.globalName)
        #expect(global.emoji == DefaultWorkspaceFactory.globalEmoji)
        #expect(global.sortOrder == 0)
        #expect(global.filter.isUnrestricted)
        #expect(global.orderedModules.count == DefaultWorkspaceFactory.globalSpecs.count)
        #expect(global.orderedModules.compactMap(\.kind)
                == DefaultWorkspaceFactory.globalSpecs.map(\.kind))
        #expect(global.orderedModules.map(\.sortOrder) == Array(0..<DefaultWorkspaceFactory.globalSpecs.count))
        #expect(global.orderedModules.allSatisfy { $0.scope == .inherit })
        #expect(global.orderedModules.first?.config.limit == 6)

        // A second launch (same store, same process) must not add another global
        // workspace or another copy of the default layout.
        try WorkspaceSeeder.seedIfNeeded(in: context, now: base.addingTimeInterval(60))
        #expect(try count(Workspace.self, in: context) == 1)
        #expect(try count(WorkspaceModule.self, in: context)
                == DefaultWorkspaceFactory.globalSpecs.count)
        #expect(try count(TodoTask.self, in: context) == 1)
        #expect(try count(TodoProject.self, in: context) == 1)
        #expect(try count(TaskCategory.self, in: context) == 1)
        #expect(try count(CalendarEvent.self, in: context) == 1)
        let fetched = try #require(try context.fetch(FetchDescriptor<TodoTask>()).first)
        #expect(fetched.project?.id == project.id)
        #expect(fetched.tags?.map(\.id) == [tag.id])
    }

    @Test func seedingRepairsAMissingGlobalWithoutDiscardingExistingScenarios() throws {
        let (container, context) = try make()
        _ = container
        let existing = Workspace(name: "手动场景", emoji: "🧪", accent: .plum,
                                 sortOrder: 4, isGlobal: false,
                                 filter: .activeOnly, now: base)
        context.insert(existing)
        let module = WorkspaceModule(kind: .inbox, size: .small, sortOrder: 0, now: base)
        context.insert(module)
        module.workspace = existing
        try context.save()

        let global = try seed(context)
        #expect(global.id != existing.id)
        #expect(global.isGlobal)
        #expect(global.sortOrder == 0)
        let workspaces = try WorkspaceService(context: context).allWorkspaces()
        #expect(workspaces.count == 2)
        #expect(workspaces.first?.isGlobal == true)
        let scenario = try #require(workspaces.first { !$0.isGlobal })
        #expect(scenario.id == existing.id)
        #expect(scenario.name == "手动场景")
        #expect(scenario.sortOrder == 1)
        #expect(scenario.orderedModules.count == 1)

        try WorkspaceSeeder.seedIfNeeded(in: context, now: base.addingTimeInterval(10))
        #expect(try count(Workspace.self, in: context) == 2)
    }

    // MARK: - Lifecycle

    @Test func createPresetAndBlankWorkspacesUseValidatedDefaults() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)

        let campus = try service.createWorkspace(
            name: "  校园  ", emoji: "🎓", accent: .ocean,
            filter: .activeOnly, preset: .campus, now: base
        )
        #expect(campus.name == "校园")
        #expect(campus.emoji == "🎓")
        #expect(campus.accent == .ocean)
        #expect(campus.isGlobal == false)
        #expect(campus.sortOrder == 1)
        #expect(campus.filter == TaskFilterExpression.activeOnly)
        #expect(campus.orderedModules.compactMap(\.kind) == [
            .focus, .upcoming, .month, .taskList, .projects
        ])
        #expect(campus.orderedModules.map(\.sortOrder) == Array(0..<5))

        let blank = try service.createWorkspace(
            name: "空白", emoji: "", accent: .sage,
            filter: .unrestricted, preset: .blank, now: base.addingTimeInterval(10)
        )
        #expect(blank.emoji == WorkspacePreset.blank.defaultEmoji)
        #expect(blank.orderedModules.isEmpty)
        #expect(blank.sortOrder == 2)

        #expect(throws: WorkspaceError.emptyName) {
            try service.createWorkspace(name: "   ", emoji: "📁", accent: .sage,
                                        filter: .unrestricted, preset: .blank)
        }
        #expect(throws: WorkspaceError.nameTooLong) {
            try service.createWorkspace(name: String(repeating: "名", count: 31),
                                        emoji: "📁", accent: .sage,
                                        filter: .unrestricted, preset: .blank)
        }
        #expect(throws: WorkspaceError.invalidEmoji) {
            try service.createWorkspace(name: "过长 Emoji", emoji: "123456789",
                                        accent: .sage, filter: .unrestricted, preset: .blank)
        }
        #expect(throws: WorkspaceError.self) {
            try service.createWorkspace(
                name: "坏日期", emoji: "📁", accent: .sage,
                filter: TaskFilterExpression(dateRange: .custom, customStart: base),
                preset: .blank
            )
        }
    }

    @Test func duplicateCopiesConfigurationButNeverModuleIdentityOrTasks() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)
        let task = TodoTask(title: "不应被复制", now: base)
        context.insert(task)
        try context.save()

        let source = try service.createWorkspace(
            name: "开发", emoji: "💻", accent: .slate,
            filter: TaskFilterExpression(statuses: [TaskStatus.inProgress.rawValue]),
            preset: .development, now: base
        )
        let sourceModuleIDs = Set(source.orderedModules.map(\.id))
        let copy = try service.duplicateWorkspace(source, now: base.addingTimeInterval(100))

        #expect(copy.id != source.id)
        #expect(copy.name == "开发 副本")
        #expect(copy.emoji == source.emoji)
        #expect(copy.accent == source.accent)
        #expect(copy.filter == source.filter)
        #expect(copy.isGlobal == false)
        #expect(copy.orderedModules.count == source.orderedModules.count)
        #expect(Set(copy.orderedModules.map(\.id)).isDisjoint(with: sourceModuleIDs))
        #expect(copy.orderedModules.map(\.kindRaw) == source.orderedModules.map(\.kindRaw))
        #expect(copy.orderedModules.map(\.sizeRaw) == source.orderedModules.map(\.sizeRaw))
        #expect(copy.orderedModules.map(\.sortOrder) == source.orderedModules.map(\.sortOrder))
        #expect(copy.orderedModules.map(\.scopeRaw) == source.orderedModules.map(\.scopeRaw))
        #expect(copy.orderedModules.map(\.config) == source.orderedModules.map(\.config))
        #expect(try count(TodoTask.self, in: context) == 1)
        #expect(try count(Workspace.self, in: context) == 3)

        let global = try #require(try service.globalWorkspace())
        let globalCopy = try service.duplicateWorkspace(global,
                                                       now: base.addingTimeInterval(200))
        #expect(globalCopy.isGlobal == false)
        #expect(globalCopy.orderedModules.count == DefaultWorkspaceFactory.globalSpecs.count)
    }

    @Test func updateRenameAccentAndFilterDoesNotTouchLayout() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)
        let workspace = try service.createWorkspace(
            name: "生活", emoji: "🌿", accent: .amber,
            filter: .unrestricted, preset: .life, now: base
        )
        let moduleIDs = workspace.orderedModules.map(\.id)
        let filter = TaskFilterExpression(
            statuses: [TaskStatus.pending.rawValue],
            importances: [TaskImportance.high.rawValue],
            dateField: .due, dateRange: .next7Days,
            dueState: .hasDue, searchText: "  报告  "
        )
        try service.updateWorkspace(workspace.id, name: " 生活与学习 ", emoji: "📖",
                                    accent: .plum, filter: filter,
                                    now: base.addingTimeInterval(20))
        let updated = try #require(try service.fetchWorkspace(id: workspace.id))
        #expect(updated.name == "生活与学习")
        #expect(updated.emoji == "📖")
        #expect(updated.accent == .plum)
        #expect(updated.filter.statuses == [TaskStatus.pending.rawValue])
        #expect(updated.filter.searchText == "报告")
        #expect(updated.updatedAt == base.addingTimeInterval(20))
        #expect(updated.orderedModules.map(\.id) == moduleIDs)

        #expect(throws: WorkspaceError.workspaceNotFound) {
            try service.updateWorkspace(UUID(), name: "不存在", emoji: "🗂",
                                        accent: .sage, filter: .unrestricted)
        }
    }

    @Test func deleteRemovesOnlyScenarioConfigurationAndProtectsGlobal() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)
        let project = TodoProject(name: "项目", now: base)
        let tag = TaskCategory(name: "标签", symbolName: "tag", colorHex: "#3F6852",
                               sortOrder: 1, now: base)
        let task = TodoTask(title: "任务", now: base)
        task.project = project
        task.tags = [tag]
        let event = CalendarEvent(title: "日程", startsAt: base,
                                  endsAt: base.addingTimeInterval(600), now: base)
        context.insert(project)
        context.insert(tag)
        context.insert(task)
        context.insert(event)
        try context.save()

        let first = try service.createWorkspace(name: "一", emoji: "1️⃣", accent: .sage,
                                                filter: .unrestricted, preset: .campus, now: base)
        let second = try service.createWorkspace(name: "二", emoji: "2️⃣", accent: .ocean,
                                                 filter: .unrestricted, preset: .life,
                                                 now: base.addingTimeInterval(10))
        let third = try service.createWorkspace(name: "三", emoji: "3️⃣", accent: .amber,
                                                filter: .unrestricted, preset: .development,
                                                now: base.addingTimeInterval(20))
        let firstModuleCount = first.orderedModules.count
        try service.deleteWorkspace(second.id)

        let remaining = try service.scenarioWorkspaces()
        #expect(remaining.map(\.name) == ["一", "三"])
        #expect(remaining.map(\.sortOrder) == [1, 2])
        #expect(try count(WorkspaceModule.self, in: context)
                == DefaultWorkspaceFactory.globalSpecs.count + firstModuleCount
                    + third.orderedModules.count)
        #expect(try count(TodoTask.self, in: context) == 1)
        #expect(try count(TodoProject.self, in: context) == 1)
        #expect(try count(TaskCategory.self, in: context) == 1)
        #expect(try count(CalendarEvent.self, in: context) == 1)

        let global = try #require(try service.globalWorkspace())
        #expect(throws: WorkspaceError.globalCannotBeDeleted) {
            try service.deleteWorkspace(global.id)
        }
        #expect(throws: WorkspaceError.workspaceNotFound) {
            try service.deleteWorkspace(UUID())
        }
    }

    @Test func reorderCanonicalizesScenarioOrderAndIgnoresUnknownIDs() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)
        let a = try service.createWorkspace(name: "A", emoji: "🅰️", accent: .sage,
                                            filter: .unrestricted, preset: .blank, now: base)
        let b = try service.createWorkspace(name: "B", emoji: "🅱️", accent: .ocean,
                                            filter: .unrestricted, preset: .blank, now: base)
        let c = try service.createWorkspace(name: "C", emoji: "©️", accent: .rose,
                                            filter: .unrestricted, preset: .blank, now: base)
        try service.reorderWorkspaces([c.id, UUID(), a.id, c.id, b.id])
        #expect(try service.scenarioWorkspaces().map(\.name) == ["C", "A", "B"])
        #expect(try service.scenarioWorkspaces().map(\.sortOrder) == [1, 2, 3])
        #expect(try service.globalWorkspace()?.sortOrder == 0)
    }

    @Test func workspaceAndModuleLimitsAreEnforcedWithoutPartialRows() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)

        // Fill the store to the workspace cap without 23 disk saves.
        for index in 1..<WorkspaceLimits.maximumWorkspaces {
            let workspace = Workspace(name: "场景 \(index)", emoji: "🗂", sortOrder: index,
                                      isGlobal: false, now: base)
            context.insert(workspace)
        }
        try context.save()
        #expect(throws: WorkspaceError.workspaceLimit) {
            try service.createWorkspace(name: "超限", emoji: "🗂", accent: .sage,
                                        filter: .unrestricted, preset: .blank)
        }

        let target = try #require(try service.scenarioWorkspaces().first)
        var modules: [WorkspaceModuleSnapshot] = []
        for index in 0..<WorkspaceLimits.maximumModulesPerWorkspace {
            modules.append(snapshot(kind: .focus, size: .medium, order: index))
        }
        try service.saveLayout(workspaceID: target.id, modules: modules, now: base)
        #expect(try service.fetchWorkspace(id: target.id)?.orderedModules.count
                == WorkspaceLimits.maximumModulesPerWorkspace)

        modules.append(snapshot(kind: .focus, size: .medium, order: modules.count))
        #expect(throws: WorkspaceError.moduleLimit) {
            try service.saveLayout(workspaceID: target.id, modules: modules, now: base)
        }
        #expect(try service.fetchWorkspace(id: target.id)?.orderedModules.count
                == WorkspaceLimits.maximumModulesPerWorkspace)
    }

    // MARK: - Modules

    @Test func moduleLifecycleAddsMovesResizesAndRemovesInOrder() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)
        let workspace = try service.createWorkspace(name: "模块", emoji: "🧩", accent: .sage,
                                                    filter: .unrestricted, preset: .blank, now: base)

        let focus = try service.addModule(to: workspace.id, kind: .focus, size: .medium, now: base)
        let inbox = try service.addModule(to: workspace.id, kind: .inbox, size: .small,
                                          now: base.addingTimeInterval(1))
        let month = try service.addModule(to: workspace.id, kind: .month, size: .large,
                                          now: base.addingTimeInterval(2))
        let sortOrders = [focus.sortOrder, inbox.sortOrder, month.sortOrder]
        #expect(sortOrders == [0, 1, 2])
        #expect(try service.fetchWorkspace(id: workspace.id)?.orderedModules.map(\.id)
                == [focus.id, inbox.id, month.id])

        #expect(throws: WorkspaceError.unsupportedSize) {
            try service.addModule(to: workspace.id, kind: .stats, size: .large)
        }
        #expect(throws: WorkspaceError.workspaceNotFound) {
            try service.addModule(to: UUID(), kind: .focus, size: .medium)
        }

        try service.moveModule(id: month.id, before: focus.id, in: workspace.id,
                               now: base.addingTimeInterval(3))
        #expect(try service.fetchWorkspace(id: workspace.id)?.orderedModules.map(\.id)
                == [month.id, focus.id, inbox.id])
        #expect(try service.fetchWorkspace(id: workspace.id)?.orderedModules.map(\.sortOrder)
                == [0, 1, 2])

        try service.moveModule(id: focus.id, toIndex: 99, in: workspace.id,
                               now: base.addingTimeInterval(4))
        #expect(try service.fetchWorkspace(id: workspace.id)?.orderedModules.map(\.id)
                == [month.id, inbox.id, focus.id])

        try service.setSize(.large, for: focus.id, now: base.addingTimeInterval(5))
        #expect(try service.fetchModule(id: focus.id)?.size == .large)
        #expect(throws: WorkspaceError.unsupportedSize) {
            try service.setSize(.small, for: month.id)
        }
        #expect(throws: WorkspaceError.moduleNotFound) {
            try service.setSize(.small, for: UUID())
        }

        try service.removeModule(id: inbox.id, from: workspace.id, now: base.addingTimeInterval(6))
        #expect(try service.fetchWorkspace(id: workspace.id)?.orderedModules.map(\.id)
                == [month.id, focus.id])
        #expect(try service.fetchWorkspace(id: workspace.id)?.orderedModules.map(\.sortOrder)
                == [0, 1])
        #expect(throws: WorkspaceError.moduleNotFound) {
            try service.removeModule(id: inbox.id, from: workspace.id)
        }

        let upcoming = try service.addModule(to: workspace.id, kind: .upcoming,
                                             size: .medium, now: base.addingTimeInterval(7))
        try service.updateUpcomingDays(7, for: upcoming.id, now: base.addingTimeInterval(8))
        #expect(try service.fetchModule(id: upcoming.id)?.config.days == 7)
        try service.updateUpcomingDays(5, for: upcoming.id, now: base.addingTimeInterval(9))
        #expect(try service.fetchModule(id: upcoming.id)?.config.days == 3)
        #expect(throws: WorkspaceError.unsupportedModule) {
            try service.updateUpcomingDays(7, for: focus.id)
        }
    }

    @Test func restoreDefaultLayoutIsGlobalOnlyAndKeepsWorkspaceIdentity() throws {
        let (container, context) = try make()
        _ = container
        let global = try seed(context)
        let service = WorkspaceService(context: context)
        let globalID = global.id
        let defaultCount = global.orderedModules.count

        try service.removeModule(id: global.orderedModules[0].id, from: global.id, now: base)
        #expect(try service.fetchWorkspace(id: globalID)?.orderedModules.count == defaultCount - 1)
        try service.restoreDefaultLayout(for: globalID, now: base.addingTimeInterval(10))
        let restored = try #require(try service.fetchWorkspace(id: globalID))
        #expect(restored.orderedModules.count == defaultCount)
        #expect(restored.orderedModules.compactMap(\.kind)
                == DefaultWorkspaceFactory.globalSpecs.map(\.kind))
        #expect(restored.id == globalID)

        let scenario = try service.createWorkspace(name: "场景", emoji: "🧪", accent: .sage,
                                                   filter: .unrestricted, preset: .blank, now: base)
        #expect(throws: WorkspaceError.onlyGlobalCanRestoreDefault) {
            try service.restoreDefaultLayout(for: scenario.id)
        }
    }

    // MARK: - Layout engine

    @Test func breakpointsMapEverySizeToDeterministicSpans() {
        #expect(WorkspaceLayoutEngine.columnCount(for: 0) == 1)
        #expect(WorkspaceLayoutEngine.columnCount(for: 839) == 1)
        #expect(WorkspaceLayoutEngine.columnCount(for: 840) == 2)
        #expect(WorkspaceLayoutEngine.columnCount(for: 1_179) == 2)
        #expect(WorkspaceLayoutEngine.columnCount(for: 1_180) == 3)
        #expect(WorkspaceLayoutEngine.columnCount(for: 8_000) == 3)

        let items = [
            ModuleLayoutItem(id: UUID(), size: .small),
            ModuleLayoutItem(id: UUID(), size: .medium),
            ModuleLayoutItem(id: UUID(), size: .large),
            ModuleLayoutItem(id: UUID(), size: .medium),
            ModuleLayoutItem(id: UUID(), size: .small),
            ModuleLayoutItem(id: UUID(), size: .large)
        ]

        let one = WorkspaceLayoutEngine.placements(for: items, columns: 1)
        #expect(one.map(\.span) == Array(repeating: 1, count: items.count))
        #expect(one.map(\.row) == Array(0..<items.count))
        #expect(one.map(\.column) == Array(repeating: 0, count: items.count))

        let two = WorkspaceLayoutEngine.placements(for: items, columns: 2)
        #expect(two.map(\.span) == [1, 1, 2, 1, 1, 2])
        #expect(two.map(\.row) == [0, 0, 1, 2, 2, 3])
        #expect(two.map(\.column) == [0, 1, 0, 0, 1, 0])

        let three = WorkspaceLayoutEngine.placements(for: items, columns: 3)
        #expect(three.map(\.span) == [1, 1, 3, 1, 1, 3])
        #expect(three.map(\.row) == [0, 0, 1, 2, 2, 3])
        #expect(three.map(\.column) == [0, 1, 0, 0, 1, 0])

        #expect(WorkspaceLayoutEngine.placements(for: items, columns: 2)
                == WorkspaceLayoutEngine.placements(for: items, columns: 2))
        #expect(WorkspaceLayoutEngine.rows(for: items, columns: 3).count == 4)
    }

    @Test func availableWidthPlacementsNeverOverlapOrOverflow() {
        let items = (0..<12).map { index in
            ModuleLayoutItem(id: UUID(), size: [ModuleSize.small, .medium, .large][index % 3])
        }
        for width in [320.0, 839.0, 840.0, 1_180.0, 1_500.0, 2_400.0] {
            let placements = WorkspaceLayoutEngine.placements(for: items, availableWidth: width)
            #expect(placements.count == items.count)
            #expect(Set(placements.map(\.id)).count == items.count)
            let content = WorkspaceLayoutEngine.contentWidth(for: width)
            #expect(placements.allSatisfy { $0.width > 0 && $0.x >= 0 })
            #expect(placements.allSatisfy { $0.x + $0.width <= content + 0.01 },
                    "width \(width) produced a module outside the board")
            let columns = WorkspaceLayoutEngine.columnCount(for: content)
            #expect(placements.allSatisfy { $0.column >= 0 && $0.span >= 1
                && $0.column + $0.span <= columns })
            for row in Set(placements.map(\.row)) {
                let ordered = placements.filter { $0.row == row }
                    .sorted { $0.column < $1.column }
                for index in 1..<ordered.count {
                    #expect(ordered[index - 1].column + ordered[index - 1].span
                            <= ordered[index].column,
                            "modules overlap at width \(width)")
                    #expect(ordered[index - 1].x + ordered[index - 1].width
                            <= ordered[index].x + 0.01,
                            "horizontal frames overlap at width \(width)")
                }
            }
        }
    }

    @Test func layoutRemainsDeterministicAndBoundedAtTenThirtyAndHundredModules() {
        let widths: [CGFloat] = [760, 1_000, 1_400]
        for count in [10, 30, 100] {
            let items = (0..<count).map { index in
                ModuleLayoutItem(id: UUID(), size: [ModuleSize.small, .medium, .large][index % 3])
            }
            for width in widths {
                let columns = WorkspaceLayoutEngine.columnCount(for: width)
                let first = WorkspaceLayoutEngine.placements(for: items, availableWidth: width)
                let second = WorkspaceLayoutEngine.placements(for: items, availableWidth: width)
                #expect(first == second)
                #expect(first.count == count)
                #expect(Set(first.map(\.id)).count == count)
                #expect(zip(items, first).allSatisfy { item, placement in
                    placement.column >= 0 && placement.span >= 1
                        && placement.column + placement.span <= columns
                        && placement.width > 0
                        && placement.x >= 0
                        && placement.x + placement.width <= width + 0.01
                        && placement.span == min(item.size.preferredSpan(columns: columns),
                                                 columns)
                })
                for row in Set(first.map(\.row)) {
                    let ordered = first.filter { $0.row == row }
                        .sorted { $0.column < $1.column }
                    for index in 1..<ordered.count {
                        #expect(ordered[index - 1].column + ordered[index - 1].span
                                <= ordered[index].column,
                                "modules overlap for \(count) modules at width \(width)")
                        #expect(ordered[index - 1].x + ordered[index - 1].width
                                <= ordered[index].x + 0.01,
                                "frames overlap for \(count) modules at width \(width)")
                    }
                }
            }
        }
    }

    // MARK: - Layout persistence and transactions

    @Test func saveLayoutPersistsOrderSizeScopeAndConfigInOneTransaction() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)
        let workspace = try service.createWorkspace(name: "布局", emoji: "🧱", accent: .slate,
                                                    filter: .unrestricted, preset: .blank, now: base)
        let focus = try service.addModule(to: workspace.id, kind: .focus, size: .medium, now: base)
        let month = try service.addModule(to: workspace.id, kind: .month, size: .medium,
                                          now: base.addingTimeInterval(1))

        let filter = TaskFilterExpression(
            statuses: [TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue],
            importances: [TaskImportance.high.rawValue],
            dateField: .planned, dateRange: .next3Days,
            plannedState: .has, searchText: "材料"
        )
        let config = WorkspaceModuleConfig(
            filter: filter, days: 7, limit: 12,
            sortRaw: TaskSortMode.dueDate.rawValue
        )
        let revisedFocus = snapshot(id: focus.id, kind: .focus, size: .large, order: 1,
                                    scope: .custom, config: config)
        let revisedMonth = snapshot(id: month.id, kind: .month, size: .medium, order: 0)
        try service.saveLayout(workspaceID: workspace.id,
                               modules: [revisedMonth, revisedFocus],
                               now: base.addingTimeInterval(20))

        let saved = try #require(try service.fetchWorkspace(id: workspace.id))
        #expect(saved.updatedAt == base.addingTimeInterval(20))
        #expect(saved.orderedModules.map(\.id) == [month.id, focus.id])
        #expect(saved.orderedModules.map(\.size) == [.medium, .large])
        #expect(saved.orderedModules[1].scope == .custom)
        #expect(saved.orderedModules[1].config == config.sanitized())
        #expect(saved.orderedModules[1].config.filter?.searchText == "材料")

        // A new snapshot may add a module and remove another in the same commit.
        let inbox = snapshot(kind: .inbox, size: .small, order: 0)
        try service.saveLayout(workspaceID: workspace.id,
                               modules: [inbox, revisedFocus],
                               now: base.addingTimeInterval(30))
        let replaced = try #require(try service.fetchWorkspace(id: workspace.id))
        #expect(replaced.orderedModules.count == 2)
        #expect(replaced.orderedModules[0].id == inbox.id)
        #expect(replaced.orderedModules[1].id == focus.id)
        #expect(try service.fetchModule(id: month.id) == nil)
    }

    @Test func saveLayoutRollsBackEveryMutationWhenValidationFails() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)
        let workspace = try service.createWorkspace(name: "回滚", emoji: "↩️", accent: .sage,
                                                    filter: .unrestricted, preset: .blank, now: base)
        let focus = try service.addModule(to: workspace.id, kind: .focus, size: .medium, now: base)
        let month = try service.addModule(to: workspace.id, kind: .month, size: .medium,
                                          now: base.addingTimeInterval(1))

        // The first snapshot is valid and stages a size change. The second refers
        // to a saved view that does not exist and must undo the whole draft.
        let changedFocus = snapshot(id: focus.id, kind: .focus, size: .large, order: 0)
        let brokenMonth = snapshot(id: month.id, kind: .month, size: .medium, order: 1,
                                   savedViewID: UUID())
        #expect(throws: WorkspaceError.savedViewNotFound) {
            try service.saveLayout(workspaceID: workspace.id,
                                   modules: [changedFocus, brokenMonth],
                                   now: base.addingTimeInterval(10))
        }
        let rolledBack = try #require(try service.fetchWorkspace(id: workspace.id))
        #expect(rolledBack.orderedModules.map(\.id) == [focus.id, month.id])
        #expect(rolledBack.orderedModules.map(\.size) == [.medium, .medium])
        #expect(rolledBack.orderedModules.allSatisfy { $0.savedViewID == nil })
        #expect(rolledBack.updatedAt == base.addingTimeInterval(1))

        // Duplicate and unknown identifiers fail before touching any row.
        let duplicated = [snapshot(id: focus.id, kind: .focus, size: .large, order: 0),
                          snapshot(id: focus.id, kind: .focus, size: .large, order: 1)]
        #expect(throws: WorkspaceError.duplicateModule) {
            try service.saveLayout(workspaceID: workspace.id, modules: duplicated)
        }
        #expect(throws: WorkspaceError.unsupportedSize) {
            try service.saveLayout(
                workspaceID: workspace.id,
                modules: [snapshot(id: focus.id, kind: .focus, size: .small, order: 0),
                          snapshot(id: month.id, kind: .month, size: .medium, order: 1)]
            )
        }
        #expect(try service.fetchWorkspace(id: workspace.id)?.orderedModules.count == 2)

        // The service remains usable after a rollback.
        try service.saveLayout(workspaceID: workspace.id,
                               modules: [changedFocus, snapshot(id: month.id, kind: .month,
                                                                size: .medium, order: 1)],
                               now: base.addingTimeInterval(20))
        #expect(try service.fetchModule(id: focus.id)?.size == .large)
    }

    @Test func unknownModuleTypesAndRawConfigSurviveCopyAndSave() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let service = WorkspaceService(context: context)
        let workspace = try service.createWorkspace(name: "未来", emoji: "🔮", accent: .plum,
                                                    filter: .unrestricted, preset: .blank, now: base)
        let rawConfig = Data(#"{"future":true,"columns":7,"filter":{"invented":1}}"#.utf8)
        let moduleID = UUID()
        let module = WorkspaceModule(id: moduleID, kindRaw: "futureWidget",
                                     sizeRaw: "galaxy", sortOrder: 0, scopeRaw: "edge",
                                     savedViewID: nil, configData: rawConfig, now: base)
        context.insert(module)
        module.workspace = workspace
        try context.save()

        let original = try #require(try service.fetchModule(id: moduleID))
        #expect(original.snapshot.isKnownKind == false)
        #expect(original.snapshot.title == "未知模块")
        #expect(original.snapshot.effectiveSize == .medium)

        // Simulate an edit-mode draft that cannot understand the module. Only the
        // logical position may change; every forward-compatible byte is retained.
        var draft = original.snapshot
        draft.sortOrder = 0
        draft.kindRaw = "futureWidget"
        draft.sizeRaw = "large"
        draft.scopeRaw = "custom"
        draft.config = WorkspaceModuleConfig(filter: .activeOnly, days: 7, limit: 2)
        draft.rawConfigData = Data("should-not-be-written".utf8)
        let known = snapshot(kind: .focus, size: .medium, order: 1)
        try service.saveLayout(workspaceID: workspace.id, modules: [draft, known],
                               now: base.addingTimeInterval(30))

        let persisted = try #require(try service.fetchModule(id: moduleID))
        #expect(persisted.sortOrder == 0)
        #expect(persisted.kindRaw == "futureWidget")
        #expect(persisted.sizeRaw == "galaxy")
        #expect(persisted.scopeRaw == "edge")
        #expect(persisted.configData == rawConfig)
        #expect(persisted.workspace?.id == workspace.id)

        let copy = try service.duplicateWorkspace(workspace, now: base.addingTimeInterval(40))
        let copied = try #require(copy.orderedModules.first)
        #expect(copied.id != moduleID)
        #expect(copied.kindRaw == "futureWidget")
        #expect(copied.sizeRaw == "galaxy")
        #expect(copied.scopeRaw == "edge")
        #expect(copied.configData == rawConfig)
        #expect(copy.orderedModules.count == 2)
    }

    @Test func layoutAndUnknownModuleConfigurationSurviveARealReopen() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase05Layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Selno.store")
        let workspaceID = UUID()
        let taskListID = UUID()
        let unknownID = UUID()
        let rawConfig = Data(#"{"version":9,"opaque":"保留"}"#.utf8)
        let filter = TaskFilterExpression(
            statuses: [TaskStatus.completed.rawValue],
            importances: [TaskImportance.low.rawValue],
            dateField: .due, dateRange: .thisMonth,
            dueState: .notOverdue, searchText: "复盘"
        )

        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext
            try WorkspaceSeeder.seedIfNeeded(in: context, now: base)
            let workspace = Workspace(id: workspaceID, name: "持久化", emoji: "💾",
                                      accent: .ocean, sortOrder: 1, isGlobal: false,
                                      filter: .activeOnly, now: base)
            context.insert(workspace)
            let taskList = WorkspaceModule(id: taskListID, kind: .taskList, size: .large,
                                           sortOrder: 0, scope: .custom,
                                           config: WorkspaceModuleConfig(filter: filter, days: 7,
                                                                         limit: 18,
                                                                         sortRaw: TaskSortMode.importance.rawValue),
                                           now: base)
            let unknown = WorkspaceModule(id: unknownID, kindRaw: "futureWidget", sizeRaw: "galaxy",
                                          sortOrder: 1, scopeRaw: "edge", savedViewID: nil,
                                          configData: rawConfig, now: base)
            context.insert(taskList)
            context.insert(unknown)
            taskList.workspace = workspace
            unknown.workspace = workspace
            try context.save()
        }

        try autoreleasepool {
            let container = try PersistenceController.makeContainer(storage: .disk(url))
            let context = container.mainContext
            // The app seeds on every launch; this must not disturb saved layouts.
            try WorkspaceSeeder.seedIfNeeded(in: context, now: base.addingTimeInterval(100))
            #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 2)
            let workspace = try #require(try WorkspaceService(context: context)
                .fetchWorkspace(id: workspaceID))
            #expect(workspace.name == "持久化")
            #expect(workspace.accent == .ocean)
            #expect(workspace.filter == TaskFilterExpression.activeOnly)
            #expect(workspace.orderedModules.map(\.id) == [taskListID, unknownID])
            let taskList = try #require(workspace.orderedModules.first)
            #expect(taskList.size == .large)
            #expect(taskList.scope == .custom)
            #expect(taskList.config == WorkspaceModuleConfig(
                filter: filter, days: 7, limit: 18,
                sortRaw: TaskSortMode.importance.rawValue
            ).sanitized())
            let unknown = try #require(workspace.orderedModules.last)
            #expect(unknown.kindRaw == "futureWidget")
            #expect(unknown.sizeRaw == "galaxy")
            #expect(unknown.scopeRaw == "edge")
            #expect(unknown.configData == rawConfig)
        }
    }

    // MARK: - Saved views

    @Test func savedViewLifecycleForcesCustomScopeAndDetachesOnDelete() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let workspaceService = WorkspaceService(context: context)
        let viewService = SavedViewService(context: context)
        let workspace = try workspaceService.createWorkspace(
            name: "视图", emoji: "🔎", accent: .sage,
            filter: .activeOnly, preset: .blank, now: base
        )
        let module = try workspaceService.addModule(to: workspace.id, kind: .taskList,
                                                    size: .medium, now: base)
        let viewFilter = TaskFilterExpression(
            statuses: [TaskStatus.completed.rawValue],
            importances: [TaskImportance.high.rawValue],
            projectIDs: [], tagIDs: [],
            dateField: .due, dateRange: .next7Days,
            searchText: "复盘"
        )
        let view = try viewService.create(name: "本周复盘", emoji: "🧭",
                                          colorHex: "#4f7a69", filter: viewFilter,
                                          sort: .dueDate, limit: 12, now: base)

        // Supplying a saved view overrides a requested inherit scope.
        try workspaceService.updateModule(
            id: module.id, size: .large, scope: .inherit,
            savedViewID: view.id,
            config: WorkspaceModuleConfig(filter: .activeOnly, limit: 4),
            now: base.addingTimeInterval(5)
        )
        let attached = try #require(try workspaceService.fetchModule(id: module.id))
        #expect(attached.savedViewID == view.id)
        #expect(attached.scope == .custom)
        #expect(attached.size == .large)

        let duplicate = try viewService.duplicate(view.id, now: base.addingTimeInterval(10))
        #expect(duplicate.id != view.id)
        #expect(duplicate.name == "本周复盘 副本")
        #expect(duplicate.filter == view.filter)
        #expect(duplicate.effectiveLimit == view.effectiveLimit)

        let task = TodoTask(title: "复盘任务", now: base)
        context.insert(task)
        try context.save()

        try viewService.delete(view.id, now: base.addingTimeInterval(20))
        let detached = try #require(try workspaceService.fetchModule(id: module.id))
        #expect(detached.savedViewID == nil)
        #expect(detached.scope == .inherit)
        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SavedTaskView>()) == 1)
        #expect(try viewService.fetch(view.id) == nil)
        #expect(throws: WorkspaceError.savedViewNotFound) {
            try viewService.delete(view.id)
        }
    }

    @Test func savedViewValidationAndMissingReferenceAreRejected() throws {
        let (container, context) = try make()
        _ = container
        _ = try seed(context)
        let workspaceService = WorkspaceService(context: context)
        let viewService = SavedViewService(context: context)
        let workspace = try workspaceService.createWorkspace(
            name: "视图校验", emoji: "🧪", accent: .sage,
            filter: .unrestricted, preset: .blank, now: base
        )
        let module = try workspaceService.addModule(to: workspace.id, kind: .taskList,
                                                    size: .medium, now: base)

        #expect(throws: WorkspaceError.emptyName) {
            try viewService.create(name: " ", emoji: "🔎", colorHex: "#123456",
                                   filter: .unrestricted, sort: .standard, limit: 8)
        }
        #expect(throws: WorkspaceError.self) {
            try viewService.create(name: "颜色", emoji: "🔎", colorHex: "red",
                                   filter: .unrestricted, sort: .standard, limit: 8)
        }
        #expect(throws: WorkspaceError.savedViewNotFound) {
            try workspaceService.updateModule(id: module.id, size: .medium, scope: .custom,
                                              savedViewID: UUID(),
                                              config: .default)
        }
        let unchanged = try #require(try workspaceService.fetchModule(id: module.id))
        #expect(unchanged.savedViewID == nil)
        #expect(unchanged.scope == .inherit)

        let view = try viewService.create(name: "有效视图", emoji: "✅", colorHex: "ABCDEF",
                                          filter: .activeOnly, sort: .updated, limit: 99,
                                          now: base)
        #expect(view.colorHex == "#ABCDEF")
        #expect(view.effectiveLimit == WorkspaceLimits.taskListLimitRange.upperBound)
        try viewService.update(view.id, name: "更新视图", emoji: "🔄", colorHex: "#00A1B2",
                               filter: .unrestricted, sort: .importance, limit: 0,
                               now: base.addingTimeInterval(10))
        let updated = try #require(try viewService.fetch(view.id))
        #expect(updated.name == "更新视图")
        #expect(updated.colorHex == "#00A1B2")
        #expect(updated.sort == .importance)
        #expect(updated.effectiveLimit == 1)
    }

    // MARK: - Filter resolution and query planning

    @Test func scopeResolutionInheritsGloballyOrUsesCustomRules() {
        let workspaceFilter = TaskFilterExpression.activeOnly
        let custom = TaskFilterExpression(
            statuses: [TaskStatus.completed.rawValue], importances: [TaskImportance.high.rawValue]
        )
        let moduleID = UUID()
        func module(scope: ModuleDataScope, savedViewID: UUID? = nil,
                    filter: TaskFilterExpression? = custom) -> WorkspaceModuleSnapshot {
            snapshot(id: moduleID, kind: .taskList, size: .medium, order: 0,
                     scope: scope, savedViewID: savedViewID,
                     config: WorkspaceModuleConfig(filter: filter))
        }

        let inherited = WorkspaceFilterResolver.resolve(
            module: module(scope: .inherit), workspace: workspaceFilter, savedViews: [:]
        )
        #expect(inherited.filter == workspaceFilter)
        #expect(inherited.source == .scenario)

        let global = WorkspaceFilterResolver.resolve(
            module: module(scope: .global), workspace: workspaceFilter, savedViews: [:]
        )
        #expect(global.filter.isUnrestricted)
        #expect(global.source == .global)

        let own = WorkspaceFilterResolver.resolve(
            module: module(scope: .custom), workspace: workspaceFilter, savedViews: [:]
        )
        #expect(own.filter == custom)
        #expect(own.source == .custom)

        let emptyCustom = WorkspaceFilterResolver.resolve(
            module: module(scope: .custom, filter: nil),
            workspace: workspaceFilter, savedViews: [:]
        )
        #expect(emptyCustom.filter.isUnrestricted)
        #expect(emptyCustom.source == .custom)

        let viewFilter = TaskFilterExpression(statuses: [TaskStatus.cancelled.rawValue])
        let view = SavedTaskViewSnapshot(
            id: UUID(), name: "已取消", emoji: "🔎", colorHex: "#4F7A69",
            filter: viewFilter, sortRaw: TaskSortMode.standard.rawValue, limit: 8,
            createdAt: base, updatedAt: base
        )
        let overridden = WorkspaceFilterResolver.resolve(
            module: module(scope: .inherit, savedViewID: view.id),
            workspace: workspaceFilter, savedViews: [view.id: view]
        )
        #expect(overridden.filter == viewFilter)
        #expect(overridden.source == .custom)

        // An unknown raw scope from a future build safely falls back to inherit.
        let raw = snapshot(kind: .taskList, size: .medium, order: 0, scope: .inherit)
        var future = raw
        future.scopeRaw = "futureScope"
        let fallback = WorkspaceFilterResolver.resolve(
            module: future, workspace: workspaceFilter, savedViews: [:]
        )
        #expect(fallback.filter == workspaceFilter)
        #expect(fallback.source == .scenario)
    }

    @Test func boardQueryPlanUnionsVisibleWindowsAndClampsExtremeRanges() throws {
        let (container, context) = try make()
        _ = container
        let global = try seed(context)
        let service = WorkspaceService(context: context)
        let today = calendar.startOfDay(for: base)
        let lookback = try #require(calendar.date(byAdding: .day,
                                                  value: -WorkspaceLimits.queryLookbackDays,
                                                  to: today))
        let lookahead = try #require(calendar.date(byAdding: .day,
                                                   value: WorkspaceLimits.queryLookaheadDays,
                                                   to: today))

        // Ten years of custom range must never turn into a ten-year fetch.
        let extreme = TaskFilterExpression(
            dateField: .due, dateRange: .custom,
            customStart: calendar.date(byAdding: .year, value: -5, to: today),
            customEnd: calendar.date(byAdding: .year, value: 5, to: today)
        )
        try service.updateWorkspace(global.id, name: global.name, emoji: global.emoji,
                                    accent: global.accent, filter: extreme, now: base)
        let snapshot = try #require(try service.persistedSnapshot(workspaceID: global.id))
        let plan = WorkspaceBoardQueryPlan.make(workspace: snapshot, savedViews: [],
                                                now: base, calendar: calendar)

        #expect(plan.day == today)
        #expect(plan.range.start >= lookback)
        #expect(plan.range.end <= lookahead)
        #expect(plan.range.start < plan.range.end)
        #expect(plan.range.duration <= Double(WorkspaceLimits.maximumQuerySpanDays) * 86_400 + 1)
        #expect(plan.signature == snapshot.layoutSignature + "|")
        #expect(plan.monthWindow.range.contains(today))

        // An empty board asks only for today, not the whole store.
        let empty = try service.createWorkspace(name: "空白", emoji: "⬜️", accent: .sage,
                                                filter: .unrestricted, preset: .blank, now: base)
        let emptyPlan = WorkspaceBoardQueryPlan.make(
            workspace: try #require(try service.persistedSnapshot(workspaceID: empty.id)),
            savedViews: [], now: base, calendar: calendar
        )
        #expect(emptyPlan.range.start == today)
        #expect(emptyPlan.range.end > emptyPlan.range.start)

        // Unknown modules cannot widen the plan even if their raw config claims a
        // huge range; only known module kinds contribute.
        let futureConfig = WorkspaceModuleConfig(
            filter: TaskFilterExpression(dateRange: .custom,
                                         customStart: Date(timeIntervalSince1970: 0),
                                         customEnd: lookahead.addingTimeInterval(10 * 365 * 86_400)),
            days: 7, limit: 3
        )
        let future = WorkspaceModule(id: UUID(), kindRaw: "futureWidget", sizeRaw: "galaxy",
                                     sortOrder: 0, scopeRaw: "custom", savedViewID: nil,
                                     configData: futureConfig.encoded(), now: base)
        context.insert(future)
        future.workspace = empty
        try context.save()
        let futurePlan = WorkspaceBoardQueryPlan.make(
            workspace: try #require(try service.persistedSnapshot(workspaceID: empty.id)),
            savedViews: [], now: base, calendar: calendar
        )
        #expect(futurePlan.range.start == today)
    }

    @Test func statisticsAndInboxUseTheSameFilteredUniverse() throws {
        let (container, context) = try make()
        _ = container
        _ = context
        let today = calendar.startOfDay(for: base)
        let overdue = TodoTask(title: "逾期", now: base)
        overdue.dueAt = calendar.date(byAdding: .day, value: -1, to: today)
        let soon = TodoTask(title: "临近", status: .inProgress, now: base)
        soon.dueAt = calendar.date(byAdding: .day, value: 2, to: today)
        let noDue = TodoTask(title: "无截止", now: base)
        let completedToday = TodoTask(title: "今日完成", status: .completed, now: base)
        completedToday.completedAt = base
        let completedBefore = TodoTask(title: "旧完成", status: .completed, now: base)
        completedBefore.completedAt = calendar.date(byAdding: .day, value: -2, to: today)

        let stats = WorkspaceTaskStatistics.make(
            tasks: [overdue, soon, noDue, completedToday, completedBefore],
            now: base, calendar: calendar
        )
        #expect(stats.pending == 3)
        #expect(stats.completedToday == 1)
        #expect(stats.overdue == 1)
        #expect(stats.dueSoon == 1)

        let inbox = TodoTask(title: "收件箱", now: base)
        let planned = TodoTask(title: "已安排", now: base)
        planned.plannedAt = today
        let project = TodoProject(name: "项目", now: base)
        let assigned = TodoTask(title: "有项目", now: base)
        assigned.project = project
        let archived = TodoTask(title: "归档", now: base)
        archived.archivedAt = base
        let tasks = [inbox, planned, assigned, archived]
        let filter = TaskFilterExpression.unrestricted
        let expectation = tasks.filter {
            filter.matches($0, now: base, calendar: calendar) && $0.isInInbox && $0.status.isActive
        }
        #expect(expectation.map(\.id) == [inbox.id])
    }

    @Test func knownModuleConfigRetainsFutureKeysAcrossNormalizeUpdateAndSave() throws {
        let (container, context) = try make()
        _ = container
        let service = WorkspaceService(context: context)
        let workspace = try service.createWorkspace(name: "未来配置", emoji: "🧩",
                                                    accent: .sage,
                                                    filter: .unrestricted,
                                                    preset: .blank, now: base)
        let raw = Data(#"{"days":3,"limit":8,"sortRaw":"standard","future":{"columns":4},"note":"保留"}"#.utf8)
        let module = WorkspaceModule(kind: .taskList, size: .medium, sortOrder: 0, now: base)
        context.insert(module)
        module.workspace = workspace
        module.configData = raw
        try context.save()

        // A valid config is left byte-for-byte alone by the launch sanitizer.
        #expect(try WorkspaceSanitizer.normalize(in: context,
                                                now: base.addingTimeInterval(10)) == false)
        #expect(try #require(try service.fetchModule(id: module.id)).configData == raw)

        // Editing known fields preserves keys this build does not understand.
        var config = WorkspaceModuleConfig.decode(from: raw)
        config.limit = 42
        try service.updateModule(id: module.id, size: .large, scope: .inherit,
                                 savedViewID: nil, config: config,
                                 now: base.addingTimeInterval(20))
        let updated = try #require(try service.fetchModule(id: module.id))
        let updatedData = try #require(updated.configData)
        let updatedObject = try #require(
            try JSONSerialization.jsonObject(with: updatedData) as? [String: Any]
        )
        #expect(updatedObject["future"] != nil)
        #expect(updatedObject["note"] as? String == "保留")
        #expect(updatedObject["limit"] as? Int == 42)
        #expect(updated.config.limit == 42)

        // Saving a layout draft also keeps the future payload when only order or
        // size changes.
        var draft = updated.snapshot
        draft.sizeRaw = ModuleSize.large.rawValue
        draft.config = config
        draft.rawConfigData = updatedData
        try service.saveLayout(workspaceID: workspace.id, modules: [draft],
                               now: base.addingTimeInterval(30))
        let saved = try #require(try service.fetchModule(id: module.id))
        let savedData = try #require(saved.configData)
        let savedObject = try #require(
            try JSONSerialization.jsonObject(with: savedData) as? [String: Any]
        )
        #expect(savedObject["future"] != nil)
        #expect(savedObject["note"] as? String == "保留")
        #expect(saved.sizeRaw == ModuleSize.large.rawValue)

        // Invalid known values are repaired at launch, but unknown keys remain.
        let invalid = Data(#"{"days":3,"limit":999,"sortRaw":"standard","future":true}"#.utf8)
        saved.configData = invalid
        try context.save()
        #expect(try WorkspaceSanitizer.normalize(in: context,
                                                now: base.addingTimeInterval(40)) == true)
        let repaired = try #require(try service.fetchModule(id: module.id))
        let repairedData = try #require(repaired.configData)
        let repairedObject = try #require(
            try JSONSerialization.jsonObject(with: repairedData) as? [String: Any]
        )
        #expect(repairedObject["limit"] as? Int == WorkspaceLimits.taskListLimitRange.upperBound)
        #expect(repairedObject["future"] as? Bool == true)

        // An unknown raw size on a known kind must be repaired to a supported
        // value instead of staying hidden behind the `.medium` display fallback.
        repaired.sizeRaw = "galaxy"
        try context.save()
        #expect(try WorkspaceSanitizer.normalize(in: context,
                                                now: base.addingTimeInterval(45)) == true)
        #expect(repaired.sizeRaw == ModuleSize.medium.rawValue)
    }

    @Test func workspaceFilterRetainsFutureKeysAcrossNormalizeAndEdit() throws {
        let (container, context) = try make()
        _ = container
        let workspace = try seed(context)
        let raw = Data(#"{"statuses":[],"importances":[],"projectIDs":[],"includeUnassignedProject":false,"tagIDs":[],"dateField":"any","dateRange":"any","dueState":"any","plannedState":"any","includeArchived":false,"searchText":"","future":{"mode":2}}"#.utf8)
        workspace.filterData = raw
        try context.save()

        #expect(try WorkspaceSanitizer.normalize(in: context,
                                                now: base.addingTimeInterval(50)) == false)
        #expect(workspace.filterData == raw)

        var filter = workspace.filter
        filter.searchText = "未来"
        workspace.filter = filter
        try context.save()

        let data = try #require(workspace.filterData)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["searchText"] as? String == "未来")
        #expect((object["future"] as? [String: Any])?["mode"] as? Int == 2)
    }

    @Test func cancelledTasksWithoutDatesRemainInTheBoardUniverse() throws {
        let (container, context) = try make()
        _ = container
        let cancelled = TodoTask(title: "已取消", status: .cancelled, now: base)
        let archived = TodoTask(title: "已归档", status: .cancelled, now: base)
        archived.archivedAt = base
        context.insert(cancelled)
        context.insert(archived)
        try context.save()

        let active = try context.fetch(WorkspaceDataQuery.activeTasks())
        #expect(active.map(\.id) == [cancelled.id])
        let filter = TaskFilterExpression(statuses: [TaskStatus.cancelled.rawValue])
        #expect(active.filter { filter.matches($0, now: base, calendar: calendar) }
            .map(\.id) == [cancelled.id])
    }
}