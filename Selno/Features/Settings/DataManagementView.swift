import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted after a successful import so workspaces can drop stale selections and
    /// reload their queries against the rewritten store.
    static let selnoDataDidChange = Notification.Name("SelnoDataDidChange")
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @State private var preview: BackupImportPreview?
    @State private var importMode: BackupImportMode = .merge
    @State private var pendingReplace: BackupImportPreview?
    @State private var alert: DataAlert?
    @State private var lastExport: ExportRecord?
    @State private var lastImportSummary: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("数据管理").font(.title2.weight(.semibold))
                    Text("所有内容只保存在这台 Mac 的本机数据库中。JSON 备份不经过任何云服务。")
                        .font(.callout).foregroundStyle(SelnoDesign.secondary)
                }

                WorkspaceCard(emphasis: true) {
                    ModuleHeading(title: "导出备份", symbol: "square.and.arrow.up",
                                  detail: "UTF-8 JSON · 完整关系")
                    Text("导出全部任务、状态、优先级、日期、日程、项目、标签、模板、提醒、工作台布局与任务视图。导出不会改动任何现有数据。")
                        .font(.callout).foregroundStyle(SelnoDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("导出 JSON…") { exportBackup() }
                            .buttonStyle(SelnoButtonStyle(primary: true))
                            .disabled(isWorking)
                            .accessibilityIdentifier("data.export")
                        if let lastExport {
                            Text("上次导出：\(lastExport.fileName) · \(lastExport.date.formatted(date: .abbreviated, time: .shortened)) · \(lastExport.recordCount) 条记录")
                                .font(.caption).foregroundStyle(SelnoDesign.secondary)
                                .lineLimit(2)
                        } else {
                            Text("尚未从本机导出备份。").font(.caption).foregroundStyle(SelnoDesign.secondary)
                        }
                    }
                    if let summary = currentSummary {
                        Text(summary).font(.caption).foregroundStyle(SelnoDesign.tertiary)
                    }
                }

                WorkspaceCard(emphasis: true) {
                    ModuleHeading(title: "导入备份", symbol: "square.and.arrow.down",
                                  detail: "先校验，再写入")
                    Text("导入前会完整校验格式、日期与关联关系。兼容 v1 与 v2 备份：v1 文件导入后会自动补建全局工作台。任何一步失败都不会留下半导入状态。")
                        .font(.callout).foregroundStyle(SelnoDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 7) {
                        ImportModeRow(mode: .merge)
                        ImportModeRow(mode: .replace)
                    }
                    .padding(.vertical, 2)
                    HStack(spacing: 12) {
                        Button("选择备份文件…") { chooseBackup() }
                            .buttonStyle(SelnoButtonStyle())
                            .disabled(isWorking)
                            .accessibilityIdentifier("data.import")
                        if let lastImportSummary {
                            Text(lastImportSummary).font(.caption).foregroundStyle(SelnoDesign.secondary)
                        }
                    }
                }

                WorkspaceCard {
                    ModuleHeading(title: "安全与恢复", symbol: "lock.shield")
                    VStack(alignment: .leading, spacing: 8) {
                        Label("合并导入按稳定标识匹配；同一条记录冲突时保留本地版本，并报告跳过数量。", systemImage: "arrow.triangle.merge")
                        Label("替换恢复会先写入一份 Selno-PreRestore 安全备份，再执行替换。", systemImage: "clock.arrow.circlepath")
                        Label("未来版本的备份会被拒绝，不会尝试猜测或降级写入。", systemImage: "nosign")
                    }
                    .font(.caption).foregroundStyle(SelnoDesign.secondary)
                    HStack(spacing: 10) {
                        Button("打开自动备份文件夹") { revealAutomaticBackups() }
                            .buttonStyle(.link).font(.caption)
                        Spacer()
                        Text("自动备份位置：Application Support/Selno/Backups")
                            .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SelnoDesign.canvas)
        .onAppear { lastExport = ExportRecord.load() }
        .sheet(item: $preview) { item in
            ImportPreviewSheet(
                preview: item,
                mode: $importMode,
                cancel: { preview = nil },
                confirm: { mode in
                    preview = nil
                    if mode == .replace {
                        pendingReplace = item
                    } else {
                        performImport(item.document, mode: .merge)
                    }
                }
            )
        }
        .confirmationDialog("替换全部本地数据？", isPresented: Binding(
            get: { pendingReplace != nil },
            set: { if !$0 { pendingReplace = nil } }
        ), titleVisibility: .visible) {
            Button("先备份，再替换", role: .destructive) {
                if let item = pendingReplace { performImport(item.document, mode: .replace) }
                pendingReplace = nil
            }
            Button("取消", role: .cancel) { pendingReplace = nil }
        } message: {
            Text("这会删除当前全部任务、日程、项目、标签、模板、提醒、工作台布局与任务视图，然后写入备份内容。执行前会自动生成一份 Selno-PreRestore JSON 安全备份。")
        }
        .alert(item: $alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
    }

    private var currentSummary: String? {
        guard let counts = try? BackupImportService(context: context).currentCounts() else { return nil }
        return "当前：\(counts.tasks) 个任务 · \(counts.events) 个日程 · \(counts.projects) 个项目 · \(counts.tags) 个标签 · \(counts.templates) 个模板 · \(counts.reminders) 条任务提醒 · \(counts.workspaces) 个工作台 · \(counts.savedViews) 个任务视图"
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "导出 Selno 备份"
        panel.prompt = "导出"
        panel.nameFieldStringValue = BackupExportService.suggestedFileName()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            let service = BackupExportService(context: context)
            let document = try service.makeDocument()
            try service.write(document.backup, to: url)
            let record = ExportRecord(date: .now, fileName: url.lastPathComponent,
                                      recordCount: document.counts.total)
            record.save()
            lastExport = record
            alert = DataAlert(
                title: "备份已导出",
                message: "已写入 \(url.lastPathComponent)，共 \(document.counts.total) 条记录。\(url.deletingLastPathComponent().path)"
            )
        } catch {
            alert = DataAlert(title: "无法导出备份", message: error.localizedDescription)
        }
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.title = "选择 Selno 备份"
        panel.prompt = "打开"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            let data = try BackupFileIO.read(from: url)
            let backup = try BackupCodec.decode(data)
            try BackupCodec.validate(backup)
            let document = BackupDocument(backup: backup, fileName: url.lastPathComponent,
                                          sourceURL: url, byteCount: data.count)
            let importPreview = try BackupImportService(context: context).makePreview(document: document)
            importMode = .merge
            preview = importPreview
        } catch {
            alert = DataAlert(title: "无法读取备份", message: error.localizedDescription)
        }
    }

    private func performImport(_ document: BackupDocument, mode: BackupImportMode) {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try BackupImportService(context: context).apply(document: document, mode: mode)
            let safety = result.safetyBackupURL.map { "\n安全备份：\($0.lastPathComponent)" } ?? ""
            lastImportSummary = "上次导入：\(mode.title) · 新增 \(result.inserted.total) 条"
            alert = DataAlert(
                title: mode == .merge ? "合并完成" : "恢复完成",
                message: "新增 \(result.inserted.total) 条记录，跳过 \(result.skipped.total) 条已存在的记录。\(safety)"
            )
            NotificationCenter.default.post(name: .selnoDataDidChange, object: nil)
            lastExport = ExportRecord.load()
        } catch {
            alert = DataAlert(title: mode == .merge ? "导入失败" : "恢复失败", message: error.localizedDescription)
        }
    }

    private func revealAutomaticBackups() {
        do {
            let directory = try PersistenceController.automaticBackupDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        } catch {
            alert = DataAlert(title: "无法打开自动备份文件夹", message: error.localizedDescription)
        }
    }
}

private struct ImportModeRow: View {
    let mode: BackupImportMode
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: mode == .merge ? "arrow.triangle.merge" : "arrow.counterclockwise")
                .foregroundStyle(mode == .replace ? SelnoDesign.warning : SelnoDesign.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).font(.subheadline.weight(.medium))
                Text(mode.explanation).font(.caption).foregroundStyle(SelnoDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ImportPreviewSheet: View {
    let preview: BackupImportPreview
    @Binding var mode: BackupImportMode
    let cancel: () -> Void
    let confirm: (BackupImportMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("检查备份").font(.title2.weight(.semibold))
                Text(preview.document.fileName).font(.callout).foregroundStyle(SelnoDesign.secondary)
                Text("导出于 \(preview.document.backup.exportedAt.formatted(date: .abbreviated, time: .standard)) · 格式版本 \(preview.document.backup.schemaVersion) · Selno \(preview.document.backup.appVersion)")
                    .font(.caption).foregroundStyle(SelnoDesign.tertiary)
            }

            WorkspaceCard(emphasis: true) {
                ModuleHeading(title: "文件内容", symbol: "doc.text", detail: "\(preview.document.counts.total) 条")
                CountsView(counts: preview.document.counts)
            }

            WorkspaceCard {
                ModuleHeading(title: "导入方式", symbol: "slider.horizontal.3")
                Picker("导入方式", selection: $mode) {
                    ForEach(BackupImportMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(mode.explanation).font(.caption).foregroundStyle(SelnoDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                if mode == .merge {
                    Text("本地现有内容").font(.caption.weight(.medium))
                    CountsView(counts: preview.existingCounts)
                    HStack(spacing: 14) {
                        Label("将新增 \(preview.mergeInserted.total) 条", systemImage: "plus.circle")
                            .foregroundStyle(SelnoDesign.success)
                        Label("将跳过 \(preview.mergeSkipped.total) 条", systemImage: "arrow.uturn.forward")
                            .foregroundStyle(SelnoDesign.secondary)
                    }.font(.caption)
                } else {
                    Text("本地现有内容将被移除").font(.caption.weight(.medium))
                    CountsView(counts: preview.existingCounts)
                    Label("执行前自动写入一份安全备份；若写入失败，替换不会开始。", systemImage: "exclamationmark.shield")
                        .font(.caption).foregroundStyle(SelnoDesign.warning)
                }
            }

            HStack {
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(mode == .replace ? "继续替换…" : "确认合并导入") { confirm(mode) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(SelnoButtonStyle(primary: true))
                    .accessibilityIdentifier("data.import.confirm")
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(SelnoDesign.canvas)
    }
}

private struct CountsView: View {
    let counts: BackupCounts
    private let columns = [GridItem(.adaptive(minimum: 132), alignment: .leading)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.label) { row in
                HStack(spacing: 5) {
                    Text(row.label).foregroundStyle(SelnoDesign.secondary)
                    Text("\(row.value)").monospacedDigit()
                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
        }
    }
    private var rows: [(label: String, value: Int)] {
        [("任务", counts.tasks), ("日程", counts.events), ("项目", counts.projects),
         ("标签", counts.tags), ("模板", counts.templates), ("子任务", counts.steps),
         ("模板快照", counts.templateInstances), ("时间节点", counts.milestones),
         ("任务提醒", counts.reminders), ("工作台", counts.workspaces),
         ("布局模块", counts.modules), ("任务视图", counts.savedViews)]
            .filter { $0.1 > 0 || $0.0 == "任务" }
    }
}

private struct DataAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ExportRecord {
    let date: Date
    let fileName: String
    let recordCount: Int

    private static let key = "Selno.LastExportRecord"

    static func load() -> ExportRecord? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return ExportRecord(date: value.date, fileName: value.fileName, recordCount: value.recordCount)
    }

    func save() {
        let value = Stored(date: date, fileName: fileName, recordCount: recordCount)
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private struct Stored: Codable {
        let date: Date
        let fileName: String
        let recordCount: Int
    }
}