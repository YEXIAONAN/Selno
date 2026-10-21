import SwiftUI
import SwiftData

// MARK: - Create

struct WorkspaceCreateView: View {
    let onCreated: (UUID) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workspace.sortOrder) private var workspaces: [Workspace]

    @State private var preset: WorkspacePreset = .blank
    @State private var name = WorkspacePreset.blank.defaultName
    @State private var emoji = WorkspacePreset.blank.defaultEmoji
    @State private var accent: WorkspaceAccent = .sage
    @State private var filter: TaskFilterExpression = .unrestricted
    @State private var copySourceID: UUID?
    @State private var filterExpanded = false
    @State private var error: String?

    private var atLimit: Bool { workspaces.count >= WorkspaceLimits.maximumWorkspaces }
    private var copyReady: Bool { preset != .copy || copySourceID != nil }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("新建工作台")
                            .font(.title2.weight(.semibold))
                            .accessibilityIdentifier("workspace.create")
                        Text("工作台是同一份本地数据的场景化视图。创建场景不会复制或移动任何任务、项目、标签与日程。")
                            .font(.caption).foregroundStyle(SelnoDesign.secondary)
                    }

                    WorkspaceSection(title: "从预设开始") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(WorkspacePreset.allCases) { value in
                                presetCard(value)
                            }
                        }
                    }

                    if preset == .copy {
                        WorkspaceSection(title: "复制来源") {
                            Picker("复制来源", selection: $copySourceID) {
                                Text("选择工作台").tag(nil as UUID?)
                                ForEach(workspaces) { workspace in
                                    Text("\(workspace.emoji) \(workspace.name)\(workspace.isGlobal ? "（全局）" : "")")
                                        .tag(Optional(workspace.id))
                                }
                            }
                            .accessibilityIdentifier("workspace.create.copySource")
                            Text("复制只包含模块布局与筛选配置；业务数据始终共享。")
                                .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                        }
                    }

                    WorkspaceSection(title: "名称与外观") {
                        HStack(spacing: 9) {
                            TextField("Emoji", text: $emoji)
                                .frame(width: 58)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("workspace.create.emoji")
                            TextField("工作台名称", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("workspace.create.name")
                        }
                        WorkspaceAccentPicker(accent: $accent)
                    }

                    WorkspaceSection(title: "场景默认筛选") {
                        WorkspaceFilterDisclosure(identifier: "workspace.create.filter",
                                                  isExpanded: $filterExpanded,
                                                  summary: filter.summary()) {
                            TaskFilterEditor(filter: $filter)
                                .padding(.top, 8)
                        }
                        Text("模块默认继承这里的规则；也可在模块中改为全局数据或完全自定义。")
                            .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                    }

                    if atLimit {
                        Label("已达到 \(WorkspaceLimits.maximumWorkspaces) 个工作台上限。请先删除不用的场景。",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(SelnoDesign.warning)
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
                Button("创建工作台") { create() }
                    .buttonStyle(SelnoButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(atLimit || !copyReady || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("workspace.create.save")
            }
            .padding(16)
        }
        .frame(width: 680, height: 740)
        .tint(SelnoDesign.accent)
        .onChange(of: preset) { _, value in
            name = value.defaultName
            emoji = value.defaultEmoji
            accent = value.defaultAccent
            if value != .copy { copySourceID = nil }
        }
        .onAppear {
            if copySourceID == nil {
                copySourceID = workspaces.first(where: \.isGlobal)?.id ?? workspaces.first?.id
            }
        }
    }

    private func presetCard(_ value: WorkspacePreset) -> some View {
        Button {
            preset = value
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(value.defaultEmoji)
                    Text(value.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if preset == value {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SelnoDesign.accent)
                    }
                }
                Text(value.summary)
                    .font(.caption2).foregroundStyle(SelnoDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .contentShape(Rectangle())
            .background(preset == value ? SelnoDesign.accent.opacity(0.09) : SelnoDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(preset == value ? SelnoDesign.accent.opacity(0.6) : SelnoDesign.border.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value.title)：\(value.summary)")
        .accessibilityValue(preset == value ? "已选择" : "未选择")
        .accessibilityIdentifier("workspace.create.preset.\(value.rawValue)")
    }

    private func create() {
        do {
            let workspace = try WorkspaceService(context: context).createWorkspace(
                name: name, emoji: emoji, accent: accent, filter: filter,
                preset: preset,
                copySourceID: preset == .copy ? copySourceID : nil
            )
            onCreated(workspace.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Edit

struct WorkspaceEditorView: View {
    let workspaceID: UUID
    let onDeleted: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workspace.sortOrder) private var workspaces: [Workspace]

    @State private var loaded = false
    @State private var name = ""
    @State private var emoji = "🗂"
    @State private var accent: WorkspaceAccent = .sage
    @State private var filter: TaskFilterExpression = .unrestricted
    @State private var filterExpanded = false
    @State private var confirmDelete = false
    @State private var error: String?

    private var workspace: Workspace? {
        workspaces.first { $0.id == workspaceID }
    }

    var body: some View {
        Group {
            if let workspace {
                editor(workspace)
            } else {
                VStack(spacing: 12) {
                    Text("工作台已不存在").font(.headline)
                    Button("关闭") { dismiss() }
                }
                .padding(30)
                .frame(width: 420)
            }
        }
        .onChange(of: workspace?.id, initial: true) { _, _ in
            loadIfNeeded()
        }
    }

    private func editor(_ workspace: Workspace) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("工作台设置").font(.title2.weight(.semibold))
                        Text(workspace.isGlobal
                             ? "全局工作台是启动后的默认总览；布局与筛选都可以自定义，但不能删除。"
                             : "场景只保存视图与筛选配置。删除场景不会删除任务、项目、标签或日程。")
                            .font(.caption).foregroundStyle(SelnoDesign.secondary)
                    }

                    WorkspaceSection(title: "名称与外观") {
                        HStack(spacing: 9) {
                            TextField("Emoji", text: $emoji)
                                .frame(width: 58)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("workspace.editor.emoji")
                            TextField("工作台名称", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("workspace.editor.name")
                        }
                        WorkspaceAccentPicker(accent: $accent)
                        if workspace.isGlobal {
                            Label("全局工作台", systemImage: "globe")
                                .font(.caption).foregroundStyle(SelnoDesign.accentSecondary)
                        }
                    }

                    WorkspaceSection(title: "默认筛选") {
                        WorkspaceFilterDisclosure(identifier: "workspace.editor.filter",
                                                  isExpanded: $filterExpanded,
                                                  summary: filter.summary()) {
                            TaskFilterEditor(filter: $filter)
                                .padding(.top, 8)
                        }
                        Text("默认筛选由选择“继承场景”的模块共享。模块也可以选择全局数据或自定义规则。")
                            .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                    }

                    if let error {
                        Text(error).font(.caption).foregroundStyle(SelnoDesign.danger)
                    }

                    if !workspace.isGlobal {
                        WorkspaceSection(title: "删除场景") {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("只删除此场景的模块布局与筛选。")
                                        .font(.caption)
                                    Text("任务、项目、标签、日程与备份中的业务记录全部保留。")
                                        .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                                }
                                Spacer()
                                Button("删除场景…", role: .destructive) { confirmDelete = true }
                                    .accessibilityIdentifier("workspace.editor.delete")
                            }
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save(workspace) }
                    .buttonStyle(SelnoButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("workspace.editor.save")
            }
            .padding(16)
        }
        .frame(width: 680, height: 740)
        .tint(SelnoDesign.accent)
        .confirmationDialog("删除此场景？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除场景", role: .destructive) { delete(workspace) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除工作台的模块与筛选配置，不会删除任何任务、项目、标签或日程。")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.editor")
    }

    private func loadIfNeeded() {
        guard !loaded, let workspace else { return }
        loaded = true
        name = workspace.name
        emoji = workspace.emoji
        accent = workspace.accent
        filter = workspace.filter
    }

    private func save(_ workspace: Workspace) {
        do {
            try WorkspaceService(context: context).updateWorkspace(
                workspace.id, name: name, emoji: emoji, accent: accent, filter: filter
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ workspace: Workspace) {
        do {
            try WorkspaceService(context: context).deleteWorkspace(workspace.id)
            onDeleted()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Shared controls

/// A whole-row filter disclosure.
///
/// A stock `DisclosureGroup` on macOS only expands when its small chevron is
/// hit; the label behaves like static text, so clicking the summary does
/// nothing and the row offers no large accessibility target. This control
/// keeps the same visual language while making the entire row a button.
struct WorkspaceFilterDisclosure<Content: View>: View {
    let identifier: String
    @Binding var isExpanded: Bool
    let summary: String
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                let update = { isExpanded.toggle() }
                if reduceMotion {
                    update()
                } else {
                    withAnimation(.easeInOut(duration: 0.16), update)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SelnoDesign.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(isExpanded ? "收起筛选规则" : summary)
                        .font(.caption)
                        .foregroundStyle(SelnoDesign.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("筛选规则")
            .accessibilityValue(isExpanded ? "已展开" : "已收起")
            .accessibilityHint("展开或收起筛选规则")
            .accessibilityIdentifier(identifier)

            if isExpanded {
                content
                    .padding(.top, 3)
                    .transition(reduceMotion ? .identity
                                : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct WorkspaceAccentPicker: View {
    @Binding var accent: WorkspaceAccent

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 7)],
                  alignment: .leading, spacing: 7) {
            ForEach(WorkspaceAccent.allCases) { value in
                Button { accent = value } label: {
                    HStack(spacing: 5) {
                        Circle().fill(value.color).frame(width: 10, height: 10)
                        Text(value.title).lineLimit(1)
                        if accent == value { Image(systemName: "checkmark").font(.caption2) }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(accent == value ? value.color.opacity(0.12) : SelnoDesign.canvas,
                                in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(accent == value ? value.color.opacity(0.5) : SelnoDesign.border.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.title)
                .accessibilityValue(accent == value ? "已选择" : "未选择")
                .accessibilityIdentifier("workspace.accent.\(value.rawValue)")
            }
        }
    }
}

struct WorkspaceSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SelnoDesign.secondary)
            content
        }
    }
}