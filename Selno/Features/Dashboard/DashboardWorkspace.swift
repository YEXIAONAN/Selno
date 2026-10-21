import SwiftUI
import SwiftData

struct DashboardWorkspace: View {
    let calendar: Calendar
    let brand: BrandTypingState
    var isToday = false
    let openCalendar: (Date) -> Void
    let navigate: (AppSection) -> Void
    let openProject: (UUID) -> Void

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            DashboardContent(calendar: calendar, brand: brand, now: timeline.date, isToday: isToday,
                             openCalendar: openCalendar, navigate: navigate, openProject: openProject)
                .id(calendar.startOfDay(for: timeline.date))
        }
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .navigationTitle(isToday ? "今天" : "总览")
    }
}

private enum DashboardCreation: String, Identifiable {
    case task, event, project
    var id: String { rawValue }
}

private struct DashboardContent: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query private var overdue: [TodoTask]
    @Query private var events: [CalendarEvent]
    @Query private var milestones: [TaskMilestone]
    @Query private var inbox: [TodoTask]
    @Query private var projects: [TodoProject]
    let calendar: Calendar
    let brand: BrandTypingState
    let now: Date
    let isToday: Bool
    let monthWindow: CalendarWindow
    let openCalendar: (Date) -> Void
    let navigate: (AppSection) -> Void
    let openProject: (UUID) -> Void
    @State private var projection = DashboardProjection()
    @State private var days = 7
    @State private var inboxCount = 0
    @State private var projectCount = 0
    @State private var quickTitle = ""
    @State private var selection: AgendaSelection?
    @State private var creation: DashboardCreation?
    @State private var presentedError: PresentedError?

    init(calendar: Calendar, brand: BrandTypingState, now: Date, isToday: Bool, openCalendar: @escaping (Date) -> Void,
         navigate: @escaping (AppSection) -> Void, openProject: @escaping (UUID) -> Void) {
        self.calendar = calendar; self.brand = brand; self.now = now; self.isToday = isToday
        self.openCalendar = openCalendar; self.navigate = navigate; self.openProject = openProject
        let today = calendar.startOfDay(for: now)
        let month = CalendarMath.window(containing: today, mode: .month, listRange: .month, calendar: calendar)
        monthWindow = month
        let upcomingEnd = calendar.date(byAdding: .day, value: 8, to: today) ?? month.range.end
        let range = DateInterval(start: min(today, month.range.start), end: max(upcomingEnd, month.range.end))
        _tasks = Query(CalendarDataQuery.tasks(in: range))
        _overdue = Query(DashboardDataQuery.overdue(before: today))
        _events = Query(CalendarDataQuery.events(in: range))
        _milestones = Query(CalendarDataQuery.milestones(in: range))
        _inbox = Query(DashboardDataQuery.inbox(limit: 4))
        _projects = Query(DashboardDataQuery.projects(limit: 3))
    }

    private var revision: [String] {
        (tasks + overdue).map { "t\($0.id)\($0.updatedAt.timeIntervalSince1970)\($0.statusRaw)\($0.importanceRaw)\($0.title)\(String(describing: $0.plannedAt))\(String(describing: $0.plannedStartAt))\(String(describing: $0.dueAt))" }
        + milestones.map { "n\($0.id)\($0.date.timeIntervalSince1970)\($0.title)\($0.task?.statusRaw ?? "")" }
        + events.map { "e\($0.id)\($0.updatedAt.timeIntervalSince1970)\($0.startsAt)\($0.endsAt)\($0.title)" }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if isToday {
                        todayLayout(wide: geometry.size.width >= 820)
                    } else {
                        overviewLayout(wide: geometry.size.width >= 820)
                        projectModule
                    }
                }
                .padding(26)
                .frame(maxWidth: 1400)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(WorkspaceStyle.canvas)
            .accessibilityIdentifier(isToday ? "today.workspace" : "dashboard.workspace")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建任务") { creation = .task }.keyboardShortcut("n", modifiers: .command)
                    Button("新建日程") { creation = .event }
                    Button("从模板创建任务") { creation = .task }
                } label: { Label("新建", systemImage: "plus") }
                .accessibilityIdentifier("dashboard.new")
            }
        }
        .onChange(of: revision, initial: true) { _, _ in rebuild() }
        .onChange(of: days) { _, _ in rebuild() }
        .onAppear(perform: refreshCounts)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refreshCounts() }
        .sheet(item: $selection) { AgendaDetailsSheet(selection: $0, calendar: calendar) }
        .sheet(item: $creation) { kind in
            switch kind {
            case .task: TaskEditorView(plannedDate: now, calendar: calendar)
            case .event: CalendarEventEditorView(date: now, calendar: calendar)
            case .project: ProjectEditorView()
            }
        }
        .alert(item: $presentedError) { Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("好"))) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(CalendarMath.fullDate(now, calendar: calendar)).font(.subheadline).foregroundStyle(.secondary)
                    if isToday {
                        Text("专注今天。").font(.system(size: 28, weight: .semibold, design: .rounded)).accessibilityIdentifier("today.heading")
                    } else { BrandHeadline(state: brand) }
                }
                Spacer(minLength: 12)
                Button { openCalendar(now) } label: { Label("打开日历", systemImage: "arrow.up.right") }
                    .buttonStyle(SelnoButtonStyle())
                    .accessibilityIdentifier("dashboard.openCalendar")
            }
            HStack(spacing: 18) {
                metric("待办", count: projection.focus.count, symbol: "circle.dashed")
                metric("日程", count: projection.todayEvents.count, symbol: "calendar")
                if projection.overdueCount > 0 { metric("逾期", count: projection.overdueCount, symbol: "exclamationmark.circle", urgent: true) }
                Spacer(minLength: 0)
            }
        }
    }

    private func metric(_ title: String, count: Int, symbol: String, urgent: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
            Text(title)
        }.font(.subheadline).foregroundStyle(urgent ? SelnoDesign.warning : SelnoDesign.secondary)
    }

    @ViewBuilder private func overviewLayout(wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 16) { focusModule; upcomingModule }.frame(maxWidth: .infinity)
                VStack(spacing: 16) { monthModule; inboxModule }.frame(width: 294)
            }
        } else {
            focusModule
            HStack(alignment: .top, spacing: 16) { monthModule; inboxModule }
            upcomingModule
        }
    }

    private var focusModule: some View {
        WorkspaceCard(emphasis: true) {
            ModuleHeading(title: "今日聚焦", symbol: "scope", detail: "\(projection.focus.count + projection.todayEvents.count) 项",
                          actionTitle: "查看今天", action: { navigate(.today) })
            if projection.focus.isEmpty && projection.todayEvents.isEmpty {
                QuietEmptyState(title: "今天，可以从容开始", message: "安排一件要紧的事，或先把想法放进收件箱。")
                HStack {
                    Button("安排任务") { creation = .task }.buttonStyle(SelnoButtonStyle(primary: true)).accessibilityIdentifier("dashboard.createTask")
                    Button("添加日程") { creation = .event }.buttonStyle(SelnoButtonStyle()).accessibilityIdentifier("dashboard.createEvent")
                }
            } else {
                if !projection.todayEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("按时发生").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(projection.todayEvents.prefix(2))) { event in
                            CalendarEventAgendaRow(event: event, calendar: calendar) { selection = .event(event) }
                        }
                    }
                }
                if !projection.focus.isEmpty {
                    if !projection.todayEvents.isEmpty { Divider() }
                    VStack(spacing: 2) {
                        ForEach(Array(projection.focus.prefix(5))) { item in focusRow(item) }
                    }
                }
                let remaining = max(0, projection.focus.count - 5) + max(0, projection.todayEvents.count - 2)
                if remaining > 0 { Button("还有 \(remaining) 项 · 查看今天") { navigate(.today) }.buttonStyle(.link).font(.caption) }
            }
        }
    }

    private var upcomingModule: some View {
        WorkspaceCard {
            HStack {
                ModuleHeading(title: "近期安排", symbol: "text.alignleft")
                Picker("近期范围", selection: $days) { Text("3 天").tag(3); Text("7 天").tag(7) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 104).accessibilityIdentifier("dashboard.range")
            }
            Text("从明天起 · 每件事展示下一次安排").font(.caption).foregroundStyle(SelnoDesign.tertiary)
            if projection.upcoming.isEmpty {
                QuietEmptyState(title: "未来 \(days) 天暂无新安排", message: "今天需要处理的事项已集中在上方。")
            } else {
                ForEach(projection.upcoming) { day in
                    VStack(alignment: .leading, spacing: 5) {
                        Button { openCalendar(day.date) } label: {
                            HStack { Text(CalendarMath.fullDate(day.date, calendar: calendar)).font(.caption.weight(.semibold)); Spacer(); Image(systemName: "arrow.up.right").font(.caption2) }
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                        ForEach(Array(day.events.prefix(2))) { event in
                            CalendarEventAgendaRow(event: event, calendar: calendar) { selection = .event(event) }
                        }
                        ForEach(Array(day.tasks.prefix(3))) { item in
                            CalendarTaskAgendaRow(occurrence: item, open: { selection = .task(item.task) }, toggle: { toggle(item.task) })
                        }
                        let remainder = max(0, day.events.count - 2) + max(0, day.tasks.count - 3)
                        if remainder > 0 { Button("另有 \(remainder) 项，打开当日安排") { openCalendar(day.date) }.buttonStyle(.link).font(.caption) }
                    }
                    if day.id != projection.upcoming.last?.id { Divider() }
                }
            }
        }
    }

    private var monthModule: some View {
        WorkspaceCard {
            ModuleHeading(title: CalendarMath.monthTitle(now, calendar: calendar), symbol: "calendar",
                          actionTitle: "展开", action: { openCalendar(now) })
            CompactMonthView(window: monthWindow, today: now, snapshot: projection.month, calendar: calendar, select: openCalendar)
        }
    }

    private var inboxModule: some View {
        WorkspaceCard {
            ModuleHeading(title: "收件箱", symbol: "tray", detail: "\(inboxCount)", actionTitle: "整理", action: { navigate(.inbox) })
            if inbox.isEmpty { QuietEmptyState(title: "想法随时放在这里", message: "尚未安排的任务，稍后再整理。") }
            else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(inbox) { task in
                        Button { selection = .task(task) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Image(systemName: "circle.small").foregroundStyle(.tertiary)
                                Text(task.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).font(.subheadline)
                    }
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("快速记下任务…", text: $quickTitle).textFieldStyle(.plain)
                    .onSubmit(quickAdd).accessibilityIdentifier("dashboard.quickAdd")
                if !quickTitle.isEmpty { Button(action: quickAdd) { Image(systemName: "arrow.turn.down.left") }.buttonStyle(.plain).accessibilityLabel("保存到收件箱") }
            }.padding(9).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
            Text("\(inboxCount) 项待整理 · 未设置计划或项目")
                .font(.caption2).foregroundStyle(.tertiary).accessibilityIdentifier("dashboard.inboxCount")
        }
    }

    private var projectModule: some View {
        WorkspaceCard {
            ModuleHeading(title: "项目进度", symbol: "folder", detail: "\(projectCount) 个进行中",
                          actionTitle: "全部项目", action: { navigate(.projects) })
            if projects.isEmpty {
                HStack {
                    QuietEmptyState(title: "把相关事务，归入同一个项目", message: "为长期推进的事情保留清晰的进度。")
                    Spacer()
                    Button("创建项目") { creation = .project }.accessibilityIdentifier("dashboard.createProject")
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 24)], alignment: .leading, spacing: 16) {
                    ForEach(projects) { project in
                        Button { openProject(project.id) } label: { ProjectProgressView(project: project, calendar: calendar, now: now).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(projectLabel(project))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("dashboard.project.\(project.id)")
                    }
                }
            }
        }
    }

    @ViewBuilder private func todayLayout(wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 20) {
                todayTasks.frame(maxWidth: .infinity)
                todayEvents.frame(width: 300)
            }
        } else { todayEvents; todayTasks }
    }

    private var todayTasks: some View {
        WorkspaceCard(emphasis: true) {
            ModuleHeading(title: "需要完成", symbol: "checklist", detail: "\(projection.focus.count) 项")
            if projection.focus.isEmpty {
                QuietEmptyState(title: "今天的待办已清空", message: "计划执行、今天截止与逾期待办都会汇集在这里。")
            } else {
                ForEach(projection.focus) { item in
                    focusRow(item)
                    if item.id != projection.focus.last?.id { Divider() }
                }
            }
            Button("安排今天的任务") { creation = .task }.buttonStyle(.link)
        }
    }

    private var todayEvents: some View {
        WorkspaceCard {
            ModuleHeading(title: "按时发生", symbol: "clock", detail: "\(projection.todayEvents.count) 项日程")
            if projection.todayEvents.isEmpty {
                QuietEmptyState(title: "今天暂无日程", message: "为需要按时参加的事情留出时间。")
            } else {
                ForEach(projection.todayEvents) { event in
                    CalendarEventAgendaRow(event: event, calendar: calendar) { selection = .event(event) }
                    if event.id != projection.todayEvents.last?.id { Divider() }
                }
            }
            Button("添加今日日程") { creation = .event }.buttonStyle(.link)
        }
    }

    private func focusRow(_ item: FocusTask) -> some View {
        FocusTaskRow(item: item, open: { selection = .task(item.task) }, toggle: { toggle(item.task) })
    }
    private func projectLabel(_ project: TodoProject) -> String {
        let progress = ProjectProgress(project: project, now: now, calendar: calendar)
        return "\(project.name)，\(progress.completed) / \(progress.total) 已完成，\(progress.overdue) 项逾期"
    }
    private func rebuild() {
        projection = DashboardProjection.build(tasks: tasks + overdue, events: events, now: now, days: days, monthWindow: monthWindow, calendar: calendar, milestones: milestones)
    }
    private func refreshCounts() {
        do {
            inboxCount = try context.fetchCount(DashboardDataQuery.inbox())
            projectCount = try context.fetchCount(DashboardDataQuery.projects())
        } catch { presentedError = PresentedError("无法读取总览数量", error: error) }
    }
    private func toggle(_ task: TodoTask) {
        do { try TaskService(context: context).toggleCompletion(task) }
        catch { presentedError = PresentedError("无法更新任务", error: error) }
    }
    private func quickAdd() {
        do { try TaskService(context: context).createTask(title: quickTitle); quickTitle = ""; refreshCounts() }
        catch { presentedError = PresentedError("无法创建任务", error: error) }
    }
}

private struct CompactMonthView: View {
    let window: CalendarWindow
    let today: Date
    let snapshot: CalendarAgendaSnapshot
    let calendar: Calendar
    let select: (Date) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                let weekday = (calendar.firstWeekday - 1 + index) % 7
                Text(calendar.veryShortStandaloneWeekdaySymbols[weekday]).font(.caption2).foregroundStyle(.tertiary).frame(height: 18)
            }
            ForEach(window.days, id: \.self) { day in
                let agenda = snapshot.agenda(on: day, calendar: calendar)
                let isToday = calendar.isDate(day, inSameDayAs: today)
                let isMonth = calendar.isDate(day, equalTo: today, toGranularity: .month)
                Button { select(day) } label: {
                    VStack(spacing: 3) {
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 11, weight: isToday ? .semibold : .regular)).monospacedDigit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(isToday ? Color(nsColor: .windowBackgroundColor) : .primary)
                            .background(isToday ? Color.primary : .clear, in: Circle())
                        HStack(spacing: 2) {
                            if agenda.pendingCount > 0 { Circle().frame(width: 3, height: 3) }
                            if !agenda.events.isEmpty { RoundedRectangle(cornerRadius: 1).frame(width: 5, height: 3) }
                        }.frame(height: 3).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle()).opacity(isMonth ? 1 : 0.3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CalendarMath.fullDate(day, calendar: calendar))
                .accessibilityValue("\(agenda.pendingCount) 项待办，\(agenda.events.count) 项日程")
                .accessibilityIdentifier("dashboard.day.\(CalendarMath.dayID(day, calendar: calendar))")
                .help(hoverSummary(agenda))
            }
        }
    }
    private func hoverSummary(_ agenda: DayAgenda) -> String {
        let titles = agenda.events.prefix(2).map { "\(CalendarAgendaBuilder.eventTime($0, calendar: calendar)) \($0.title)" }
            + agenda.tasks.filter { $0.task.status.isActive }.prefix(2).map { $0.task.title }
        let remaining = agenda.pendingCount + agenda.events.count - titles.count
        return ([CalendarMath.fullDate(agenda.date, calendar: calendar), "\(agenda.pendingCount) 项待办 · \(agenda.events.count) 项日程"]
                + (titles.isEmpty ? ["暂无安排"] : titles) + (remaining > 0 ? ["另有 \(remaining) 项"] : [])).joined(separator: "\n")
    }
}
