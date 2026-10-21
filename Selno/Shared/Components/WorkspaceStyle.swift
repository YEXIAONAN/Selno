import SwiftUI

enum WorkspaceStyle {
    static let canvas = SelnoDesign.canvas
    static let surface = SelnoDesign.surface
    static let line = SelnoDesign.border.opacity(0.45)
}

struct WorkspaceCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var emphasis = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(SelnoDesign.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(emphasis ? SelnoDesign.surface : .clear, in: RoundedRectangle(cornerRadius: SelnoDesign.radius))
            .overlay(alignment: .top) { if !emphasis { Rectangle().fill(SelnoDesign.border.opacity(contrast == .increased ? 1 : 0.5)).frame(height: 1) } }
            .overlay { if emphasis { RoundedRectangle(cornerRadius: SelnoDesign.radius).strokeBorder(SelnoDesign.border.opacity(contrast == .increased ? 1 : 0.4), lineWidth: 1) } }
    }
}

struct ModuleHeading: View {
    let title: String
    let symbol: String
    var detail: String = ""
    var actionTitle: String = ""
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            if let action { Button(actionTitle, action: action).buttonStyle(.link).font(.caption).foregroundStyle(SelnoDesign.accent) }
        }
    }
}

struct QuietEmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 8)
    }
}

struct FocusTaskRow: View {
    let item: FocusTask
    let open: () -> Void
    let toggle: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: toggle) { Image(systemName: "circle").font(.title3).foregroundStyle(.secondary) }
                .buttonStyle(.plain).padding(.top, 2)
                .accessibilityLabel("标记为完成")
                .accessibilityIdentifier("task.complete.\(item.id.uuidString)")
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.task.title).font(.body.weight(.medium)).lineLimit(2)
                    HStack(spacing: 5) {
                        if item.isOverdue { Image(systemName: "exclamationmark.circle") }
                        Text(item.subtitle)
                        if let project = item.task.project { Text("· \(project.name)").lineLimit(1) }
                    }
                    .font(.caption).foregroundStyle(item.isOverdue ? SelnoDesign.warning : SelnoDesign.secondary)
                    TaskTags(task: item.task)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if item.task.importance == .high { Image(systemName: "flag.fill").font(.caption).foregroundStyle(.secondary).padding(.top, 3) }
        }.padding(.vertical, 7)
    }
}

struct ProjectProgressView: View {
    let project: TodoProject
    let calendar: Calendar
    let now: Date
    var body: some View {
        let progress = ProjectProgress(project: project, now: now, calendar: calendar)
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "folder").foregroundStyle(.secondary); Text(project.name).font(.subheadline.weight(.semibold)).lineLimit(1); Spacer(minLength: 0) }
            ProgressView(value: progress.fraction).tint(.secondary).accessibilityHidden(true)
            HStack {
                Text("\(progress.completed) / \(progress.total) 已完成")
                Spacer(minLength: 4)
                if progress.overdue > 0 { Text("\(progress.overdue) 项逾期").foregroundStyle(SelnoDesign.warning) }
            }.font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
