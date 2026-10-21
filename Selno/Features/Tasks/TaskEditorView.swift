import AppKit
import SwiftUI
import SwiftData
import UserNotifications

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskTemplate.createdAt) private var templates: [TaskTemplate]
    @Query(sort: \TaskCategory.sortOrder) private var tags: [TaskCategory]
    let task: TodoTask?
    let onSaved: ((TodoTask) -> Void)?
    @State private var selectedTemplateID: UUID?
    @State private var saving = false
    @State private var draft: TaskDraft
    @State private var presentedError: PresentedError?
    @State private var reminderPreferencesLoaded = false
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var dueReminderEnabled = false
    @State private var dueLeadMinutes = 1_440
    @State private var customLeadMinutes = 120
    @State private var scheduledReminderEnabled = false
    @State private var scheduledReminderAt = Date.now.addingTimeInterval(3_600)

    init(task: TodoTask) {
        self.task = task
        onSaved = nil
        _draft = State(initialValue: TaskDraft(task: task))
    }

    init(plannedDate: Date, calendar: Calendar, onSaved: ((TodoTask) -> Void)? = nil) {
        task = nil
        self.onSaved = onSaved
        _draft = State(initialValue: TaskDraft(plannedAt: CalendarMath.defaultTime(on: plannedDate, calendar: calendar)))
    }
    init(calendar: Calendar, onSaved: ((TodoTask) -> Void)? = nil) {
        task = nil
        self.onSaved = onSaved
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
                Section("提醒") {
                    Toggle("截止前提醒", isOn: $dueReminderEnabled)
                        .accessibilityIdentifier("task.editor.dueReminder")
                    if dueReminderEnabled {
                        if draft.dueAt == nil {
                            Label("设置截止日期后才能安排提醒；保存时会自动关闭。", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(SelnoDesign.warning)
                        } else {
                            Picker("提前时间", selection: $dueLeadMinutes) {
                                Text("提前 7 天").tag(10_080)
                                Text("提前 3 天").tag(4_320)
                                Text("提前 1 天").tag(1_440)
                                Text("自定义…").tag(-1)
                            }
                            if dueLeadMinutes == -1 {
                                HStack(spacing: 8) {
                                    TextField("分钟", value: $customLeadMinutes, format: .number)
                                        .frame(width: 90)
                                        .accessibilityIdentifier("task.editor.customLead")
                                    Stepper("", value: $customLeadMinutes, in: 1...525_600)
                                        .labelsHidden()
                                    Text("分钟前").font(.caption).foregroundStyle(SelnoDesign.secondary)
                                }
                            }
                        }
                    }
                    Toggle("指定时间提醒", isOn: $scheduledReminderEnabled)
                        .accessibilityIdentifier("task.editor.scheduledReminder")
                    if scheduledReminderEnabled {
                        DatePicker("提醒时间", selection: $scheduledReminderAt,
                                   displayedComponents: [.date, .hourAndMinute])
                        if scheduledReminderAt <= .now {
                            Label("提醒时间已经过去，不会补发通知。", systemImage: "clock.badge.exclamationmark")
                                .font(.caption).foregroundStyle(SelnoDesign.warning)
                        }
                    }
                    permissionRow
                    Text("提醒由 macOS 通知中心投递。Selno 未运行或处于休眠时不会执行应用内核对；已经错过的提醒不会自动补发。")
                        .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
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
        .onAppear(perform: loadReminderPreferences)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { permissionStatus = await ReminderPermission.status() }
        }
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

    @ViewBuilder
    private var permissionRow: some View {
        switch permissionStatus {
        case .denied:
            HStack {
                Label("通知权限已关闭，提醒不会送达。", systemImage: "bell.slash")
                    .font(.caption).foregroundStyle(SelnoDesign.warning)
                Spacer()
                Button("打开系统设置") { ReminderPermission.openSystemSettings() }
                    .buttonStyle(.link).font(.caption)
            }
        case .notDetermined:
            Label("保存提醒时会请求通知权限。", systemImage: "bell")
                .font(.caption).foregroundStyle(SelnoDesign.secondary)
        default:
            Label("通知已允许。", systemImage: "bell.badge")
                .font(.caption).foregroundStyle(SelnoDesign.success)
        }
    }

    private func loadReminderPreferences() {
        guard !reminderPreferencesLoaded else { return }
        reminderPreferencesLoaded = true
        Task { permissionStatus = await ReminderPermission.status() }
        guard let task else { return }
        let taskID = task.id
        guard let rows = try? context.fetch(
            FetchDescriptor<TaskReminder>(predicate: #Predicate { $0.taskID == taskID })
        ) else { return }
        if let due = rows.filter({ $0.kind == .due }).max(by: { $0.updatedAt < $1.updatedAt }) {
            dueReminderEnabled = true
            if [10_080, 4_320, 1_440].contains(due.leadMinutes) {
                dueLeadMinutes = due.leadMinutes
            } else {
                dueLeadMinutes = -1
                customLeadMinutes = max(1, due.leadMinutes)
            }
        }
        if let scheduled = rows.filter({ $0.kind == .scheduled }).max(by: { $0.updatedAt < $1.updatedAt }),
           let date = scheduled.scheduledAt {
            scheduledReminderEnabled = true
            scheduledReminderAt = date
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
            let dueLead = dueReminderEnabled && draft.dueAt != nil
                ? (dueLeadMinutes == -1 ? min(max(customLeadMinutes, 1), 525_600) : dueLeadMinutes)
                : nil
            draft.dueReminderLeadMinutes = dueLead
            draft.scheduledReminderAt = scheduledReminderEnabled ? scheduledReminderAt : nil
            let wantsMilestoneReminder = draft.template?.payload.answers.contains(where: { $0.reminderMinutes != nil && $0.date != nil }) == true
            if dueLead != nil || draft.scheduledReminderAt != nil || wantsMilestoneReminder {
                guard await ReminderPermission.request() else {
                    permissionStatus = await ReminderPermission.status()
                    throw ReminderError.notAuthorized
                }
                permissionStatus = await ReminderPermission.status()
            }
            let savedTask: TodoTask
            if let task {
                try TaskService(context: context).update(task, draft: draft)
                savedTask = task
            } else {
                savedTask = try TaskService(context: context).createTask(draft: draft)
            }
            onSaved?(savedTask)
            dismiss()
        } catch {
            presentedError = PresentedError("无法保存任务", error: error)
        }
    }
}
