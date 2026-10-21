import SwiftUI

struct TemplateFieldsForm: View {
    @Binding var payload: TemplatePayload
    @State private var expanded: Set<String> = ["基本信息"]
    private var groups: [String] {
        var seen = Set<String>()
        return payload.fields.filter(\.isVisible).map(\.group).filter { seen.insert($0).inserted }
    }
    var body: some View {
        ForEach(groups, id: \.self) { group in
            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(group) }, set: { if $0 { expanded.insert(group) } else { expanded.remove(group) } })) {
                ForEach(payload.fields.filter { $0.isVisible && $0.group == group }) { field in
                    fieldView(field)
                }
            } label: { Text(group).font(.subheadline.weight(.semibold)) }
        }
    }
    private func binding(_ field: TemplateField) -> Binding<FieldAnswer> {
        Binding(get: { payload.answer(field) }, set: { answer in
            if let index = payload.answers.firstIndex(where: { $0.fieldID == field.id }) { payload.answers[index] = answer }
            else { payload.answers.append(answer) }
        })
    }
    @ViewBuilder private func fieldView(_ field: TemplateField) -> some View {
        let answer = binding(field)
        let label = field.name + (field.isOptional ? "（可选）" : " *")
        switch field.kind {
        case .text, .url:
            TextField(label, text: answer.text).accessibilityIdentifier("field.text.\(field.name)")
        case .multiline:
            TextField(label, text: answer.text, axis: .vertical).lineLimit(2...4).accessibilityIdentifier("field.text.\(field.name)")
        case .dateTime:
            VStack(alignment: .leading, spacing: 8) {
                Toggle(label, isOn: Binding(get: { answer.wrappedValue.date != nil }, set: { answer.wrappedValue.date = $0 ? .now : nil; if !$0 { answer.wrappedValue.reminderMinutes = nil } }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("field.enable.\(field.semanticRaw)")
                if answer.wrappedValue.date != nil {
                    DatePicker(field.name, selection: Binding(get: { answer.wrappedValue.date ?? .now }, set: { answer.wrappedValue.date = $0 }), displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    HStack {
                        Toggle("显示在日历", isOn: answer.showOnCalendar).toggleStyle(.checkbox)
                        Picker("提醒", selection: answer.reminderMinutes) {
                            Text("不提醒").tag(nil as Int?)
                            ForEach([0, 10, 30, 60, 1440], id: \.self) { Text($0 == 0 ? "准时" : "提前 \($0) 分钟").tag(Optional($0)) }
                        }.frame(maxWidth: 240)
                    }.font(.caption)
                    Text("仅在明确选择后创建本地提醒；不会修改任务截止日期。")
                        .font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                }
            }.padding(.vertical, 4)
        }
    }
}
