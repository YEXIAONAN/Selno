import SwiftUI
import SwiftData

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskTemplate.createdAt) private var templates: [TaskTemplate]
    @Query(sort: \TaskCategory.sortOrder) private var tags: [TaskCategory]
    let task: TodoTask?
    @State private var selectedTemplateID: UUID?
    @State private var saving = false
    @State private var draft: TaskDraft
    @State private var presentedError: PresentedError?

    init(task: TodoTask) {
        self.task = task
        _draft = State(initialValue: TaskDraft(task: task))
    }

    init(plannedDate: Date, calendar: Calendar) {
        task = nil
        _draft = State(initialValue: TaskDraft(plannedAt: CalendarMath.defaultTime(on: plannedDate, calendar: calendar)))
    }
    init(calendar: Calendar) {
        task = nil
        var value = TaskDraft(plannedAt: .now); value.plannedAt = nil
        _draft = State(initialValue: value)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if task == nil {
                    Section("从模板开始") {
                        Picker("任务模板", selection: $selectedTemplateID) {
                            Text("直接创建普通任务").tag(nil as UUID?)
                            ForEach(templates) { template in
                                Text("\(template.emoji) \(template.name)").tag(Optional(template.id))
                                    .disabled(template.definition.map { $0.version != 1 || !$0.fields.allSatisfy(\.isSupported) } ?? true)
                            }
                        }.accessibilityIdentifier("template.selector")
                        SettingsLink { Label("管理模板和标签", systemImage: "slider.horizontal.3") }.font(.caption)
                    }
                }
                Section("基本信息") {
                    TextField("标题", text: $draft.title)
                        .accessibilityIdentifier("task.editor.title")
                    TextField("备注", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("状态", selection: $draft.status) {
                        ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("重要性", selection: $draft.importance) {
                        ForEach(TaskImportance.allCases) { Text($0.title).tag($0) }
                    }
                }
                if !tags.isEmpty {
                    Section("标签") { TagSelection(tags: tags, selectedIDs: $draft.tagIDs) }
                }
                if draft.template != nil {
                    Section("\(draft.template?.name ?? "模板") · 独立任务快照") {
                        TemplateFieldsForm(payload: Binding(get: { draft.template?.payload ?? TemplatePayload(definition: .init()) }, set: { draft.template?.payload = $0 }))
                    }
                } else if task?.templateInstance != nil {
                    Section { Text("结构化数据暂无法编辑；原始记录将完整保留。").foregroundStyle(SelnoDesign.warning) }
                }
                Section("日期安排") {
                    optionalDate("计划日期", value: $draft.plannedAt, identifier: "task.editor.planEnabled")
                    optionalDate("截止日期", value: $draft.dueAt, identifier: "task.editor.dueEnabled")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("task.editor.save")
            }
            .padding()
        }
        .frame(width: 560, height: 640)
        .tint(SelnoDesign.accent)
        .onChange(of: selectedTemplateID) { _, id in
            guard let template = templates.first(where: { $0.id == id }), let definition = template.definition else { draft.template = nil; return }
            draft.template = TemplateTaskDraft(templateID: template.id, name: template.name, revision: template.revision, payload: TemplatePayload(definition: definition))
            draft.importance = TaskImportance(rawValue: definition.defaultImportanceRaw) ?? .normal
            draft.tagIDs = Set(definition.defaultTagIDs)
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("好")))
        }
    }

    private func optionalDate(_ title: String, value: Binding<Date?>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? (value.wrappedValue ?? .now) : nil }
            ))
            .toggleStyle(.checkbox)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
            if value.wrappedValue != nil {
                DatePicker(title, selection: Binding(
                    get: { value.wrappedValue ?? .now },
                    set: { value.wrappedValue = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if let payload = draft.template?.payload { try TemplateValidation.validate(payload) }
            if draft.template?.payload.answers.contains(where: { $0.reminderMinutes != nil && $0.date != nil }) == true {
                guard await SystemReminderGateway().requestPermission() else { throw ReminderError.notAuthorized }
            }
            if let task {
                try TaskService(context: context).update(task, draft: draft)
            } else {
                try TaskService(context: context).createTask(draft: draft)
            }
            dismiss()
        } catch {
            presentedError = PresentedError("无法保存任务", error: error)
        }
    }
}
