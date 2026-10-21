import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WorkspaceSidebarView: View {
    @Binding var selection: SidebarSelection?

    @Environment(\.modelContext) private var context
    @Query(sort: \Workspace.sortOrder) private var workspaces: [Workspace]

    @State private var creating = false
    @State private var editorRequest: WorkspaceEditorRequest?
    @State private var deleting: Workspace?
    @State private var draggedWorkspaceID: UUID?
    @State private var error: PresentedError?

    private var scenarios: [Workspace] {
        workspaces.filter { !$0.isGlobal }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selno")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                Text("序宁 · 让事务有序")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.top, 18)

            List(selection: $selection) {
                Section {
                    ForEach(AppSection.allCases) { item in
                        NavigationLink(value: SidebarSelection.section(item)) {
                            Label(item.title, systemImage: item.symbolName)
                                .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("sidebar.\(item.rawValue)")
                    }
                }

                Section {
                    ForEach(scenarios) { workspace in
                        scenarioRow(workspace)
                    }
                    // Native List row reordering. A custom .onDrag on the link
                    // makes AppKit treat the row as a drag source and swallow
                    // plain clicks, so reordering is delegated to List itself
                    // while the NavigationLink keeps its normal activation.
                    .onMove { source, destination in
                        var ids = scenarios.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        do { try WorkspaceService(context: context).reorderWorkspaces(ids) }
                        catch { self.error = PresentedError("无法调整工作台顺序", error: error) }
                    }
                    // Keep the add action as a real List row. A Button inside a
                    // Section header is merged into the header's StaticText by
                    // AppKit's sidebar outline view, which makes it neither
                    // clickable for VoiceOver nor addressable by UI tests.
                    Button {
                        creating = true
                    } label: {
                        Label("新建工作台", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(SelnoDesign.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .accessibilityIdentifier("workspace.add")
                } header: {
                    Text("工作台")
                        .textCase(nil)
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("sidebar.workspaces")

            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(SelnoDesign.secondary)
            .padding(.horizontal, 18).padding(.bottom, 16)
            .accessibilityIdentifier("settings.open")
        }
        .navigationTitle("Selno")
        .background(SelnoDesign.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 192, max: 260)
        .sheet(isPresented: $creating) {
            WorkspaceCreateView { id in
                selection = .workspace(id)
            }
        }
        .sheet(item: $editorRequest) { request in
            WorkspaceEditorView(workspaceID: request.id,
                                onDeleted: { clearSelectionIfNeeded(request.id) })
        }
        .confirmationDialog("删除场景“\(deleting?.name ?? "")”？",
                            isPresented: Binding(get: { deleting != nil },
                                                 set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("删除场景", role: .destructive) { deleteSelected() }
            Button("取消", role: .cancel) { deleting = nil }
        } message: {
            Text("只会删除工作台的模块与筛选配置，不会删除任何任务、项目、标签、日程或模板。")
        }
        .alert(item: $error) { error in
            Alert(title: Text(error.title), message: Text(error.message),
                  dismissButton: .default(Text("好")))
        }
    }

    private func scenarioRow(_ workspace: Workspace) -> some View {
        // A tagged row rather than a NavigationLink: AppKit only starts a
        // native List row drag from a plain selectable row, and a link's mouse
        // tracking swallowed the drag. Selection still drives the detail pane
        // through the List's selection binding.
        workspaceRow(workspace)
            .tag(SidebarSelection.workspace(workspace.id))
            .onDrop(of: [WorkspaceDragType.workspace.identifier],
                    delegate: WorkspaceSidebarDropDelegate(
                        targetID: workspace.id,
                        draggedID: $draggedWorkspaceID,
                        move: move
                    ))
            .accessibilityIdentifier("sidebar.workspace.\(workspace.id.uuidString)")
            .contextMenu {
                Button("重命名与筛选…") {
                    editorRequest = WorkspaceEditorRequest(id: workspace.id)
                }
                Button("复制工作台") { duplicate(workspace) }
                Divider()
                Button("上移") { move(workspace, by: -1) }
                    .disabled(index(of: workspace) == 0)
                Button("下移") { move(workspace, by: 1) }
                    .disabled(index(of: workspace) >= scenarios.count - 1)
                Divider()
                Button("删除场景…", role: .destructive) { deleting = workspace }
            }
    }

    private func workspaceRow(_ workspace: Workspace) -> some View {
        HStack(spacing: 7) {
            Text(workspace.emoji.isEmpty ? "🗂" : workspace.emoji)
                .frame(width: 20)
            Text(workspace.name).lineLimit(1)
            Spacer(minLength: 4)
            Circle()
                .fill(workspace.accent.color)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            // The drag source is only this small grip. Putting .onDrag on the
            // whole row makes AppKit treat the row as a drag source and swallow
            // plain clicks, so selection and drag stay on separate targets.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(SelnoDesign.tertiary)
                .frame(width: 12, height: 18)
                .contentShape(Rectangle())
                .onDrag {
                    draggedWorkspaceID = workspace.id
                    return WorkspaceDragType.workspaceProvider(for: workspace.id)
                }
                .help("拖动调整工作台顺序")
                .accessibilityLabel("拖动 \(workspace.name)")
                .accessibilityIdentifier("sidebar.workspace.drag.\(workspace.id.uuidString)")
        }
        .padding(.vertical, 3)
    }

    private func index(of workspace: Workspace) -> Int {
        scenarios.firstIndex { $0.id == workspace.id } ?? 0
    }

    private func move(_ workspace: Workspace, by offset: Int) {
        var ids = scenarios.map(\.id)
        guard let current = ids.firstIndex(of: workspace.id) else { return }
        let target = current + offset
        guard ids.indices.contains(target) else { return }
        ids.swapAt(current, target)
        do { try WorkspaceService(context: context).reorderWorkspaces(ids) }
        catch { self.error = PresentedError("无法调整工作台顺序", error: error) }
    }

    private func move(_ sourceID: UUID, relativeTo targetID: UUID, after: Bool) {
        var ids = scenarios.map(\.id)
        guard let source = ids.firstIndex(of: sourceID),
              sourceID != targetID,
              ids.contains(targetID) else { return }
        let item = ids.remove(at: source)
        guard let target = ids.firstIndex(of: targetID) else { return }
        ids.insert(item, at: after ? target + 1 : target)
        do { try WorkspaceService(context: context).reorderWorkspaces(ids) }
        catch { self.error = PresentedError("无法调整工作台顺序", error: error) }
    }

    private func duplicate(_ workspace: Workspace) {
        do {
            let copy = try WorkspaceService(context: context).duplicateWorkspace(workspace)
            selection = .workspace(copy.id)
        } catch {
            self.error = PresentedError("无法复制工作台", error: error)
        }
    }

    private func deleteSelected() {
        guard let deleting else { return }
        do {
            try WorkspaceService(context: context).deleteWorkspace(deleting.id)
            clearSelectionIfNeeded(deleting.id)
            self.deleting = nil
        } catch {
            self.error = PresentedError("无法删除场景", error: error)
            self.deleting = nil
        }
    }

    private func clearSelectionIfNeeded(_ id: UUID) {
        if selection == .workspace(id) {
            selection = .section(.overview)
        }
    }
}

private struct WorkspaceSidebarDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let move: (UUID, UUID, Bool) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [WorkspaceDragType.workspace.identifier]),
              let draggedID, draggedID != targetID else { return false }
        return true
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedID = nil }
        guard let source = draggedID, source != targetID else { return false }
        // Dropping on a row's lower half places the dragged row after it.
        move(source, targetID, info.location.y > 11)
        return true
    }
}

