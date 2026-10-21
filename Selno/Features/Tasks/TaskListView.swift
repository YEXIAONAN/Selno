import SwiftUI
import SwiftData

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Query(sort: \TaskCategory.sortOrder) private var tags: [TaskCategory]
    let scope: TaskListScope
    let tasks: [TodoTask]
    @Binding var selectedTaskID: UUID?
    let focusRequest: Int
    var events: [CalendarEvent] = []
    var openEvent: (CalendarEvent) -> Void = { _ in }
    @State private var title = ""
    @State private var presentedError: PresentedError?
    @State private var filterTagID: UUID?
    @State private var sortMode = "默认"
    @State private var templateCreation = false
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let filtered = scope.tasks(from: tasks, on: timeline.date, calendar: calendar).filter { task in
                filterTagID == nil || task.visibleTags.contains { $0.id == filterTagID }
            }
            let visibleTasks = sorted(filtered)
            VStack(spacing: 0) {
                HStack {
                    Picker("标签", selection: $filterTagID) {
                        Text("全部标签").tag(nil as UUID?)
                        ForEach(tags) { Text("\($0.emoji) \($0.name)").tag(Optional($0.id)) }
                    }.labelsHidden().accessibilityIdentifier("tags.filter")
                    Picker("排序", selection: $sortMode) { ForEach(["默认", "截止日期", "重要性"], id: \.self) { Text($0).tag($0) } }.labelsHidden().fixedSize()
                }.controlSize(.small).padding(12)
                if visibleTasks.isEmpty && events.isEmpty {
                    ContentUnavailableView(scope.title, systemImage: scope.symbolName,
                                           description: Text(scope.emptyDescription))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedTaskID) {
                        if !events.isEmpty {
                            Section("日程") {
                                ForEach(events) { event in
                                    CalendarEventAgendaRow(event: event, calendar: calendar) { openEvent(event) }
                                }
                            }
                        }
                        taskSection("待办", tasks: visibleTasks.filter { $0.status.isActive })
                        taskSection("已完成", tasks: visibleTasks.filter { $0.status == .completed })
                        taskSection("已取消", tasks: visibleTasks.filter { $0.status == .cancelled })
                    }
                    .accessibilityIdentifier("task.list")
                }
                Divider()
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
                HStack { Button("从模板创建") { templateCreation = true }.buttonStyle(.link).accessibilityIdentifier("task.fromTemplate"); Spacer(); Text("↩ 快速记录").font(.caption).foregroundStyle(SelnoDesign.tertiary) }.padding(.horizontal, 14).padding(.bottom, 12)
            }
            .navigationTitle(scope.title)
        }
        .onChange(of: focusRequest) { _, _ in quickAddFocused = true }
        .onChange(of: filterTagID) { _, id in
            if let id, let task = tasks.first(where: { $0.id == selectedTaskID }),
               !task.visibleTags.contains(where: { $0.id == id }) { selectedTaskID = nil }
        }
        .onChange(of: tags.map(\.id)) { _, ids in
            if let filterTagID, !ids.contains(filterTagID) { self.filterTagID = nil }
        }
        .sheet(isPresented: $templateCreation) { TaskEditorView(calendar: calendar) }
        .alert(item: $presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("好")))
        }
    }
    private func sorted(_ values: [TodoTask]) -> [TodoTask] {
        if sortMode == "截止日期" { return values.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) } }
        if sortMode == "重要性" { return values.sorted { $0.importance.sortPriority > $1.importance.sortPriority } }
        return values
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
                }
            }
        }
    }

    private func createTask() {
        do {
            let task = try TaskService(context: context).createTask(title: title)
            title = ""
            selectedTaskID = task.id
            quickAddFocused = true
        } catch {
            presentedError = PresentedError("无法创建任务", error: error)
        }
    }
}
