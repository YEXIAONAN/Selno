import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Board

/// Entry point for both the upgraded global overview and user scenarios.
///
/// The outer view owns edit state and draft layout. Normal content lives in a
/// query host keyed by the board's query plan, so a saved layout change reloads
/// exactly once while a drag or a size change never writes to the store. Edit
/// mode renders only layout previews and performs one transactional save when
/// the user chooses 完成.
struct WorkspaceBoardView: View {
    let workspaceID: UUID?
    let calendar: Calendar
    let brand: BrandTypingState
    let openCalendar: (Date) -> Void
    let navigate: (AppSection) -> Void
    let openProject: (UUID) -> Void
    let onWorkspaceDeleted: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Workspace.sortOrder) private var workspaces: [Workspace]
    @Query(sort: \SavedTaskView.name) private var savedViews: [SavedTaskView]

    @State private var isEditing = false
    @State private var draft: [WorkspaceModuleSnapshot] = []
    @State private var draggedModuleID: UUID?
    @State private var configTarget: WorkspaceModuleTarget?
    @State private var catalogPresented = false
    @State private var editorRequest: WorkspaceEditorRequest?
    @State private var restoreConfirmation = false
    @State private var presentedError: PresentedError?

    private var workspace: Workspace? {
        if let workspaceID {
            return workspaces.first { $0.id == workspaceID }
        }
        return workspaces.first(where: \.isGlobal)
    }

    private var savedViewSnapshots: [SavedTaskViewSnapshot] {
        savedViews.map(\.snapshot)
    }

    var body: some View {
        Group {
            if let workspace {
                board(for: workspace)
                    .navigationTitle(workspace.isGlobal ? "总览" : workspace.name)
            } else {
                missingWorkspace
                    .navigationTitle("总览")
            }
        }
        .onChange(of: workspace?.id) { _, _ in
            // Edit mode is strictly per workspace. Switching in the sidebar must
            // never carry a draft or a drag session into another scenario.
            isEditing = false
            draft = []
            draggedModuleID = nil
            configTarget = nil
            catalogPresented = false
        }
        .sheet(item: $configTarget) { target in
            ModuleConfigurationView(moduleID: target.id, draft: $draft)
        }
        .sheet(isPresented: $catalogPresented) {
            if let workspace {
                ModuleCatalogView(isGlobal: workspace.isGlobal) { kind in
                    appendModule(kind)
                    catalogPresented = false
                }
            }
        }
        .sheet(item: $editorRequest) { request in
            WorkspaceEditorView(workspaceID: request.id,
                                onDeleted: {
                                    editorRequest = nil
                                    onWorkspaceDeleted()
                                })
        }
        .confirmationDialog("恢复全局工作台的默认布局？",
                            isPresented: $restoreConfirmation, titleVisibility: .visible) {
            Button("恢复默认布局", role: .destructive) { restoreDraftLayout() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会替换工作台当前的模块布局；任务、项目、标签与日程不会被删除。取消编辑仍可放弃这次更改。")
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message),
                  dismissButton: .default(Text("好")))
        }
    }

    @ViewBuilder
    private func board(for workspace: Workspace) -> some View {
        let snapshot = workspace.snapshot
        if isEditing {
            WorkspaceEditBoard(
                workspace: snapshot,
                draft: $draft,
                draggedModuleID: $draggedModuleID,
                savedViews: Dictionary(uniqueKeysWithValues: savedViewSnapshots.map { ($0.id, $0) }),
                reduceMotion: reduceMotion,
                onAdd: { catalogPresented = true },
                onConfigure: { configTarget = WorkspaceModuleTarget(id: $0) },
                onCancel: cancelEditing,
                onDone: saveDraft,
                onRestore: { restoreConfirmation = true },
                onManage: { editorRequest = WorkspaceEditorRequest(id: workspace.id) }
            )
        } else {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let plan = WorkspaceBoardQueryPlan.make(
                    workspace: snapshot,
                    savedViews: savedViewSnapshots,
                    now: now,
                    calendar: calendar
                )
                WorkspaceBoardQueryHost(
                    plan: plan,
                    workspace: snapshot,
                    savedViews: savedViewSnapshots,
                    now: now,
                    calendar: calendar,
                    brand: brand,
                    openCalendar: openCalendar,
                    navigate: navigate,
                    openProject: openProject,
                    onCustomize: beginEditing,
                    onManage: { editorRequest = WorkspaceEditorRequest(id: workspace.id) }
                )
                .id(plan.identity)
            }
        }
    }

    private var missingWorkspace: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("工作台已不存在", systemImage: "rectangle.on.rectangle.slash")
                .font(.title3.weight(.semibold))
            Text("它可能已被删除，或来自另一份尚未恢复的数据备份。任务与项目不会因此丢失。")
                .font(.callout).foregroundStyle(.secondary)
            Button("返回全局工作台", action: onWorkspaceDeleted)
                .buttonStyle(SelnoButtonStyle(primary: true))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WorkspaceStyle.canvas)
    }

    // MARK: Editing

    private func beginEditing() {
        isEditing = true
        draft = (workspace?.orderedModules ?? []).map(\.snapshot)
        draggedModuleID = nil
    }

    private func cancelEditing() {
        isEditing = false
        draft = []
        draggedModuleID = nil
    }

    private func saveDraft() {
        guard let workspace else { return }
        do {
            try WorkspaceService(context: context).saveLayout(
                workspaceID: workspace.id,
                modules: draft
            )
            isEditing = false
            draft = []
            draggedModuleID = nil
        } catch {
            // The service rolled the context back. The draft stays visible so the
            // user can retry or cancel instead of losing their layout work.
            presentedError = PresentedError("无法保存工作台布局", error: error)
        }
    }

    private func appendModule(_ kind: WorkspaceModuleKind) {
        guard let descriptor = WorkspaceModuleRegistry.descriptor(for: kind) else { return }
        guard draft.count < WorkspaceLimits.maximumModulesPerWorkspace else {
            presentedError = PresentedError("无法添加模块", error: WorkspaceError.moduleLimit)
            return
        }
        let now = Date.now
        let config = descriptor.defaultConfig.sanitized()
        let module = WorkspaceModuleSnapshot(
            id: UUID(),
            kindRaw: kind.rawValue,
            sizeRaw: descriptor.defaultSize.rawValue,
            sortOrder: draft.count,
            scopeRaw: ModuleDataScope.inherit.rawValue,
            savedViewID: nil,
            config: config,
            rawConfigData: config.encoded(),
            createdAt: now,
            updatedAt: now
        )
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            draft.append(module)
        }
    }

    private func restoreDraftLayout() {
        let now = Date.now
        draft = DefaultWorkspaceFactory.globalSpecs.enumerated().map { index, spec in
            let config = spec.config.sanitized()
            return WorkspaceModuleSnapshot(
                id: UUID(),
                kindRaw: spec.kind.rawValue,
                sizeRaw: spec.size.rawValue,
                sortOrder: index,
                scopeRaw: ModuleDataScope.inherit.rawValue,
                savedViewID: nil,
                config: config,
                rawConfigData: config.encoded(),
                createdAt: now,
                updatedAt: now
            )
        }
    }
}

// MARK: - Query host

private struct WorkspaceBoardQueryHost: View {
    @Environment(\.modelContext) private var context
    @Query private var activeTasks: [TodoTask]
    @Query private var windowTasks: [TodoTask]
    @Query private var recentCompleted: [TodoTask]
    @Query private var archivedTasks: [TodoTask]
    @Query private var events: [CalendarEvent]
    @Query private var milestones: [TaskMilestone]
    @Query private var projects: [TodoProject]
    @Query private var tags: [TaskCategory]

    let plan: WorkspaceBoardQueryPlan
    let workspace: WorkspaceSnapshot
    let savedViews: [SavedTaskViewSnapshot]
    let now: Date
    let calendar: Calendar
    let brand: BrandTypingState
    let openCalendar: (Date) -> Void
    let navigate: (AppSection) -> Void
    let openProject: (UUID) -> Void
    let onCustomize: () -> Void
    let onManage: () -> Void

    @State private var selection: AgendaSelection?
    @State private var creation: WorkspaceBoardCreation?
    @State private var presentedError: PresentedError?

    init(
        plan: WorkspaceBoardQueryPlan,
        workspace: WorkspaceSnapshot,
        savedViews: [SavedTaskViewSnapshot],
        now: Date,
        calendar: Calendar,
        brand: BrandTypingState,
        openCalendar: @escaping (Date) -> Void,
        navigate: @escaping (AppSection) -> Void,
        openProject: @escaping (UUID) -> Void,
        onCustomize: @escaping () -> Void,
        onManage: @escaping () -> Void
    ) {
        self.plan = plan
        self.workspace = workspace
        self.savedViews = savedViews
        self.now = now
        self.calendar = calendar
        self.brand = brand
        self.openCalendar = openCalendar
        self.navigate = navigate
        self.openProject = openProject
        self.onCustomize = onCustomize
        self.onManage = onManage

        _activeTasks = Query(WorkspaceDataQuery.activeTasks())
        _windowTasks = Query(CalendarDataQuery.tasks(in: plan.range))
        let cutoff = calendar.date(byAdding: .day, value: -WorkspaceLimits.queryLookbackDays, to: plan.day) ?? plan.day
        _recentCompleted = Query(WorkspaceDataQuery.completed(since: cutoff))
        _archivedTasks = Query(WorkspaceDataQuery.archived(since: cutoff))
        _events = Query(CalendarDataQuery.events(in: plan.range))
        _milestones = Query(CalendarDataQuery.milestones(in: plan.range))
        _projects = Query(WorkspaceDataQuery.projects())
        _tags = Query(WorkspaceDataQuery.tags())
    }

    private var savedViewMap: [UUID: SavedTaskViewSnapshot] {
        Dictionary(uniqueKeysWithValues: savedViews.map { ($0.id, $0) })
    }

    var body: some View {
        let data = WorkspaceBoardData(
            plan: plan,
            activeTasks: activeTasks,
            windowTasks: windowTasks,
            recentCompleted: recentCompleted,
            archivedTasks: archivedTasks,
            events: events,
            milestones: milestones,
            projects: projects,
            tags: tags,
            now: now,
            calendar: calendar
        )
        let projection = data.projection(filter: workspace.filter, days: 3)
        let filterSummary = workspace.filter.summary(projectNames: data.projectNames, tagNames: data.tagNames)
        let actions = makeActions()

        GeometryReader { geometry in
            let available = WorkspaceLayoutEngine.contentWidth(for: max(0, geometry.size.width - 52))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WorkspaceBoardHeader(
                        workspace: workspace,
                        now: now,
                        calendar: calendar,
                        brand: brand,
                        projection: projection,
                        filterSummary: filterSummary,
                        onCustomize: onCustomize,
                        onManage: onManage,
                        onOpenCalendar: { openCalendar(now) }
                    )
                    if workspace.orderedModules.isEmpty {
                        emptyBoard
                    } else {
                        WorkspaceBoardLayout(
                            workspace: workspace,
                            modules: workspace.orderedModules,
                            savedViews: savedViewMap,
                            data: data,
                            availableWidth: available,
                            isGlobal: workspace.isGlobal,
                            actions: actions
                        )
                    }
                }
                .padding(26)
                .frame(maxWidth: WorkspaceLayoutEngine.maximumBoardWidth)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(WorkspaceStyle.canvas)
            // Without an explicit container SwiftUI copies this identifier onto
            // every descendant that has no identifier of its own, which hides
            // the header, quick-action and module identifiers from UI tests and
            // merges unrelated controls into one VoiceOver element.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(workspace.isGlobal ? "dashboard.workspace" : "workspace.board.\(workspace.id.uuidString)")
        }
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建任务") { creation = .task }
                        .keyboardShortcut("n", modifiers: .command)
                    Button("从模板创建任务") { creation = .task }
                    Button("新建日程") { creation = .event }
                    Button("新建项目") { creation = .project }
                    Divider()
                    Button("自定义工作台") { onCustomize() }
                    Button("管理工作台") { onManage() }
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .accessibilityIdentifier(workspace.isGlobal ? "dashboard.new" : "workspace.new")
            }
        }
        .sheet(item: $selection) { AgendaDetailsSheet(selection: $0, calendar: calendar) }
        .sheet(item: $creation) { kind in
            switch kind {
            case .task:
                // Keep the pre-Phase-05 overview behavior: a task created from
                // the dashboard starts planned today, so it appears in 今日聚焦
                // and can be completed there. Scenarios share the same action.
                TaskEditorView(plannedDate: now, calendar: calendar)
            case .event: CalendarEventEditorView(date: now, calendar: calendar)
            case .project: ProjectEditorView()
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message),
                  dismissButton: .default(Text("好")))
        }
    }

    private var emptyBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("这个工作台还没有模块", systemImage: "square.dashed")
                .font(.title3.weight(.semibold))
            Text("进入自定义模式，从模块目录添加今日聚焦、任务视图或日历。业务数据不会被复制到场景中。")
                .font(.callout).foregroundStyle(.secondary)
            Button("自定义工作台", action: onCustomize)
                .buttonStyle(SelnoButtonStyle(primary: true))
                .accessibilityIdentifier("workspace.empty.customize")
        }
        .padding(.vertical, 28)
    }

    private func makeActions() -> WorkspaceBoardActions {
        WorkspaceBoardActions(
            openTask: { selection = .task($0) },
            openEvent: { selection = .event($0) },
            toggleTask: toggle,
            quickAddInbox: quickAdd,
            openToday: { navigate(.today) },
            openInbox: { navigate(.inbox) },
            openAllTasks: { navigate(.all) },
            openProjects: { navigate(.projects) },
            openCalendarDay: openCalendar,
            openProject: openProject,
            createTask: { creation = .task },
            createFromTemplate: { creation = .task },
            createEvent: { creation = .event },
            createProject: { creation = .project }
        )
    }

    private func toggle(_ task: TodoTask) {
        do { try TaskService(context: context).toggleCompletion(task) }
        catch { presentedError = PresentedError("无法更新任务", error: error) }
    }

    private func quickAdd(_ title: String) -> Bool {
        do {
            try TaskService(context: context).createTask(title: title)
            return true
        } catch {
            presentedError = PresentedError("无法创建任务", error: error)
            return false
        }
    }
}

private enum WorkspaceBoardCreation: String, Identifiable {
    case task, event, project
    var id: String { rawValue }
}

// MARK: - Header

private struct WorkspaceBoardHeader: View {
    let workspace: WorkspaceSnapshot
    let now: Date
    let calendar: Calendar
    let brand: BrandTypingState
    let projection: DashboardProjection
    let filterSummary: String
    let onCustomize: () -> Void
    let onManage: () -> Void
    let onOpenCalendar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Text(CalendarMath.fullDate(now, calendar: calendar))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !workspace.isGlobal {
                            Text("·").foregroundStyle(.tertiary)
                            Text("\(workspace.emoji) \(workspace.name)")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if workspace.isGlobal {
                        BrandHeadline(state: brand)
                    } else {
                        Text(workspace.name)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .tracking(-0.5)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("workspace.heading")
                    }
                }
                Spacer(minLength: 12)
                Menu {
                    Button("自定义工作台", action: onCustomize)
                    Button("管理工作台", action: onManage)
                } label: {
                    Label("工作台", systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("workspace.manage")
                Button { onOpenCalendar() } label: {
                    Label("打开日历", systemImage: "arrow.up.right")
                }
                .buttonStyle(SelnoButtonStyle())
                .accessibilityIdentifier(workspace.isGlobal ? "dashboard.openCalendar" : "workspace.openCalendar")
            }
            HStack(spacing: 18) {
                metric("待办", count: projection.focus.count, symbol: "circle.dashed")
                metric("日程", count: projection.todayEvents.count, symbol: "calendar")
                if projection.overdueCount > 0 {
                    metric("逾期", count: projection.overdueCount, symbol: "exclamationmark.circle", urgent: true)
                }
                if !workspace.isGlobal {
                    Label("场景筛选", systemImage: "square.stack.3d.up")
                        .font(.caption).foregroundStyle(SelnoDesign.secondary)
                        .help(filterSummary)
                        // Collapse the icon and text into one element so the
                        // summary reaches both VoiceOver and UI tests instead
                        // of leaving a child static text with only the title.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("场景筛选：\(filterSummary)")
                        .accessibilityIdentifier("workspace.filter.source")
                } else if !workspace.filter.isUnrestricted {
                    Label("全局筛选", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption).foregroundStyle(SelnoDesign.secondary)
                        .help(filterSummary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("全局筛选：\(filterSummary)")
                        .accessibilityIdentifier("workspace.filter.source")
                }
                Spacer(minLength: 0)
                Button("自定义布局", action: onCustomize)
                    .buttonStyle(.link).font(.caption)
                    .accessibilityIdentifier("workspace.customize")
            }
        }
    }

    private func metric(_ title: String, count: Int, symbol: String, urgent: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
            Text(title)
        }
        .font(.subheadline)
        .foregroundStyle(urgent ? SelnoDesign.warning : SelnoDesign.secondary)
    }
}

// MARK: - Normal layout

private struct WorkspaceBoardLayout: View {
    let workspace: WorkspaceSnapshot
    let modules: [WorkspaceModuleSnapshot]
    let savedViews: [UUID: SavedTaskViewSnapshot]
    let data: WorkspaceBoardData
    let availableWidth: CGFloat
    let isGlobal: Bool
    let actions: WorkspaceBoardActions

    var body: some View {
        let items = modules.map { ModuleLayoutItem(id: $0.id, size: $0.effectiveSize) }
        let columns = WorkspaceLayoutEngine.columnCount(for: availableWidth)
        let rows = WorkspaceLayoutEngine.rows(for: items, columns: columns)
        let lookup = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: WorkspaceLayoutEngine.spacing) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: WorkspaceLayoutEngine.spacing) {
                    ForEach(row.entries) { entry in
                        if let module = lookup[entry.id] {
                            let width = WorkspaceLayoutEngine.entryWidth(
                                span: entry.span, columns: columns,
                                availableWidth: availableWidth
                            )
                            WorkspaceCard(emphasis: module.kind == .focus) {
                                WorkspaceModuleContentView(
                                    module: module,
                                    workspaceFilter: workspace.filter,
                                    savedViews: savedViews,
                                    data: data,
                                    showsHeading: true,
                                    isGlobal: isGlobal,
                                    actions: actions
                                )
                            }
                            .frame(width: width)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("workspace.module.\(module.id.uuidString)")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Edit board

private struct WorkspaceEditBoard: View {
    let workspace: WorkspaceSnapshot
    @Binding var draft: [WorkspaceModuleSnapshot]
    @Binding var draggedModuleID: UUID?
    let savedViews: [UUID: SavedTaskViewSnapshot]
    let reduceMotion: Bool
    let onAdd: () -> Void
    let onConfigure: (UUID) -> Void
    let onCancel: () -> Void
    let onDone: () -> Void
    let onRestore: () -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            editBar
            Divider()
            GeometryReader { geometry in
                let width = WorkspaceLayoutEngine.contentWidth(for: max(0, geometry.size.width - 52))
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("拖动左侧手柄调整顺序；尺寸和筛选在完成时一次性保存。正常浏览时不显示这些控件。")
                            .font(.caption).foregroundStyle(SelnoDesign.secondary)
                        if draft.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("空工作台", systemImage: "square.dashed").font(.headline)
                                Text("添加第一个模块，或取消并返回浏览。")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("打开模块目录", action: onAdd)
                                    .buttonStyle(SelnoButtonStyle(primary: true))
                                    .accessibilityIdentifier("workspace.edit.emptyAdd")
                            }
                            .padding(.vertical, 22)
                        } else {
                            editLayout(width: width)
                            endDropZone
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: WorkspaceLayoutEngine.maximumBoardWidth)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .background(WorkspaceStyle.canvas)
        // Keep the board's own identifier on a real accessibility container;
        // otherwise the edit bar, cards and drag handles all inherit it and
        // their child identifiers become unreachable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.editBoard")
    }

    private var editBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Label("自定义工作台", systemImage: "rectangle.3.group")
                    .font(.headline)
                Text("\(workspace.emoji) \(workspace.name) · \(draft.count) / \(WorkspaceLimits.maximumModulesPerWorkspace) 个模块")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Label("添加模块", systemImage: "plus")
            }
            .buttonStyle(SelnoButtonStyle())
            .disabled(draft.count >= WorkspaceLimits.maximumModulesPerWorkspace)
            .accessibilityIdentifier("workspace.edit.add")
            Menu {
                Button("管理工作台…", action: onManage)
                if workspace.isGlobal {
                    Divider()
                    Button("恢复默认布局…", action: onRestore)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("workspace.edit.more")
            Button("取消", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("workspace.edit.cancel")
            Button("完成", action: onDone)
                .buttonStyle(SelnoButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("workspace.edit.done")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .background(SelnoDesign.surface)
    }

    private func editLayout(width: CGFloat) -> some View {
        let items = draft.map { ModuleLayoutItem(id: $0.id, size: $0.effectiveSize) }
        let columns = WorkspaceLayoutEngine.columnCount(for: width)
        let rows = WorkspaceLayoutEngine.rows(for: items, columns: columns)
        let lookup = Dictionary(uniqueKeysWithValues: draft.enumerated().map { ($0.element.id, ($0.offset, $0.element)) })
        return VStack(alignment: .leading, spacing: WorkspaceLayoutEngine.spacing) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: WorkspaceLayoutEngine.spacing) {
                    ForEach(row.entries) { entry in
                        if let (index, module) = lookup[entry.id] {
                            let cardWidth = WorkspaceLayoutEngine.entryWidth(
                                span: entry.span, columns: columns,
                                availableWidth: width
                            )
                            WorkspaceEditModuleCard(
                                module: module,
                                index: index,
                                count: draft.count,
                                savedViewName: module.savedViewID.flatMap { savedViews[$0]?.name },
                                draggedModuleID: $draggedModuleID,
                                onMoveBefore: { source, target in
                                    move(source, before: target)
                                },
                                onMoveToIndex: { id, destination in
                                    move(id, to: destination)
                                },
                                onSize: { id, size in setSize(id, size) },
                                onConfigure: { onConfigure($0) },
                                onRemove: remove
                            )
                            .frame(width: cardWidth)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: draft.map(\.id))
    }

    private var endDropZone: some View {
        HStack {
            Image(systemName: "arrow.down.to.line")
            Text("拖到这里放到最后")
        }
        .font(.caption)
        .foregroundStyle(draggedModuleID == nil ? SelnoDesign.tertiary : SelnoDesign.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(draggedModuleID == nil ? SelnoDesign.border.opacity(0.5) : SelnoDesign.accent.opacity(0.7))
        )
        .onDrop(of: [WorkspaceDragType.module.identifier], isTargeted: nil) { providers in
            guard let source = draggedModuleID else { return false }
            return WorkspaceDragType.receive(providers, expected: source) { id in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    move(id, to: draft.count - 1)
                }
                draggedModuleID = nil
            }
        }
        .accessibilityIdentifier("workspace.edit.dropEnd")
    }

    private func move(_ sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID,
              let source = draft.firstIndex(where: { $0.id == sourceID }),
              let target = draft.firstIndex(where: { $0.id == targetID }) else { return }
        var list = draft
        let item = list.remove(at: source)
        let insertion = target > source ? target - 1 : target
        list.insert(item, at: max(0, min(insertion, list.count)))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            draft = renumbered(list)
        }
    }

    private func move(_ id: UUID, to destination: Int) {
        guard let source = draft.firstIndex(where: { $0.id == id }) else { return }
        var list = draft
        let item = list.remove(at: source)
        let target = min(max(0, destination), list.count)
        list.insert(item, at: target)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            draft = renumbered(list)
        }
    }

    private func setSize(_ id: UUID, _ size: ModuleSize) {
        guard let index = draft.firstIndex(where: { $0.id == id }),
              let descriptor = draft[index].kind.flatMap({ WorkspaceModuleRegistry.descriptor(for: $0) }),
              descriptor.supports(size) else { return }
        var module = draft[index]
        module.sizeRaw = size.rawValue
        module.updatedAt = Date.now
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            draft[index] = module
        }
    }

    private func remove(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            draft = renumbered(draft.filter { $0.id != id })
        }
    }

    private func renumbered(_ list: [WorkspaceModuleSnapshot]) -> [WorkspaceModuleSnapshot] {
        list.enumerated().map { index, module in module.with(sortOrder: index) }
    }
}

// MARK: - Edit card

private struct WorkspaceEditModuleCard: View {
    let module: WorkspaceModuleSnapshot
    let index: Int
    let count: Int
    let savedViewName: String?
    @Binding var draggedModuleID: UUID?
    let onMoveBefore: (UUID, UUID) -> Void
    let onMoveToIndex: (UUID, Int) -> Void
    let onSize: (UUID, ModuleSize) -> Void
    let onConfigure: (UUID) -> Void
    let onRemove: (UUID) -> Void

    @State private var isDropTarget = false

    private var descriptor: WorkspaceModuleDescriptor? { module.descriptor }
    private var isBeingDragged: Bool { draggedModuleID == module.id }
    private var showsInsertionIndicator: Bool { isDropTarget && !isBeingDragged }

    private var cardHeight: CGFloat {
        switch module.effectiveSize {
        case .small: 142
        case .medium: 204
        case .large: 258
        }
    }

    private var scopeText: String {
        if let savedViewName { return "任务视图 · \(savedViewName)" }
        guard module.kind != .quickActions else { return "不读取任务数据" }
        if module.isKnownKind { return module.dataScope.title }
        return "未知模块 · 原始配置已保留"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(SelnoDesign.secondary)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggedModuleID = module.id
                        return WorkspaceDragType.provider(for: module.id)
                    }
                    .accessibilityLabel("拖动 \(module.title)")
                    .accessibilityIdentifier("workspace.module.drag.\(module.id.uuidString)")
                Label(module.title, systemImage: module.symbolName)
                    .font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if let descriptor {
                    Menu {
                        ForEach(descriptor.supportedSizes) { size in
                            Button {
                                onSize(module.id, size)
                            } label: {
                                if module.effectiveSize == size {
                                    Label(size.title, systemImage: "checkmark")
                                } else {
                                    Text(size.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text(module.effectiveSize.title)
                        }
                        .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("模块尺寸")
                    .accessibilityValue(module.effectiveSize.title)
                    .accessibilityIdentifier("workspace.module.size.\(module.id.uuidString)")
                }
            }
            Text(scopeText)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if descriptor == nil {
                Text(module.kindRaw)
                    .font(.caption2.monospaced())
                    .foregroundStyle(SelnoDesign.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Label(module.effectiveSize.title + "号", systemImage: "rectangle.split.3x1")
                    .font(.caption2).foregroundStyle(.secondary)
                if let savedViewName {
                    Text(savedViewName).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(SelnoDesign.accent.opacity(0.08), in: Capsule())
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if descriptor != nil {
                    Button { onConfigure(module.id) } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .help("配置模块")
                    .accessibilityLabel("配置 \(module.title)")
                    .accessibilityIdentifier("workspace.module.config.\(module.id.uuidString)")
                }
                Button { onRemove(module.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("移除模块（不会删除任何任务）")
                .accessibilityLabel("移除 \(module.title)")
                .accessibilityIdentifier("workspace.module.remove.\(module.id.uuidString)")
                Menu {
                    Button("向前移动") { onMoveToIndex(module.id, index - 1) }.disabled(index == 0)
                    Button("向后移动") { onMoveToIndex(module.id, index + 1) }.disabled(index >= count - 1)
                    Divider()
                    Button("移到最前") { onMoveToIndex(module.id, 0) }.disabled(index == 0)
                    Button("移到最后") { onMoveToIndex(module.id, count - 1) }.disabled(index >= count - 1)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("调整 \(module.title) 顺序")
                .accessibilityIdentifier("workspace.module.move.\(module.id.uuidString)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background(SelnoDesign.surface, in: RoundedRectangle(cornerRadius: SelnoDesign.radius))
        .overlay {
            RoundedRectangle(cornerRadius: SelnoDesign.radius)
                .strokeBorder(strokeColor, style: StrokeStyle(lineWidth: 1, dash: descriptor == nil ? [5, 4] : []))
        }
        .overlay(alignment: .leading) {
            if showsInsertionIndicator {
                Capsule().fill(SelnoDesign.accent)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .offset(x: -10)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isBeingDragged ? 0.55 : 1)
        .onDrop(of: [WorkspaceDragType.module.identifier], delegate: WorkspaceEditDropDelegate(
            targetID: module.id,
            draggedModuleID: $draggedModuleID,
            isTargeted: $isDropTarget,
            moveBefore: onMoveBefore
        ))
        .contextMenu {
            Button("向前移动") { onMoveToIndex(module.id, index - 1) }.disabled(index == 0)
            Button("向后移动") { onMoveToIndex(module.id, index + 1) }.disabled(index >= count - 1)
            Divider()
            if descriptor != nil {
                Button("配置模块…") { onConfigure(module.id) }
            }
            Button("移除模块", role: .destructive) { onRemove(module.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.module.card.\(module.id.uuidString)")
        .accessibilityAction(named: Text("向前移动")) {
            if index > 0 { onMoveToIndex(module.id, index - 1) }
        }
        .accessibilityAction(named: Text("向后移动")) {
            if index < count - 1 { onMoveToIndex(module.id, index + 1) }
        }
    }

    private var strokeColor: Color {
        if showsInsertionIndicator { return SelnoDesign.accent.opacity(0.9) }
        return SelnoDesign.border.opacity(descriptor == nil ? 0.7 : 0.5)
    }
}

private struct WorkspaceEditDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedModuleID: UUID?
    @Binding var isTargeted: Bool
    let moveBefore: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedModuleID, draggedModuleID != targetID else { return }
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [WorkspaceDragType.module.identifier]) else {
            return false
        }
        return draggedModuleID != nil && draggedModuleID != targetID
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let source = draggedModuleID, source != targetID else { return false }
        let providers = info.itemProviders(for: [WorkspaceDragType.module.identifier])
        return WorkspaceDragType.receive(providers, expected: source) { id in
            moveBefore(id, targetID)
            draggedModuleID = nil
        }
    }
}

// MARK: - Requests

nonisolated struct WorkspaceModuleTarget: Identifiable, Equatable {
    var id: UUID
}

nonisolated struct WorkspaceEditorRequest: Identifiable, Equatable {
    var id: UUID
}