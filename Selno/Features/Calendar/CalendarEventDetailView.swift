import SwiftUI
import SwiftData

struct CalendarEventDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent
    let calendar: Calendar
    var onDelete: (() -> Void)? = nil
    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var presentedError: PresentedError?

    var body: some View {
        Form {
            Section {
                Label(event.title, systemImage: "calendar")
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                LabeledContent("类型", value: event.isAllDay ? "全天日程" : "定时日程")
            }
            Section("时间") {
                LabeledContent("开始") {
                    Text(CalendarMath.fullDate(event.startsAt, calendar: calendar))
                }
                if event.isAllDay {
                    let lastDay = calendar.date(byAdding: .day, value: -1, to: event.endsAt) ?? event.startsAt
                    LabeledContent("结束（含）") { Text(CalendarMath.fullDate(lastDay, calendar: calendar)) }
                } else {
                    LabeledContent("结束") { Text(CalendarMath.fullDate(event.endsAt, calendar: calendar)) }
                    LabeledContent("时段", value: CalendarAgendaBuilder.eventTime(event, calendar: calendar))
                }
            }
            if let location = event.location { LabeledContent("地点", value: location) }
            if !event.notes.isEmpty { Section("备注") { Text(event.notes).textSelection(.enabled) } }
        }
        .formStyle(.grouped)
        .navigationTitle("日程详情")
        .toolbar {
            ToolbarItem {
                Button("编辑") { isEditing = true }.accessibilityIdentifier("event.edit")
            }
            ToolbarItem {
                Button("删除日程", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(isPresented: $isEditing) { CalendarEventEditorView(event: event, calendar: calendar) }
        .confirmationDialog("删除这个日程？", isPresented: $confirmDelete) {
            Button("删除日程", role: .destructive) {
                do {
                    try CalendarEventService(context: context, calendar: calendar).delete(event)
                    if let onDelete { onDelete() } else { dismiss() }
                } catch { presentedError = PresentedError("无法删除日程", error: error) }
            }
        } message: { Text("此操作无法撤销，任务记录不会受到影响。") }
        .alert(item: $presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("好")))
        }
    }
}
