import SwiftUI
import SwiftData

struct ProjectWorkspace: View {
    @Query(sort: \TodoProject.updatedAt, order: .reverse) private var projects: [TodoProject]
    let calendar: Calendar
    var initialProjectID: UUID?
    @State private var selectedProject: TodoProject?
    @State private var isCreating = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("项目").font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("把相关的事情放在一起，持续向前。 ").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if projects.isEmpty {
                        WorkspaceCard {
                            QuietEmptyState(title: "从一个正在推进的项目开始", message: "创建项目、加入任务，在这里查看完成进度和逾期情况。")
                            Button("创建项目") { isCreating = true }.accessibilityIdentifier("projects.empty.create")
                        }
                    } else {
                        projectGroup(archived: false, now: timeline.date)
                        projectGroup(archived: true, now: timeline.date)
                    }
                }.padding(26).frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .top)
            }.background(WorkspaceStyle.canvas)
        }
        .navigationTitle("项目")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isCreating = true } label: { Label("新建项目", systemImage: "plus") }
                    .accessibilityIdentifier("projects.new")
            }
        }
        .sheet(isPresented: $isCreating) { ProjectEditorView() }
        .sheet(item: $selectedProject) { ProjectDetailView(project: $0, calendar: calendar) }
        .onAppear { if let initialProjectID { selectedProject = projects.first { $0.id == initialProjectID } } }
        .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }

    @ViewBuilder private func projectGroup(archived: Bool, now: Date) -> some View {
        let visible = projects.filter { ($0.archivedAt != nil) == archived }
        if !visible.isEmpty {
            Text(archived ? "已归档 · \(visible.count)" : "进行中 · \(visible.count)").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 275), spacing: 18)], spacing: 18) {
                ForEach(visible) { project in
                    Button { selectedProject = project } label: {
                        WorkspaceCard {
                            ProjectProgressView(project: project, calendar: calendar, now: now)
                            if !project.notes.isEmpty { Text(project.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(projectLabel(project, now: now))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("projects.open.\(project.id)")
                }
            }
        }
    }

    private func projectLabel(_ project: TodoProject, now: Date) -> String {
        let progress = ProjectProgress(project: project, now: now, calendar: calendar)
        return "\(project.name)，\(progress.completed) / \(progress.total) 已完成，\(progress.overdue) 项逾期"
    }
}

struct ProjectEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let project: TodoProject?
    @State private var name: String
    @State private var notes: String
    @State private var error: String?
    @FocusState private var isNameFocused: Bool

    init(project: TodoProject? = nil) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _notes = State(initialValue: project?.notes ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(project == nil ? "新建项目" : "编辑项目").font(.title2.weight(.semibold))
            Form {
                TextField("名称", text: $name).focused($isNameFocused).accessibilityIdentifier("project.editor.name")
                TextField("备注", text: $notes, axis: .vertical).lineLimit(3...5).accessibilityIdentifier("project.editor.notes")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).accessibilityIdentifier("project.editor.save")
            }
        }.padding(24).frame(width: 440).onAppear { isNameFocused = true }
    }
    private func save() {
        do { try ProjectService(context: context).save(project: project, name: name, notes: notes); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct ProjectDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TodoTask]
    let project: TodoProject
    let calendar: Calendar
    @State private var quickTitle = ""
    @State private var selection: AgendaSelection?
    @State private var isEditing = false
    @State private var presentedError: PresentedError?

    init(project: TodoProject, calendar: Calendar) {
        self.project = project; self.calendar = calendar
        let projectID = project.id
        _tasks = Query(filter: #Predicate<TodoTask> { $0.project?.id == projectID }, sort: \TodoTask.createdAt)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(project.name).font(.title2.weight(.semibold))
                Spacer()
                Button("编辑") { isEditing = true }.accessibilityIdentifier("project.edit")
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ProjectProgressView(project: project, calendar: calendar, now: .now).accessibilityIdentifier("project.progress")
            if !project.notes.isEmpty { Text(project.notes).font(.subheadline).foregroundStyle(.secondary) }
            Divider()
            ScrollView {
                VStack(spacing: 3) {
                    if tasks.isEmpty { QuietEmptyState(title: "项目还没有任务", message: "在下方添加一项需要推进的事。 ").frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(tasks.sorted { $0.status.isActive && !$1.status.isActive }) { task in
                        HStack(spacing: 10) {
                            Button { toggle(task) } label: { Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle").font(.title3) }
                                .buttonStyle(.plain).disabled(task.status == .cancelled)
                                .accessibilityLabel(task.status == .completed ? "恢复为未完成" : "标记为完成")
                                .accessibilityIdentifier("project.complete.\(task.id)")
                            Button { selection = .task(task) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).strikethrough(task.status == .completed)
                                    Text(task.status.title).font(.caption).foregroundStyle(.secondary)
                                    TaskTags(task: task)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }.padding(.vertical, 9)
                    }
                }
            }
            HStack {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("添加项目任务…", text: $quickTitle).onSubmit(addTask).accessibilityIdentifier("project.quickAdd")
                Button("添加", action: addTask)
            }
        }.padding(24).frame(width: 540, height: 560)
            .sheet(isPresented: $isEditing) { ProjectEditorView(project: project) }
            .sheet(item: $selection) { AgendaDetailsSheet(selection: $0, calendar: calendar) }
            .alert(item: $presentedError) { Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("好"))) }
    }
    private func addTask() {
        do { try TaskService(context: context).createTask(title: quickTitle, project: project); quickTitle = "" }
        catch { presentedError = PresentedError("无法添加项目任务", error: error) }
    }
    private func toggle(_ task: TodoTask) {
        do { try TaskService(context: context).toggleCompletion(task) }
        catch { presentedError = PresentedError("无法更新任务", error: error) }
    }
}
