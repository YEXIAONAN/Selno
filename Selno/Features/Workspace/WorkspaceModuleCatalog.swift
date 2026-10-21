import SwiftUI
import SwiftData

// MARK: - Catalog

struct ModuleCatalogView: View {
    let isGlobal: Bool
    let onAdd: (WorkspaceModuleKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [WorkspaceModuleDescriptor] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return WorkspaceModuleRegistry.all }
        return WorkspaceModuleRegistry.all.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.purpose.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("模块目录").font(.title2.weight(.semibold))
                    Text(isGlobal
                         ? "全局工作台与场景使用同一份本地数据，模块只改变呈现方式。"
                         : "添加模块不会复制数据；切换场景只切换视图与筛选。")
                        .font(.caption).foregroundStyle(SelnoDesign.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(22)
            TextField("搜索模块", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
                .accessibilityIdentifier("catalog.search")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ModuleCatalogCategory.allCases) { category in
                        let descriptors = filtered.filter { $0.category == category }
                        if !descriptors.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SelnoDesign.secondary)
                                ForEach(descriptors) { descriptor in
                                    catalogRow(descriptor)
                                }
                            }
                        }
                    }
                    if filtered.isEmpty {
                        QuietEmptyState(title: "没有匹配的模块",
                                        message: "模块目录只包含 Selno 内置模块，不连接插件市场或网络。")
                    }
                }
                .padding(22)
            }
            Divider()
            HStack {
                Text("共 \(WorkspaceModuleRegistry.all.count) 个内置模块")
                    .font(.caption).foregroundStyle(SelnoDesign.tertiary)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(SelnoButtonStyle(primary: true))
            }
            .padding(14)
        }
        .frame(width: 620, height: 660)
        .tint(SelnoDesign.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.catalog")
    }

    private func catalogRow(_ descriptor: WorkspaceModuleDescriptor) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: descriptor.symbolName)
                .font(.title3)
                .frame(width: 30, height: 30)
                .foregroundStyle(SelnoDesign.accent)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(descriptor.title).font(.subheadline.weight(.semibold))
                    Text(descriptor.sizeList)
                        .font(.caption2).foregroundStyle(SelnoDesign.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(SelnoDesign.canvas, in: Capsule())
                }
                Text(descriptor.purpose)
                    .font(.caption).foregroundStyle(SelnoDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("添加") { onAdd(descriptor.kind) }
                .buttonStyle(SelnoButtonStyle())
                .accessibilityIdentifier("catalog.add.\(descriptor.kind.rawValue)")
        }
        .padding(12)
        .background(SelnoDesign.canvas.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(SelnoDesign.border.opacity(0.35)))
    }
}

// MARK: - Module configuration

struct ModuleConfigurationView: View {
    @Binding var draft: [WorkspaceModuleSnapshot]
    let moduleID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedTaskView.name) private var savedViews: [SavedTaskView]

    @State private var size: ModuleSize
    @State private var scope: ModuleDataScope
    @State private var savedViewID: UUID?
    @State private var config: WorkspaceModuleConfig
    @State private var error: String?

    init(moduleID: UUID, draft: Binding<[WorkspaceModuleSnapshot]>) {
        self.moduleID = moduleID
        _draft = draft
        let module = draft.wrappedValue.first { $0.id == moduleID }
        _size = State(initialValue: module?.effectiveSize ?? .medium)
        _scope = State(initialValue: module?.dataScope ?? .inherit)
        _savedViewID = State(initialValue: module?.savedViewID)
        _config = State(initialValue: module?.config ?? .default)
    }

    private var module: WorkspaceModuleSnapshot? {
        draft.first { $0.id == moduleID }
    }

    private var descriptor: WorkspaceModuleDescriptor? { module?.descriptor }

    private var filterBinding: Binding<TaskFilterExpression> {
        Binding(get: { config.filter ?? .unrestricted },
                set: { config.filter = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let module, let descriptor {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Image(systemName: descriptor.symbolName)
                                .font(.title2).foregroundStyle(SelnoDesign.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("配置 \(descriptor.title)")
                                    .font(.title2.weight(.semibold))
                                Text(descriptor.purpose)
                                    .font(.caption).foregroundStyle(SelnoDesign.secondary)
                            }
                        }

                        ConfigSection(title: "尺寸") {
                            Picker("尺寸", selection: $size) {
                                ForEach(descriptor.supportedSizes) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityIdentifier("module.config.size")
                            Text("\(size.title)号会按当前列数自动换算跨度；窄窗口下自动变为整行，不会溢出。")
                                .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                        }

                        if descriptor.kind == .taskList {
                            ConfigSection(title: "任务视图") {
                                Picker("数据来源", selection: $savedViewID) {
                                    Text("不使用已保存视图").tag(nil as UUID?)
                                    ForEach(savedViews) { view in
                                        Text("\(view.emoji) \(view.name)").tag(Optional(view.id))
                                    }
                                }
                                .accessibilityIdentifier("module.config.savedView")
                                Text(savedViewID == nil
                                     ? "使用下方自定义规则；规则整体替代场景筛选，而不是叠加。"
                                     : "已保存视图提供完整筛选、排序与数量；模块范围固定为自定义。")
                                    .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                            }
                        }

                        if descriptor.kind.isDataDriven {
                            ConfigSection(title: "数据范围") {
                                Picker("数据范围", selection: $scope) {
                                    ForEach(ModuleDataScope.allCases) { value in
                                        Text(value.title).tag(value)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .disabled(savedViewID != nil)
                                .accessibilityIdentifier("module.config.scope")
                                Text(scopeDetail)
                                    .font(.caption).foregroundStyle(SelnoDesign.secondary)
                            }
                        }

                        if descriptor.kind == .upcoming {
                            ConfigSection(title: "近期范围") {
                                Picker("近期范围", selection: Binding(
                                    get: { config.effectiveDays },
                                    set: { config.days = $0 }
                                )) {
                                    Text("未来 3 天").tag(3)
                                    Text("未来 7 天").tag(7)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .accessibilityIdentifier("module.config.days")
                            }
                        }

                        if savedViewID == nil && scope == .custom && descriptor.kind.isDataDriven {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("自定义筛选")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SelnoDesign.secondary)
                                TaskFilterEditor(filter: filterBinding)
                            }
                        }

                        if descriptor.kind == .taskList {
                            ConfigSection(title: "显示") {
                                Picker("排序", selection: Binding(
                                    get: { config.sort },
                                    set: { config.sortRaw = $0.rawValue }
                                )) {
                                    ForEach(TaskSortMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .disabled(savedViewID != nil)
                                Stepper("最多 \(config.effectiveLimit) 项",
                                        value: Binding(get: { config.effectiveLimit },
                                                       set: { config.limit = $0 }),
                                        in: WorkspaceLimits.taskListLimitRange)
                                    .disabled(savedViewID != nil)
                                    .accessibilityIdentifier("module.config.limit")
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
                    Button("应用") { apply(module: module) }
                        .buttonStyle(SelnoButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("module.config.save")
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Text("模块已不存在").font(.headline)
                    Button("关闭") { dismiss() }
                }
                .padding(30)
            }
        }
        .frame(width: 660, height: 720)
        .tint(SelnoDesign.accent)
        .onChange(of: savedViewID) { _, value in
            if value != nil { scope = .custom }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.module.config")
    }

    private var scopeDetail: String {
        if savedViewID != nil { return "已保存视图是完整规则集，范围固定为自定义。" }
        switch scope {
        case .inherit: return "继承场景的默认筛选；修改场景规则时此模块随之变化。"
        case .global: return "忽略场景规则，读取全部本地业务数据。"
        case .custom: return "使用模块自己的规则，完全替代场景筛选。"
        }
    }

    private func apply(module: WorkspaceModuleSnapshot) {
        guard let index = draft.firstIndex(where: { $0.id == moduleID }),
              let descriptor = module.descriptor else { return }
        guard descriptor.supports(size) else {
            error = WorkspaceError.unsupportedSize.localizedDescription
            return
        }
        var filter = config.filter ?? .unrestricted
        do {
            filter = try filter.validated()
            var value = config
            value.filter = filter
            value = value.sanitized()
            var updated = module
            updated.sizeRaw = size.rawValue
            updated.scopeRaw = (savedViewID == nil ? scope : .custom).rawValue
            updated.savedViewID = savedViewID
            updated.config = value.sanitized()
            updated.rawConfigData = value.sanitized().encoded(preserving: module.rawConfigData)
            updated.updatedAt = Date.now
            draft[index] = updated
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ConfigSection<Content: View>: View {
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