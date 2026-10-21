import SwiftUI
import SwiftData

struct CalendarEventEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent?
    let calendar: Calendar
    @State private var draft: CalendarEventDraft
    @State private var presentedError: PresentedError?

    init(date: Date, calendar: Calendar) {
        event = nil
        self.calendar = calendar
        _draft = State(initialValue: CalendarEventDraft(date: date, calendar: calendar))
    }

    init(event: CalendarEvent, calendar: Calendar) {
        self.event = event
        self.calendar = calendar
        _draft = State(initialValue: CalendarEventDraft(event: event, calendar: calendar))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(event == nil ? "新建日程" : "编辑日程") {
                    TextField("日程名称", text: $draft.title)
                        .accessibilityIdentifier("event.editor.title")
                    Toggle("全天", isOn: $draft.isAllDay)
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("全天")
                        .accessibilityIdentifier("event.editor.allDay")
                    DatePicker(draft.isAllDay ? "开始日期" : "开始时间", selection: $draft.startsAt,
                               displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .accessibilityIdentifier("event.editor.start")
                    DatePicker(draft.isAllDay ? "结束日期（含）" : "结束时间", selection: $draft.endsAt,
                               displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .accessibilityIdentifier("event.editor.end")
                    if draft.isAllDay {
                        Text("结束日期包含当天；日程按本地日期保存。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("其他信息") {
                    TextField("地点（可选）", text: $draft.location)
                        .accessibilityIdentifier("event.editor.location")
                    TextField("备注（可选）", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("event.editor.save")
            }
            .padding()
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .onChange(of: draft.isAllDay) { _, isAllDay in
            if !isAllDay {
                draft.startsAt = CalendarMath.defaultTime(on: draft.startsAt, calendar: calendar)
                let lastDayStart = CalendarMath.defaultTime(on: draft.endsAt, calendar: calendar)
                draft.endsAt = calendar.date(byAdding: .hour, value: 1, to: lastDayStart) ?? lastDayStart
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("好")))
        }
    }

    private func save() {
        do {
            let service = CalendarEventService(context: context, calendar: calendar)
            if let event { try service.update(event, draft: draft) }
            else { try service.create(draft: draft) }
            dismiss()
        } catch {
            presentedError = PresentedError("无法保存日程", error: error)
        }
    }
}
