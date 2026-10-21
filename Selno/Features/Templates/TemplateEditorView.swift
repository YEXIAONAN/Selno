import SwiftUI
import SwiftData

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskCategory.sortOrder) private var tags: [TaskCategory]
    let template: TaskTemplate?
    @State private var name: String
    @State private var emoji: String
    @State private var definition: TemplateDefinition
    @State private var error: String?
    private var canEdit: Bool {
        template == nil || (template?.definition.map { $0.version == 1 && $0.fields.allSatisfy(\.isSupported) } ?? false)
    }
    init(template: TaskTemplate? = nil) {
        self.template = template; _name = State(initialValue: template?.name ?? ""); _emoji = State(initialValue: template?.emoji ?? "")
        _definition = State(initialValue: template?.definition ?? .init())
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(template == nil ? "新建模板" : "编辑模板").font(.title2.weight(.semibold)); Spacer() }.padding(20)
            Form {
                if !canEdit {
                    Text("此模板数据版本暂不支持编辑，原始字段将完整保留。请更新应用后再试。")
                        .foregroundStyle(SelnoDesign.warning)
                }
                Section("模板信息") {
                    TextField("模板名称", text: $name).accessibilityIdentifier("template.editor.name")
                    TextField("Emoji（可选）", text: $emoji)
                    Picker("默认重要性", selection: $definition.defaultImportanceRaw) { ForEach(TaskImportance.allCases) { Text($0.title).tag($0.rawValue) } }
                    TagSelection(tags: tags, selectedIDs: Binding(get: { Set(definition.defaultTagIDs) }, set: { definition.defaultTagIDs = Array($0) }))
                }
                Section("字段 · 点击展开编辑") {
                    ForEach($definition.fields) { $field in
                        TemplateFieldEditor(field: $field, move: { direction in move(field.id, direction) }, remove: { definition.fields.removeAll { $0.id == field.id } })
                    }
                    Menu {
                        ForEach(TemplateFieldKind.allCases) { kind in Button(kind.title) { definition.fields.append(TemplateField("新字段", kind: kind)) } }
                    } label: { Label("添加字段", systemImage: "plus").foregroundStyle(SelnoDesign.accent) }
                    .menuStyle(.borderlessButton)
                    .accessibilityIdentifier("template.editor.addField")
                }
            }.formStyle(.grouped).disabled(!canEdit)
            if let error { Text(error).font(.caption).foregroundStyle(SelnoDesign.danger).padding(.horizontal) }
            HStack { Text("模板变更不会改写历史任务").font(.caption).foregroundStyle(SelnoDesign.secondary); Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(!canEdit).accessibilityIdentifier("template.editor.save") }.padding(18)
        }.frame(width: 620, height: 650).tint(SelnoDesign.accent)
    }
    private func move(_ id: UUID, _ direction: Int) {
        guard let index = definition.fields.firstIndex(where: { $0.id == id }), definition.fields.indices.contains(index + direction) else { return }
        definition.fields.swapAt(index, index + direction)
    }
    private func save() {
        do { try TemplateService(context: context).save(template, name: name, emoji: emoji, definition: definition); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct TemplateFieldEditor: View {
    @Binding var field: TemplateField
    @State private var expanded = false
    let move: (Int) -> Void
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expanded.toggle() } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption).frame(width: 12)
                    Text(field.name); Spacer(); Text(field.kind.title).font(.caption).foregroundStyle(SelnoDesign.secondary)
                }
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("template.field.toggle.\(field.id)")
                .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
                LabeledContent("字段名称") { TextField("字段名称", text: $field.name).labelsHidden().accessibilityIdentifier("template.field.name") }
                LabeledContent("分组") { TextField("分组", text: $field.group).labelsHidden() }
                Picker("类型", selection: $field.kindRaw) { ForEach(TemplateFieldKind.allCases) { Text($0.title).tag($0.rawValue) } }
                HStack { Toggle("可选", isOn: $field.isOptional); Toggle("显示", isOn: $field.isVisible) }.toggleStyle(.checkbox)
                if field.kind == .dateTime {
                    Picker("时间含义", selection: $field.semanticRaw) { ForEach(MilestoneSemantic.allCases) { Text($0.title).tag($0.rawValue) } }
                    Toggle("设置默认日期", isOn: Binding(get: { field.defaultDate != nil }, set: { field.defaultDate = $0 ? .now : nil })).toggleStyle(.checkbox)
                    if field.defaultDate != nil { DatePicker("默认日期", selection: Binding(get: { field.defaultDate ?? .now }, set: { field.defaultDate = $0 })) }
                } else { LabeledContent("默认内容") { TextField("默认内容", text: $field.defaultText).labelsHidden() } }
                HStack {
                    Button { move(-1) } label: { Label("上移", systemImage: "arrow.up") }
                    Button { move(1) } label: { Label("下移", systemImage: "arrow.down") }
                    Spacer(); Button("移除字段", role: .destructive, action: remove)
                }.controlSize(.small)
            }
        }
    }
}
