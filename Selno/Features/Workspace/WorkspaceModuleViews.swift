import SwiftUI

// MARK: - Actions

/// Closures keep the module library independent from navigation, sheets and the
/// model context. Every closure runs on the main actor because the board is a
/// SwiftUI view; none of them mutate data while the mouse is moving.
struct WorkspaceBoardActions {
    var openTask: (TodoTask) -> Void
    var openEvent: (CalendarEvent) -> Void
    var toggleTask: (TodoTask) -> Void
    var quickAddInbox: (String) -> Bool
    var openToday: () -> Void
    var openInbox: () -> Void
    var openAllTasks: () -> Void
    var openProjects: () -> Void
    var openCalendarDay: (Date) -> Void
    var openProject: (UUID) -> Void
    var createTask: () -> Void
    var createFromTemplate: () -> Void
    var createEvent: () -> Void
    var createProject: () -> Void
}

// MARK: - Module content

struct WorkspaceModuleContentView: View {
    let module: WorkspaceModuleSnapshot
    let workspaceFilter: TaskFilterExpression
    let savedViews: [UUID: SavedTaskViewSnapshot]
    let data: WorkspaceBoardData
    let showsHeading: Bool
    let isGlobal: Bool
    let actions: WorkspaceBoardActions

    @State private var quickTitle = ""

    private var resolved: ResolvedTaskFilter {
        WorkspaceFilterResolver.resolve(module: module, workspace: workspaceFilter, savedViews: savedViews)
    }

    private var savedView: SavedTaskViewSnapshot? {
        module.savedViewID.flatMap { savedViews[$0] }
    }

    private var summary: String {
        resolved.filter.summary(projectNames: data.projectNames, tagNames: data.tagNames)
    }

    var body: some View {
        Group {
            if let kind = module.kind {
                switch kind {
                case .focus: focusModule
                case .upcoming: upcomingModule
                case .month: monthModule
                case .inbox: inboxModule
                case .projects: projectsModule
                case .taskList: taskListModule
                case .stats: statsModule
                case .quickActions: quickActionsModule
                }
            } else {
                unknownModule
            }
        }
    }

    // MARK: Headings

    @ViewBuilder
    private func heading(
        _ title: String,
        symbol: String,
        detail: String = "",
        actionTitle: String = "",
        action: (() -> Void)? = nil,
        showsScope: Bool = true
    ) -> some View {
        if showsHeading {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if showsScope {
                    WorkspaceScopeBadge(resolved: resolved, summary: summary)
                }
                if let action, !actionTitle.isEmpty {
                    Button(actionTitle, action: action)
                        .buttonStyle(.link)
                        .font(.caption)
                        .foregroundStyle(SelnoDesign.accent)
                }
            }
            .accessibilityIdentifier("workspace.heading.\(module.id.uuidString)")
        }
    }

    @ViewBuilder
    private var scopeBadgeOnly: some View {
        WorkspaceScopeBadge(resolved: resolved, summary: summary)
    }

    // MARK: Focus

    private var focusModule: some View {
        let projection = data.projection(filter: resolved.filter, days: 3)
        let itemLimit = module.effectiveSize == .large ? 5 : 3
        let eventLimit = module.effectiveSize == .large ? 2 : 1
        let remaining = max(0, projection.focus.count - itemLimit) + max(0, projection.todayEvents.count - eventLimit)
        return VStack(alignment: .leading, spacing: 9) {
            heading("今日聚焦", symbol: "scope",
                    detail: "\(projection.focus.count + projection.todayEvents.count) 项",
                    actionTitle: "查看今天", action: actions.openToday)

            if projection.focus.isEmpty && projection.todayEvents.isEmpty {
                QuietEmptyState(title: "今天，可以从容开始",
                                message: "安排一件要紧的事，或先把想法放进收件箱。")
                HStack(spacing: 8) {
                    Button("安排任务", action: actions.createTask)
                        .buttonStyle(SelnoButtonStyle(primary: true))
                        .accessibilityIdentifier(isGlobal ? "dashboard.createTask" : "workspace.createTask")
                    Button("添加日程", action: actions.createEvent)
                        .buttonStyle(SelnoButtonStyle())
                        .accessibilityIdentifier(isGlobal ? "dashboard.createEvent" : "workspace.createEvent")
                }
            } else {
                if !projection.todayEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("按时发生").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(projection.todayEvents.prefix(eventLimit))) { event in
                            CalendarEventAgendaRow(event: event, calendar: data.calendar) {
                                actions.openEvent(event)
                            }
                        }
                    }
                }
                if !projection.focus.isEmpty {
                    if !projection.todayEvents.isEmpty { Divider() }
                    VStack(spacing: 1) {
                        ForEach(Array(projection.focus.prefix(itemLimit))) { item in
                            FocusTaskRow(item: item,
                                         open: { actions.openTask(item.task) },
                                         toggle: { actions.toggleTask(item.task) })
                        }
                    }
                }
                if remaining > 0 {
                    Button("还有 \(remaining) 项 · 查看今天", action: actions.openToday)
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    // MARK: Upcoming

    private var upcomingModule: some View {
        let days = module.config.effectiveDays
        let projection = data.projection(filter: resolved.filter, days: days)
        let dayLimit = module.effectiveSize == .large ? 7 : 3
        let shownDays = Array(projection.upcoming.prefix(dayLimit))
        return VStack(alignment: .leading, spacing: 9) {
            if showsHeading {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("近期安排", systemImage: "text.alignleft").font(.headline)
                    Spacer(minLength: 4)
                    scopeBadgeOnly
                }
                .accessibilityIdentifier("workspace.heading.\(module.id.uuidString)")
                Text("从明天起 · 每件事展示下一次安排")
                    .font(.caption).foregroundStyle(SelnoDesign.tertiary)
            }
            if shownDays.isEmpty {
                QuietEmptyState(title: "未来 \(days) 天暂无新安排",
                                message: "今天需要处理的事项已集中在今日聚焦。")
            } else {
                ForEach(shownDays) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Button { actions.openCalendarDay(day.date) } label: {
                            HStack {
                                Text(CalendarMath.fullDate(day.date, calendar: data.calendar))
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        ForEach(Array(day.events.prefix(2))) { event in
                            CalendarEventAgendaRow(event: event, calendar: data.calendar) {
                                actions.openEvent(event)
                            }
                        }
                        ForEach(Array(day.tasks.prefix(3))) { occurrence in
                            CalendarTaskAgendaRow(occurrence: occurrence,
                                                  open: { actions.openTask(occurrence.task) },
                                                  toggle: { actions.toggleTask(occurrence.task) })
                        }
                        let rest = max(0, day.events.count - 2) + max(0, day.tasks.count - 3)
                        if rest > 0 {
                            Button("另有 \(rest) 项，打开当日安排") { actions.openCalendarDay(day.date) }
                                .buttonStyle(.link).font(.caption)
                        }
                    }
                    if day.id != shownDays.last?.id { Divider() }
                }
                if projection.upcoming.count > shownDays.count {
                    Button("查看全部 \(days) 天安排") { actions.openCalendarDay(data.now) }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    // MARK: Month

    private var monthModule: some View {
        let snapshot = data.monthSnapshot(filter: resolved.filter)
        return VStack(alignment: .leading, spacing: 9) {
            heading(CalendarMath.monthTitle(data.now, calendar: data.calendar), symbol: "calendar",
                    actionTitle: "展开", action: { actions.openCalendarDay(data.now) })
            CompactMonthView(
                window: data.monthWindow,
                today: data.now,
                snapshot: snapshot,
                calendar: data.calendar,
                identifierPrefix: isGlobal ? "dashboard.day" : "workspace.day",
                roomy: module.effectiveSize == .large,
                select: actions.openCalendarDay
            )
        }
    }

    // MARK: Inbox

    private var inboxModule: some View {
        let visibleLimit: Int
        switch module.effectiveSize {
        case .small: visibleLimit = 2
        case .medium: visibleLimit = 4
        case .large: visibleLimit = 6
        }
        let count = data.inboxCount(filter: resolved.filter)
        let inbox = data.inboxTasks(filter: resolved.filter, limit: visibleLimit)
        return VStack(alignment: .leading, spacing: 9) {
            heading("收件箱", symbol: "tray", detail: "\(count)",
                    actionTitle: "整理", action: actions.openInbox)
            if inbox.isEmpty {
                QuietEmptyState(title: "想法随时放在这里", message: "尚未安排的任务，稍后再整理。")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(inbox) { task in
                        Button { actions.openTask(task) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Image(systemName: "circle.small").foregroundStyle(.tertiary)
                                Text(task.title).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .accessibilityIdentifier("workspace.inbox.task.\(task.id.uuidString)")
                    }
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("快速记下任务…", text: $quickTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(submitQuickAdd)
                    .accessibilityIdentifier(isGlobal ? "dashboard.quickAdd" : "workspace.quickAdd.\(module.id.uuidString)")
                if !quickTitle.isEmpty {
                    Button(action: submitQuickAdd) {
                        Image(systemName: "arrow.turn.down.left")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("保存到收件箱")
                }
            }
            .padding(9)
            .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
            Text("\(count) 项待整理 · 未设置计划或项目")
                .font(.caption2).foregroundStyle(.tertiary)
                .accessibilityIdentifier(isGlobal ? "dashboard.inboxCount" : "workspace.inboxCount.\(module.id.uuidString)")
        }
    }

    private func submitQuickAdd() {
        let value = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if actions.quickAddInbox(value) { quickTitle = "" }
    }

    // MARK: Projects

    private var projectsModule: some View {
        let visibleLimit: Int
        switch module.effectiveSize {
        case .small: visibleLimit = 1
        case .medium: visibleLimit = 3
        case .large: visibleLimit = 6
        }
        let result = data.projectList(filter: resolved.filter, limit: visibleLimit)
        return VStack(alignment: .leading, spacing: 9) {
            heading("项目进度", symbol: "folder", detail: "\(result.total) 个进行中",
                    actionTitle: "全部项目", action: actions.openProjects)
            if result.visible.isEmpty {
                HStack {
                    QuietEmptyState(title: "把相关事务，归入同一个项目",
                                    message: "为长期推进的事情保留清晰的进度。")
                    Spacer()
                    Button("创建项目", action: actions.createProject)
                        .buttonStyle(SelnoButtonStyle())
                        .accessibilityIdentifier(isGlobal ? "dashboard.createProject" : "workspace.createProject")
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 22)],
                          alignment: .leading, spacing: 14) {
                    ForEach(result.visible) { project in
                        Button { actions.openProject(project.id) } label: {
                            ProjectProgressView(project: project, calendar: data.calendar, now: data.now)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(projectLabel(project))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier(isGlobal
                            ? "dashboard.project.\(project.id.uuidString)"
                            : "workspace.project.\(project.id.uuidString)")
                    }
                }
                if result.total > result.visible.count {
                    Button("另有 \(result.total - result.visible.count) 个项目") { actions.openProjects() }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    private func projectLabel(_ project: TodoProject) -> String {
        let progress = ProjectProgress(project: project, now: data.now, calendar: data.calendar)
        return "\(project.name)，\(progress.completed) / \(progress.total) 已完成，\(progress.overdue) 项逾期"
    }

    // MARK: Task list

    private var taskListModule: some View {
        let filter = savedView?.filter ?? resolved.filter
        let sort = savedView?.sort ?? module.config.sort
        let limit = savedView?.effectiveLimit ?? module.config.effectiveLimit
        let result = data.taskList(filter: filter, sort: sort, limit: limit)
        let title = savedView?.name ?? "任务列表"
        return VStack(alignment: .leading, spacing: 7) {
            heading(title, symbol: "list.bullet.rectangle", detail: "\(result.total) 项",
                    actionTitle: "全部任务", action: actions.openAllTasks)
            if result.visible.isEmpty {
                QuietEmptyState(title: "没有符合条件的任务",
                                message: "调整筛选规则，或在全部任务中新建事项。")
            } else {
                VStack(spacing: 1) {
                    ForEach(result.visible) { task in
                        WorkspaceTaskRow(task: task, calendar: data.calendar, now: data.now,
                                         open: { actions.openTask(task) },
                                         toggle: { actions.toggleTask(task) })
                    }
                }
                if result.total > result.visible.count {
                    Button("还有 \(result.total - result.visible.count) 项") { actions.openAllTasks() }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    // MARK: Stats

    private var statsModule: some View {
        let stats = WorkspaceTaskStatistics.make(
            tasks: data.tasks(matching: resolved.filter),
            now: data.now, calendar: data.calendar
        )
        return VStack(alignment: .leading, spacing: 10) {
            heading("任务统计", symbol: "chart.bar", detail: "真实任务数据")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                statTile("待办", value: stats.pending, symbol: "circle.dashed", id: "pending")
                statTile("今日完成", value: stats.completedToday, symbol: "checkmark.circle", id: "completedToday")
                statTile("已逾期", value: stats.overdue, symbol: "exclamationmark.circle", id: "overdue",
                         color: stats.overdue > 0 ? SelnoDesign.warning : SelnoDesign.secondary)
                statTile("3 天内截止", value: stats.dueSoon, symbol: "clock", id: "dueSoon")
            }
        }
    }

    private func statTile(_ title: String, value: Int, symbol: String, id: String,
                          color: Color = SelnoDesign.secondary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.caption)
                Text(title).font(.caption)
            }
            .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SelnoDesign.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workspace.stats.\(id)")
    }

    // MARK: Quick actions

    private var quickActionsModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("快捷操作", symbol: "bolt", showsScope: false)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 9)], spacing: 9) {
                quickAction("新建任务", symbol: "plus.circle", id: "task", action: actions.createTask)
                quickAction("从模板创建", symbol: "square.stack", id: "template", action: actions.createFromTemplate)
                quickAction("新建日程", symbol: "calendar.badge.plus", id: "event", action: actions.createEvent)
                quickAction("打开今天", symbol: "sun.max", id: "today", action: actions.openToday)
                quickAction("打开日历", symbol: "calendar", id: "calendar", action: { actions.openCalendarDay(data.now) })
            }
        }
    }

    private func quickAction(_ title: String, symbol: String, id: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(SelnoDesign.border.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workspace.quick.\(id)")
    }

    // MARK: Unknown

    private var unknownModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("未知模块", systemImage: "questionmark.square.dashed")
                .font(.headline)
                .foregroundStyle(SelnoDesign.secondary)
            Text("此模块由更新版本的 Selno 创建。当前版本保留它的全部配置，但不会尝试渲染。")
                .font(.caption)
                .foregroundStyle(SelnoDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(module.kindRaw)
                .font(.caption2.monospaced())
                .foregroundStyle(SelnoDesign.tertiary)
                .textSelection(.enabled)
        }
        .accessibilityIdentifier("workspace.module.unknown.\(module.id.uuidString)")
    }
}

// MARK: - Scope badge

struct WorkspaceScopeBadge: View {
    let resolved: ResolvedTaskFilter
    let summary: String

    private var color: Color {
        switch resolved.source {
        case .scenario: SelnoDesign.secondary
        case .global: SelnoDesign.accentSecondary
        case .custom: SelnoDesign.accent
        }
    }

    var body: some View {
        Label(resolved.source.title, systemImage: resolved.source.symbolName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.08), in: Capsule())
            .help("数据范围：\(resolved.source.title)\n\(summary)")
            .accessibilityLabel("数据范围：\(resolved.source.title)")
            .accessibilityValue(summary)
            .accessibilityIdentifier("workspace.scope")
    }
}

// MARK: - Task row

struct WorkspaceTaskRow: View {
    let task: TodoTask
    let calendar: Calendar
    let now: Date
    let open: () -> Void
    let toggle: () -> Void

    private var isOverdue: Bool {
        task.status.isActive && (task.dueAt.map { $0 < calendar.startOfDay(for: now) } ?? false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: toggle) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" :
                        task.status == .cancelled ? "minus.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
            }
            .buttonStyle(.borderless)
            .disabled(task.status == .cancelled)
            .accessibilityLabel(task.status == .completed ? "恢复为未完成" : "标记为完成")
            .accessibilityIdentifier("workspace.task.complete.\(task.id.uuidString)")

            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .strikethrough(task.status == .completed)
                        .foregroundStyle(task.status.isActive ? .primary : .secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if task.importance == .high {
                            Label("重要", systemImage: "flag.fill")
                        }
                        if task.status == .inProgress {
                            StatusBadge(title: "进行中", symbol: "circle.lefthalf.filled")
                        }
                        if let planned = task.plannedAt {
                            Label("计划 \(planned.formatted(.dateTime.month().day()))",
                                  systemImage: "calendar")
                        }
                        if let due = task.dueAt {
                            Label("截止 \(due.formatted(.dateTime.month().day()))",
                                  systemImage: "flag")
                                .foregroundStyle(isOverdue ? SelnoDesign.warning : .secondary)
                        }
                        if let project = task.project {
                            Text(project.name).lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    TaskTags(task: task, limit: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workspace.task.\(task.id.uuidString)")

            if isOverdue {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(SelnoDesign.warning)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 5)
    }
}