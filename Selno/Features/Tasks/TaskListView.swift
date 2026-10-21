import SwiftUI
import SwiftData

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Query(sort: \TaskCategory.sortOrder) private var tags: [TaskCategory]
    @Query(sort: \TodoProject.updatedAt, order: .reverse) private var projects: [TodoProject]
    let scope: TaskListScope
    let tasks: [TodoTask]
    @Binding var selection: Set<UUID>
    let focusRequest: Int
    var events: [CalendarEvent] = []
    var openEvent: (CalendarEvent) -> Void = { _ in }

    @State private var title = ""
    @State private var searchText = ""
    @State private var statusFilter: TaskStatusFilter = .all
    @State private var projectFilter: TaskProjectFilter = .all
    @State private var filterTagID: UUID?
    @State private var sortMode: TaskSortMode = .standard
    @State private var presentedError: PresentedError?
    @State private var templateCreation = false
    @State private var confirmBatchDelete = false
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var highlightedTaskID: UUID?
    @State private var highlightTask: Task<Void, Never>?
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        bodyWithConfirmation
    }

    private var bodyWithConfirmation: some View {
        bodyWithAlert
            .confirmationDialog("删除选中的 \(selection.count) 个任务？", isPresented: $confirmBatchDelete,
                                titleVisibility: .visible) {
                Button("删除 \(selection.count) 个任务", role: .destructive) { deleteSelection() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("删除后可在 12 秒内撤销。任务的项目、标签、子任务、模板快照与提醒会一起恢复。")
            }
    }

    private var bodyWithAlert: some View {
        bodyWithSheet
            .alert(item: $presentedError) { error in
                Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("好")))
            }
    }

    private var bodyWithSheet: some View {
        bodyWithChanges
            .onDisappear {
                noticeTask?.cancel()
                highlightTask?.cancel()
            }
            .sheet(isPresented: $templateCreation) {
                TaskEditorView(calendar: calendar) { task in
                    revealTask(task)
                }
            }
    }

    private var bodyWithChanges: some View {
        timelineContent
            .onChange(of: focusRequest) { _, _ in quickAddFocused = true }
            .onChange(of: searchText) { _, _ in pruneSelection() }
            .onChange(of: statusFilter) { _, _ in pruneSelection() }
            .onChange(of: projectFilter) { _, _ in pruneSelection() }
            .onChange(of: filterTagID) { _, _ in pruneSelection() }
            .onChange(of: tags.map(\.id)) { _, ids in
                if let filterTagID, !ids.contains(filterTagID) { self.filterTagID = nil }
            }
            .onChange(of: projects.map(\.id)) { _, ids in
                if case .project(let id) = projectFilter, !ids.contains(id) {
                    projectFilter = .all
                    pruneSelection()
                }
            }
            .onChange(of: tasks.map(\.id)) { _, ids in
                selection = selection.intersection(ids)
            }
    }

    private var timelineContent: some View {
        TimelineView(.everyMinute) { timeline in
            workspace(now: timeline.date)
        }
    }

    @ViewBuilder
    private func workspace(now: Date) -> some View {
        let base = usesGlobalTaskUniverse ? tasks : scope.tasks(from: tasks, on: now, calendar: calendar)
        let filtered = TaskQueryFilter.apply(base, search: searchText, status: statusFilter,
                                             project: projectFilter, tagID: filterTagID)
        let visibleTasks = sortMode.sort(filtered)
        let showEvents = scope == .today && !hasActiveFilters && !events.isEmpty
        VStack(spacing: 0) {
            searchBar
            filterBar
            if !selection.isEmpty { batchBar }
            if visibleTasks.isEmpty && !showEvents {
                emptyState
            } else {
                List(selection: $selection) {
                    if showEvents {
                        Section("日程") {
                            ForEach(events) { event in
                                CalendarEventAgendaRow(event: event, calendar: calendar) { openEvent(event) }
                            }
                        }
                    }
                    if statusFilter == .archived {
                        taskSection("已归档", tasks: visibleTasks)
                    } else {
                        taskSection("待办", tasks: visibleTasks.filter { $0.status.isActive })
                        taskSection("已完成", tasks: visibleTasks.filter { $0.status == .completed })
                        taskSection("已取消", tasks: visibleTasks.filter { $0.status == .cancelled })
                    }
                }
                .accessibilityIdentifier("task.list")
                .overlay(alignment: .top) {
                    if let notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(SelnoDesign.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(.regularMaterial))
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("task.list.notice")
                            .transition(.opacity)
                    }
                }
            }
            Divider()
            quickAddBar
        }
        .navigationTitle(scope.title)
    }

    // MARK: Search and filters

    private var usesGlobalTaskUniverse: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || statusFilter == .archived
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || statusFilter != .all || projectFilter != .all || filterTagID != nil
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(SelnoDesign.tertiary)
            TextField("搜索标题、备注、项目或标签", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .accessibilityIdentifier("task.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(SelnoDesign.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityIdentifier("task.search.clear")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.055)))
        .padding(.horizontal, 12).padding(.top, 10)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(TaskStatusFilter.allCases) { option in
                    Button {
                        statusFilter = option
                    } label: {
                        if statusFilter == option { Label(option.title, systemImage: "checkmark") }
                        else { Text(option.title) }
                    }
                }
            } label: {
                filterChip(statusFilter == .all ? "状态" : statusFilter.title,
                           systemImage: statusFilter.symbolName, active: statusFilter != .all)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("task.filter.status")

            Menu {
                Button { projectFilter = .all } label: {
                    if projectFilter == .all { Label("全部项目", systemImage: "checkmark") } else { Text("全部项目") }
                }
                Button { projectFilter = .unassigned } label: {
                    if projectFilter == .unassigned { Label("未归属项目", systemImage: "checkmark") } else { Text("未归属项目") }
                }
                if !projects.isEmpty { Divider() }
                ForEach(projects) { project in
                    Button { projectFilter = .project(project.id) } label: {
                        if projectFilter == .project(project.id) { Label(project.name, systemImage: "checkmark") }
                        else { Text(project.name) }
                    }
                }
            } label: {
                filterChip(projectFilterTitle, systemImage: projectFilter.symbolName, active: projectFilter != .all)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("task.filter.project")

            Menu {
                Button { filterTagID = nil } label: {
                    if filterTagID == nil { Label("全部标签", systemImage: "checkmark") } else { Text("全部标签") }
                }
                if !tags.isEmpty { Divider() }
                ForEach(tags) { tag in
                    Button { filterTagID = tag.id } label: {
                        let title = tag.emoji.isEmpty ? tag.name : "\(tag.emoji) \(tag.name)"
                        if filterTagID == tag.id { Label(title, systemImage: "checkmark") } else { Text(title) }
                    }
                }
            } label: {
                filterChip(filterTagTitle, systemImage: "tag", active: filterTagID != nil)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("tags.filter")

            Spacer(minLength: 0)
            Menu {
                ForEach(TaskSortMode.allCases) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        if sortMode == mode { Label(mode.title, systemImage: "checkmark") }
                        else { Text(mode.title) }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(SelnoDesign.secondary)
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("排序：\(sortMode.title)")
            .accessibilityIdentifier("task.sort")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private var projectFilterTitle: String {
        switch projectFilter {
        case .all: "项目"
        case .unassigned: "未归属项目"
        case .project(let id): projects.first { $0.id == id }?.name ?? "项目"
        }
    }

    private var filterTagTitle: String {
        guard let filterTagID, let tag = tags.first(where: { $0.id == filterTagID }) else { return "全部标签" }
        return tag.emoji.isEmpty ? tag.name : "\(tag.emoji) \(tag.name)"
    }

    private func filterChip(_ text: String, systemImage: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 9, weight: .medium))
            Text(text).font(.caption2).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.55)
        }
        .foregroundStyle(active ? SelnoDesign.accent : SelnoDesign.secondary)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(maxWidth: 104, alignment: .leading)
        .background(Capsule().fill(active ? SelnoDesign.accent.opacity(0.12) : Color.primary.opacity(0.05)))
        .contentShape(Capsule())
    }

    // MARK: Batch actions

    private var batchTasks: [TodoTask] {
        tasks.filter { selection.contains($0.id) }
    }

    private var batchBar: some View {
        HStack(spacing: 10) {
            Text("已选 \(selection.count) 项")
                .font(.caption.weight(.medium))
                .foregroundStyle(SelnoDesign.accent)
            Spacer(minLength: 0)
            Button(action: completeSelection) {
                Image(systemName: "checkmark.circle")
            }
            .help("标记完成")
            .accessibilityLabel("批量完成")
            .accessibilityIdentifier("task.batch.complete")
            Menu {
                if tags.isEmpty { Text("还没有标签") }
                ForEach(tags) { tag in
                    Button(tag.emoji.isEmpty ? tag.name : "\(tag.emoji) \(tag.name)") {
                        addTag(tag)
                    }
                }
            } label: { Image(systemName: "tag") }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("添加标签")
            .accessibilityLabel("批量添加标签")
            .accessibilityIdentifier("task.batch.tag")
            Menu {
                Button("移出项目") { assignProject(nil) }
                if !projects.isEmpty { Divider() }
                ForEach(projects) { project in
                    Button(project.name) { assignProject(project) }
                }
            } label: { Image(systemName: "folder") }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("移动到项目")
            .accessibilityLabel("批量移动项目")
            .accessibilityIdentifier("task.batch.project")
            Button(action: toggleArchiveSelection) {
                Image(systemName: batchTasks.contains(where: { !$0.isArchived }) ? "archivebox" : "archivebox.fill")
            }
            .help(batchTasks.contains(where: { !$0.isArchived }) ? "归档" : "取消归档")
            .accessibilityLabel(batchTasks.contains(where: { !$0.isArchived }) ? "批量归档" : "批量取消归档")
            .accessibilityIdentifier("task.batch.archive")
            Button { confirmBatchDelete = true } label: { Image(systemName: "trash") }
                .help("删除")
                .accessibilityLabel("批量删除")
                .accessibilityIdentifier("task.batch.delete")
            Button { selection.removeAll() } label: { Image(systemName: "xmark.circle") }
                .help("取消选择")
                .accessibilityLabel("取消选择")
                .accessibilityIdentifier("task.batch.clear")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(SelnoDesign.accent.opacity(0.07))
    }

    private func completeSelection() {
        do {
            let count = try TaskService(context: context).complete(batchTasks)
            showNotice("已完成 \(count) 个任务")
        } catch { presentedError = PresentedError("无法批量完成任务", error: error) }
    }

    private func addTag(_ tag: TaskCategory) {
        do {
            try TaskService(context: context).addTag(tag, to: batchTasks)
            showNotice("已为 \(batchTasks.count) 个任务添加「\(tag.name)」")
        } catch { presentedError = PresentedError("无法批量添加标签", error: error) }
    }

    private func assignProject(_ project: TodoProject?) {
        do {
            try TaskService(context: context).assign(project: project, to: batchTasks)
            showNotice(project.map { "已移动到「\($0.name)」" } ?? "已移出项目")
            pruneSelection()
        } catch { presentedError = PresentedError("无法批量移动任务", error: error) }
    }

    private func toggleArchiveSelection() {
        let targets = batchTasks
        let shouldArchive = targets.contains { !$0.isArchived }
        do {
            try TaskService(context: context).setArchived(shouldArchive, for: targets)
            selection.removeAll()
            pruneSelection()
            showNotice(shouldArchive ? "已归档 \(targets.count) 个任务" : "已恢复 \(targets.count) 个任务")
        } catch { presentedError = PresentedError("无法批量归档任务", error: error) }
    }

    private func deleteSelection() {
        let targets = batchTasks
        guard !targets.isEmpty else { return }
        do {
            let snapshot = try TaskService(context: context).delete(targets)
            TaskUndoCenter.shared.offer(snapshot)
            selection.removeAll()
        } catch { presentedError = PresentedError("无法删除任务", error: error) }
    }

    // MARK: List and quick add

    private var emptyState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(hasActiveFilters ? "没有匹配的任务" : scope.title,
                      systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : scope.symbolName)
            } description: {
                Text(hasActiveFilters ? "试试调整搜索或筛选条件。" : scope.emptyDescription)
            }
            if hasActiveFilters {
                Button("清除搜索与筛选") { clearFilters() }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("task.filters.clear")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var quickAddBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle").foregroundStyle(.secondary)
                TextField("输入任务标题，按回车创建", text: $title)
                    .textFieldStyle(.plain)
                    .focused($quickAddFocused)
                    .onSubmit(createTask)
                    .accessibilityIdentifier("task.quickAdd")
                Button(action: createTask) {
                    Image(systemName: "arrow.turn.down.left")
                }
                .help("保存到收件箱")
                .accessibilityLabel("创建任务")
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            HStack {
                Button("从模板创建") { templateCreation = true }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("task.fromTemplate")
                Spacer()
                Text("↩ 快速记录").font(.caption).foregroundStyle(SelnoDesign.tertiary)
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func taskSection(_ title: String, tasks: [TodoTask]) -> some View {
        if !tasks.isEmpty {
            Section(title) {
                ForEach(tasks) { task in
                    TaskRowView(task: task) {
                        do {
                            try TaskService(context: context).toggleCompletion(task)
                        } catch {
                            presentedError = PresentedError("无法更新任务", error: error)
                        }
                    }
                    .tag(task.id)
                    .listRowBackground(
                        highlightedTaskID == task.id
                            ? SelnoDesign.accent.opacity(0.12)
                            : Color.clear
                    )
                }
            }
        }
    }

    private func createTask() {
        do {
            let task = try TaskService(context: context).createTask(title: title)
            title = ""
            revealTask(task)
            selection = [task.id]
        } catch {
            presentedError = PresentedError("无法创建任务", error: error)
        }
    }

    /// Makes a freshly created task visible: clears filters that could hide it,
    /// briefly highlights its row, and posts a transient notice. The caller is
    /// responsible for selecting the row when the detail pane should open.
    private func revealTask(_ task: TodoTask) {
        clearFilters()
        selection.removeAll()
        highlightedTaskID = task.id
        highlightTask?.cancel()
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            if highlightedTaskID == task.id { highlightedTaskID = nil }
        }
        showNotice("已创建「\(task.title)」")
    }

    private func clearFilters() {
        searchText = ""
        statusFilter = .all
        projectFilter = .all
        filterTagID = nil
    }

    private func pruneSelection() {
        let base = usesGlobalTaskUniverse ? tasks : scope.tasks(from: tasks, on: .now, calendar: calendar)
        let visible = Set(TaskQueryFilter.apply(
            base, search: searchText, status: statusFilter,
            project: projectFilter, tagID: filterTagID
        ).map(\.id))
        selection = selection.intersection(visible)
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}