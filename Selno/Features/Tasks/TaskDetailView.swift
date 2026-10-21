import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let task: TodoTask
    @Query private var reminders: [TaskReminder]
    @State private var isEditing = false
    @State private var presentedError: PresentedError?
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var deleting = false

    init(task: TodoTask) {
        self.task = task
        let taskID = task.id
        _reminders = Query(
            filter: #Predicate<TaskReminder> { $0.taskID == taskID },
            sort: [SortDescriptor(\TaskReminder.createdAt)]
        )
    }

    var body: some View {
        Form {
            Section {
                Text(task.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("task.detail.title")
                LabeledContent("状态", value: task.status.title)
                LabeledContent("重要性", value: task.importance.title)
                TaskTags(task: task, limit: 4)
                if !task.notes.isEmpty {
                    Text(task.notes).textSelection(.enabled)
                }
            }
            if let instance = task.templateInstance { StructuredTaskDetail(instance: instance) }
            MilestoneDetailRows(task: task)
            Section("安排") {
                dateRow("计划开始", date: task.plannedStartAt)
                dateRow("计划日期", date: task.plannedAt)
                dateRow("截止日期", date: task.dueAt)
                LabeledContent("项目", value: task.project?.name ?? "未指定")
            }
            if !reminders.isEmpty {
                Section("提醒") {
                    ForEach(reminders) { reminder in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: reminder.kind == .due ? "clock.arrow.circlepath" : "alarm")
                                .foregroundStyle(SelnoDesign.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(reminder.kind.title)
                                Text(reminder.leadDescription)
                                    .font(.caption).foregroundStyle(SelnoDesign.secondary)
                                if let snooze = reminder.snoozeUntil, snooze > .now {
                                    Text("已延后到 \(snooze.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2).foregroundStyle(SelnoDesign.accent)
                                }
                            }
                            Spacer()
                            Text(reminder.state.title)
                                .font(.caption)
                                .foregroundStyle(reminderStateColor(reminder.state))
                        }
                    }
                }
            }
            if !task.orderedSteps.isEmpty {
                Section("子任务 · \(task.completedStepCount)/\(task.orderedSteps.count)") {
                    ForEach(task.orderedSteps) { step in
                        Toggle(step.title, isOn: Binding(
                            get: { step.isCompleted },
                            set: { _ in toggleStep(step) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Section("记录") {
                LabeledContent("创建时间") { Text(task.createdAt, format: .dateTime) }
                LabeledContent("更新时间") { Text(task.updatedAt, format: .dateTime) }
                if let completedAt = task.completedAt {
                    LabeledContent("完成时间") { Text(completedAt, format: .dateTime) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("任务详情")
        .toolbar {
            ToolbarItem {
                Button("编辑") { isEditing = true }
                    .accessibilityIdentifier("task.edit")
            }
            ToolbarItem {
                Menu {
                    Button("保存为模板") { templateName = task.title + " 模板"; savingTemplate = true }
                    Button("删除任务", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityIdentifier("task.more")
            }
        }
        .sheet(isPresented: $isEditing) { TaskEditorView(task: task) }
        .alert("保存为模板", isPresented: $savingTemplate) {
            TextField("模板名称", text: $templateName)
            Button("保存") {
                do { try TemplateService(context: context).saveTaskAsTemplate(task, name: templateName) }
                catch { presentedError = PresentedError("无法保存模板", error: error) }
            }
            Button("取消", role: .cancel) { }
        } message: { Text("保留字段和默认内容，不复制已经过去的日期及提醒。") }
        .confirmationDialog("删除任务及其关联时间节点？", isPresented: $deleting) {
            Button("删除任务", role: .destructive) {
                do {
                    let snapshot = try TaskService(context: context).delete(task)
                    TaskUndoCenter.shared.offer(snapshot)
                    dismiss()
                } catch {
                    presentedError = PresentedError("无法删除任务", error: error)
                }
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("好")))
        }
    }

    private func reminderStateColor(_ state: TaskReminderState) -> Color {
        switch state {
        case .scheduled: SelnoDesign.success
        case .blocked, .failed: SelnoDesign.warning
        case .expired, .paused, .duplicate: SelnoDesign.secondary
        case .pending, .unconfigured: SelnoDesign.secondary
        }
    }

    private func dateRow(_ title: String, date: Date?) -> some View {
        LabeledContent(title) {
            if let date {
                Text(date, format: .dateTime.year().month().day().hour().minute())
            } else {
                Text("未设置").foregroundStyle(.secondary)
            }
        }
    }

    private func toggleStep(_ step: TaskStep) {
        do {
            try TaskService(context: context).toggleStepCompletion(step)
        } catch {
            presentedError = PresentedError("无法更新子任务", error: error)
        }
    }
}
