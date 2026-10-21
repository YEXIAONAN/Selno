import SwiftUI

struct TaskRowView: View {
    let task: TodoTask
    let toggleCompletion: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggleCompletion) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" :
                        task.status == .cancelled ? "minus.circle" : "circle")
                    .font(.title3)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: task.statusRaw)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(task.status == .cancelled)
            .accessibilityLabel(task.status == .completed ? "恢复为未完成" : "标记为完成")
            .accessibilityValue(task.status.title)
            .accessibilityIdentifier("task.complete.\(task.id.uuidString)")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .strikethrough(task.status == .completed)
                    .foregroundStyle(task.status.isActive ? .primary : .secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if task.importance == .high {
                        Label("重要", systemImage: "flag.fill")
                    }
                    if task.status == .inProgress { StatusBadge(title: "进行中", symbol: "circle.lefthalf.filled") }
                    if let dueAt = task.dueAt {
                        Label {
                            Text(dueAt, format: .dateTime.month().day())
                        } icon: { Image(systemName: "calendar") }
                    }
                    if let project = task.project { Text(project.name) }
                    if !(task.steps ?? []).isEmpty {
                        Text("\(task.completedStepCount)/\((task.steps ?? []).count)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                TaskTags(task: task)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
