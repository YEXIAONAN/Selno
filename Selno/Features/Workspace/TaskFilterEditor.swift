import SwiftUI
import SwiftData

// MARK: - Reusable filter editor

/// A structured rule builder. Values inside one dimension are ORed and the
/// dimensions are ANDed; the summary underneath spells that out before saving.
struct TaskFilterEditor: View {
    @Binding var filter: TaskFilterExpression
    @Query(sort: \TodoProject.name) private var projects: [TodoProject]
    @Query(sort: \TaskCategory.sortOrder) private var tags: [TaskCategory]
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FilterGroup(title: "任务状态（任一）") {
                chipGrid {
                    ForEach(TaskStatus.allCases) { status in
                        FilterToggleChip(title: status.title,
                                         selected: filter.statuses.contains(status.rawValue),
                                         identifier: "filter.status.\(status.rawValue)") {
                            toggle(status.rawValue, in: &filter.statuses)
                        }
                    }
                }
            }

            FilterGroup(title: "重要性（任一）") {
                chipGrid {
                    ForEach(TaskImportance.allCases) { importance in
                        FilterToggleChip(title: importance.title,
                                         selected: filter.importances.contains(importance.rawValue),
                                         identifier: "filter.importance.\(importance.rawValue)") {
                            toggle(importance.rawValue, in: &filter.importances)
                        }
                    }
                }
            }

            FilterGroup(title: "项目（任一）") {
                let active = projects.filter { $0.archivedAt == nil }
                if active.isEmpty && filter.projectIDs.isEmpty {
                    Text("还没有项目。筛选会匹配全部项目。")
                        .font(.caption).foregroundStyle(SelnoDesign.secondary)
                } else {
                    chipGrid {
                        ForEach(active) { project in
                            FilterToggleChip(title: project.name,
                                             symbol: "folder",
                                             selected: filter.projectIDs.contains(project.id),
                                             identifier: "filter.project.\(project.id.uuidString)") {
                                toggle(project.id, in: &filter.projectIDs)
                            }
                        }
                        FilterToggleChip(title: "未归属项目",
                                         symbol: "tray",
                                         selected: filter.includeUnassignedProject,
                                         identifier: "filter.project.unassigned") {
                            filter.includeUnassignedProject.toggle()
                        }
                    }
                }
            }

            FilterGroup(title: "标签（任一）") {
                let active = tags.filter { !$0.isArchived }
                if active.isEmpty && filter.tagIDs.isEmpty {
                    Text("还没有标签。标签筛选可以留空。")
                        .font(.caption).foregroundStyle(SelnoDesign.secondary)
                } else {
                    chipGrid {
                        ForEach(active) { tag in
                            FilterToggleChip(title: "\(tag.emoji)\(tag.name)",
                                             symbol: tag.emoji.isEmpty ? "tag" : nil,
                                             selected: filter.tagIDs.contains(tag.id),
                                             identifier: "filter.tag.\(tag.id.uuidString)") {
                                toggle(tag.id, in: &filter.tagIDs)
                            }
                        }
                    }
                }
            }

            FilterGroup(title: "日期范围") {
                HStack(spacing: 12) {
                    Picker("依据", selection: $filter.dateField) {
                        ForEach(FilterDateField.allCases) { field in Text(field.title).tag(field) }
                    }
                    .frame(maxWidth: 190)
                    .disabled(filter.dateRange == .any)
                    .accessibilityIdentifier("filter.dateField")
                    Picker("范围", selection: $filter.dateRange) {
                        ForEach(FilterDateRange.allCases) { range in Text(range.title).tag(range) }
                    }
                    .frame(maxWidth: 220)
                    .accessibilityIdentifier("filter.dateRange")
                }
                if filter.dateRange == .custom {
                    HStack(spacing: 12) {
                        DatePicker("开始", selection: Binding(
                            get: { filter.customStart ?? calendar.startOfDay(for: .now) },
                            set: { filter.customStart = calendar.startOfDay(for: $0) }
                        ), displayedComponents: .date)
                        DatePicker("结束", selection: Binding(
                            get: { filter.customEnd ?? calendar.startOfDay(for: .now) },
                            set: { filter.customEnd = calendar.startOfDay(for: $0) }
                        ), displayedComponents: .date)
                    }
                    .accessibilityIdentifier("filter.customRange")
                }
                Text("日期按当前日历与本地时区计算；“今天”指本地零点到明天零点。")
                    .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
            }

            FilterGroup(title: "其他条件（全部满足）") {
                HStack(spacing: 12) {
                    Picker("截止状态", selection: $filter.dueState) {
                        ForEach(FilterDueState.allCases) { state in Text(state.title).tag(state) }
                    }
                    Picker("计划日期", selection: $filter.plannedState) {
                        ForEach(FilterPresence.allCases) { state in Text(state.title).tag(state) }
                    }
                }
                Toggle("包含已归档任务", isOn: $filter.includeArchived)
                    .accessibilityIdentifier("filter.includeArchived")
                TextField("标题或备注关键字", text: $filter.searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("filter.search")
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(filter.summary(projectNames: projectNames, tagNames: tagNames))
                    .font(.caption).foregroundStyle(SelnoDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("清空条件") { filter = .unrestricted }
                    .buttonStyle(.link).font(.caption)
                    .accessibilityIdentifier("filter.clear")
            }
        }
        .onChange(of: filter.dateRange) { _, range in
            if range == .custom {
                materializeCustomRangeIfNeeded()
            } else {
                filter.customStart = nil
                filter.customEnd = nil
            }
            if range == .any { filter.dateField = .any }
        }
        .onAppear { materializeCustomRangeIfNeeded() }
    }

    /// The pickers visibly fall back to today, so materialize that value when a
    /// custom range is selected. Otherwise saving without touching both pickers
    /// fails validation even though the UI appears complete.
    private func materializeCustomRangeIfNeeded() {
        guard filter.dateRange == .custom else { return }
        let today = calendar.startOfDay(for: .now)
        if filter.customStart == nil { filter.customStart = today }
        if filter.customEnd == nil { filter.customEnd = today }
    }

    private var projectNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    }

    private var tagNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
    }

    private func chipGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)],
                  alignment: .leading, spacing: 6) {
            content()
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if !set.insert(value).inserted { set.remove(value) }
    }
}

private struct FilterGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(SelnoDesign.secondary)
            content
        }
    }
}

private struct FilterToggleChip: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption2) }
                Text(title).lineLimit(1)
                if selected { Image(systemName: "checkmark").font(.caption2.weight(.semibold)) }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(selected ? SelnoDesign.accent : SelnoDesign.secondary)
            .background(selected ? SelnoDesign.accent.opacity(0.12) : SelnoDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? SelnoDesign.accent.opacity(0.5) : SelnoDesign.border.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Saved view editor

struct SavedTaskViewEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let view: SavedTaskView?

    @State private var name: String
    @State private var emoji: String
    @State private var colorHex: String
    @State private var filter: TaskFilterExpression
    @State private var sort: TaskSortMode
    @State private var limit: Int
    @State private var error: String?

    init(view: SavedTaskView? = nil) {
        self.view = view
        _name = State(initialValue: view?.name ?? "新任务视图")
        _emoji = State(initialValue: view?.emoji ?? "🔎")
        _colorHex = State(initialValue: view?.colorHex ?? TagPalette.sage.rawValue)
        _filter = State(initialValue: view?.filter ?? .activeOnly)
        _sort = State(initialValue: view?.sort ?? .standard)
        _limit = State(initialValue: view?.effectiveLimit ?? 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(view == nil ? "新建任务视图" : "编辑任务视图")
                        .font(.title2.weight(.semibold))
                    FilterGroup(title: "名称与外观") {
                        HStack(spacing: 9) {
                            TextField("Emoji", text: $emoji)
                                .frame(width: 58)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("savedView.editor.emoji")
                            TextField("视图名称", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("savedView.editor.name")
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(TagPalette.allCases) { palette in
                                Button { colorHex = palette.rawValue } label: {
                                    Circle()
                                        .fill(TagPalette.color(palette.rawValue, dark: colorScheme == .dark))
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle().strokeBorder(
                                                colorHex.uppercased() == palette.rawValue.uppercased()
                                                    ? Color.primary : Color.clear,
                                                lineWidth: 2
                                            ).padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(palette.title)
                                .accessibilityLabel(palette.title)
                                .accessibilityValue(colorHex.uppercased() == palette.rawValue.uppercased() ? "已选择" : "")
                            }
                        }
                    }

                    TaskFilterEditor(filter: $filter)

                    FilterGroup(title: "显示方式") {
                        HStack(spacing: 12) {
                            Picker("排序", selection: $sort) {
                                ForEach(TaskSortMode.allCases) { mode in Text(mode.title).tag(mode) }
                            }
                            .frame(maxWidth: 210)
                            Stepper("最多显示 \(limit) 项", value: $limit, in: WorkspaceLimits.taskListLimitRange)
                                .accessibilityIdentifier("savedView.editor.limit")
                        }
                    }

                    if let error {
                        Text(error).font(.caption).foregroundStyle(SelnoDesign.danger)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(SelnoButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("savedView.editor.save")
            }
            .padding(16)
        }
        .frame(width: 660, height: 720)
        .tint(SelnoDesign.accent)
    }

    private func save() {
        do {
            let service = SavedViewService(context: context)
            if let view {
                try service.update(view.id, name: name, emoji: emoji, colorHex: colorHex,
                                   filter: filter, sort: sort, limit: limit)
            } else {
                try service.create(name: name, emoji: emoji, colorHex: colorHex,
                                   filter: filter, sort: sort, limit: limit)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Saved view management

struct SavedViewManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedTaskView.name) private var views: [SavedTaskView]
    @Query(sort: \TodoProject.name) private var projects: [TodoProject]
    @Query(sort: \TaskCategory.sortOrder) private var tags: [TaskCategory]
    @State private var isCreating = false
    @State private var editing: SavedTaskView?
    @State private var deleting: SavedTaskView?
    @State private var error: PresentedError?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("任务视图").font(.title2.weight(.semibold))
                Spacer()
                Button("新建视图") { isCreating = true }
                    .accessibilityIdentifier("savedViews.new")
            }
            Text("视图只保存筛选规则，不复制任务。删除视图会解除模块引用，但绝不会删除任何任务。")
                .font(.callout).foregroundStyle(SelnoDesign.secondary)
            if views.isEmpty {
                QuietEmptyState(title: "把常用筛选保存下来",
                                message: "例如“本周重要”“无截止日期的待办”，然后添加到工作台。")
                Spacer()
            } else {
                List(views) { view in
                    HStack(spacing: 10) {
                        Text(view.emoji.isEmpty ? "🔎" : view.emoji)
                            .font(.title3).frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(view.name).fontWeight(.medium)
                                Text("\(view.effectiveLimit) 项 · \(view.sort.title)")
                                    .font(.caption2).foregroundStyle(SelnoDesign.secondary)
                            }
                            Text(view.filter.summary(projectNames: projectNames, tagNames: tagNames))
                                .font(.caption).foregroundStyle(SelnoDesign.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("编辑") { editing = view }
                            .accessibilityIdentifier("savedView.edit.\(view.id.uuidString)")
                        Menu {
                            Button("复制视图") { perform { _ = try SavedViewService(context: context).duplicate(view.id) } }
                            Button("删除视图", role: .destructive) { deleting = view }
                        } label: { Image(systemName: "ellipsis") }
                        .fixedSize()
                        .accessibilityIdentifier("savedView.menu.\(view.id.uuidString)")
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityIdentifier("savedViews.list")
            }
        }
        .padding(24)
        .sheet(isPresented: $isCreating) { SavedTaskViewEditorView() }
        .sheet(item: $editing) { SavedTaskViewEditorView(view: $0) }
        .confirmationDialog("删除此任务视图？引用它的模块会恢复为场景筛选，任务本身不受影响。",
                            isPresented: Binding(get: { deleting != nil },
                                                 set: { if !$0 { deleting = nil } })) {
            Button("删除视图", role: .destructive) {
                if let deleting {
                    perform { try SavedViewService(context: context).delete(deleting.id) }
                }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
        .alert(item: $error) { error in
            Alert(title: Text(error.title), message: Text(error.message))
        }
    }

    private var projectNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    }

    private var tagNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { self.error = PresentedError("无法更新任务视图", error: error) }
    }
}