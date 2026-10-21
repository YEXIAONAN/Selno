import SwiftUI
import SwiftData

struct SettingsWorkspace: View {
    var body: some View {
        TabView {
            DataManagementView().tabItem { Label("数据管理", systemImage: "externaldrive") }
            ReminderSettingsView().tabItem { Label("提醒", systemImage: "bell") }
            TemplateManagementView().tabItem { Label("任务模板", systemImage: "square.stack") }
            SavedViewManagementView().tabItem { Label("任务视图", systemImage: "line.3.horizontal.decrease.circle") }
            TagManagementView().tabItem { Label("标签", systemImage: "tag") }
        }.frame(width: 760, height: 650).tint(SelnoDesign.accent)
    }
}

private struct TemplateManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskTemplate.createdAt) private var templates: [TaskTemplate]
    @State private var isCreating = false
    @State private var editing: TaskTemplate?
    @State private var deleting: TaskTemplate?
    @State private var error: PresentedError?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("任务模板").font(.title2.weight(.semibold)); Spacer(); Button("新建模板") { isCreating = true }.accessibilityIdentifier("templates.new") }
            Text("字段、顺序与默认值可自由编辑。历史任务使用自己的快照，不受模板变动影响。")
                .font(.callout).foregroundStyle(SelnoDesign.secondary)
            List(templates) { template in
                HStack {
                    Text(template.emoji.isEmpty ? "📝" : template.emoji).font(.title2).frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) { Text(template.name).fontWeight(.medium); Text("\(template.definition?.fields.count ?? 0) 个字段 · 版本 \(template.revision)").font(.caption).foregroundStyle(SelnoDesign.secondary) }
                    Spacer()
                    Button("编辑") { editing = template }.accessibilityIdentifier("template.edit.\(template.id)")
                    Menu {
                        Button("复制模板") { perform { _ = try TemplateService(context: context).duplicate(template) } }
                        Button("删除模板", role: .destructive) { deleting = template }
                    } label: { Image(systemName: "ellipsis") }.fixedSize()
                }.padding(.vertical, 7)
            }.accessibilityIdentifier("templates.list")
            if templates.isEmpty { QuietEmptyState(title: "创建自己的工作方式", message: "从常用字段开始，模板可以随时调整。") }
        }.padding(24)
            .sheet(isPresented: $isCreating) { TemplateEditorView() }
            .sheet(item: $editing) { TemplateEditorView(template: $0) }
            .confirmationDialog("删除此模板？已创建的任务将完整保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("删除模板", role: .destructive) { if let deleting { perform { try TemplateService(context: context).delete(deleting) } }; deleting = nil }
            }
            .alert(item: $error) { Alert(title: Text($0.title), message: Text($0.message)) }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = PresentedError("无法更新模板", error: error) } }
}

struct TagManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskCategory.sortOrder) private var tags: [TaskCategory]
    @State private var isCreating = false
    @State private var editing: TaskCategory?
    @State private var deleting: TaskCategory?
    @State private var error: PresentedError?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("标签").font(.title2.weight(.semibold)); Spacer(); Button("新建标签") { isCreating = true }.accessibilityIdentifier("tags.new") }
            Text("颜色用来识别事务类别，不替代重要性、截止或完成状态。Emoji 可以留空。")
                .font(.callout).foregroundStyle(SelnoDesign.secondary)
            List(tags) { tag in
                HStack {
                    TagChip(tag: tag).frame(maxWidth: 240, alignment: .leading)
                    Spacer()
                    Button("编辑") { editing = tag }.accessibilityIdentifier("tag.edit.\(tag.id)")
                    Button(role: .destructive) { deleting = tag } label: { Image(systemName: "trash") }.help("删除标签，保留任务")
                }.padding(.vertical, 5)
            }
        }.padding(24)
            .sheet(isPresented: $isCreating) { TagEditorView() }
            .sheet(item: $editing) { TagEditorView(tag: $0) }
            .confirmationDialog("删除此标签？任务仍会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("删除标签", role: .destructive) {
                    do { if let deleting { try TagService(context: context).delete(deleting) }; deleting = nil }
                    catch { self.error = PresentedError("无法删除标签", error: error) }
                }
            }
            .alert(item: $error) { Alert(title: Text($0.title), message: Text($0.message)) }
    }
}

private struct TagEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let tag: TaskCategory?
    @State private var name: String
    @State private var emoji: String
    @State private var color: String
    @State private var error: String?
    init(tag: TaskCategory? = nil) {
        self.tag = tag; _name = State(initialValue: tag?.name ?? ""); _emoji = State(initialValue: tag?.emoji ?? "")
        _color = State(initialValue: tag?.colorHex ?? TagPalette.sage.rawValue)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tag == nil ? "新建标签" : "编辑标签").font(.title2.weight(.semibold))
            Form {
                TextField("名称", text: $name).accessibilityIdentifier("tag.editor.name")
                TextField("Emoji（可选）", text: $emoji).accessibilityIdentifier("tag.editor.emoji")
                Picker("颜色", selection: $color) {
                    if !TagPalette.allCases.contains(where: { $0.rawValue == color }) { Text("原有颜色").tag(color) }
                    ForEach(TagPalette.allCases) { Label($0.title, systemImage: "circle.fill").foregroundStyle(TagPalette.color($0.rawValue, dark: false)).tag($0.rawValue) }
                }.accessibilityIdentifier("tag.editor.color")
            }
            if let error { Text(error).font(.caption).foregroundStyle(SelnoDesign.danger) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") { save() }.keyboardShortcut(.defaultAction).accessibilityIdentifier("tag.editor.save") }
        }.padding(24).frame(width: 420)
    }
    private func save() {
        do { try TagService(context: context).save(tag, name: name, emoji: emoji, color: color); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
