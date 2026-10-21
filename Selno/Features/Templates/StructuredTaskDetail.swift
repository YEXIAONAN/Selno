import SwiftUI

struct StructuredTaskDetail: View {
    let instance: TaskTemplateInstance
    var body: some View {
        if let payload = instance.payload {
            Section {
                ForEach(payload.fields) { field in
                    let answer = payload.answer(field)
                    if let date = answer.date {
                        LabeledContent(field.name) { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                    } else if !answer.text.isEmpty {
                        LabeledContent(field.name) {
                            if field.kind == .url, let url = URL(string: answer.text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link(answer.text, destination: url).lineLimit(2) }
                            else { Text(answer.text).textSelection(.enabled) }
                        }
                    }
                }
                if !payload.isEditable { Text("包含未知版本字段，原始记录已保留。").foregroundStyle(SelnoDesign.warning) }
            } header: {
                Text("\(instance.templateName) · 创建时版本 \(instance.templateRevision)")
                    .accessibilityIdentifier("task.template.snapshot")
            }
        } else {
            Section("结构化数据") { Text("暂时无法解码；原始记录仍然保留，普通任务信息可以继续编辑。").foregroundStyle(SelnoDesign.warning) }
        }
    }
}

struct MilestoneDetailRows: View {
    let task: TodoTask
    var body: some View {
        if !(task.milestones ?? []).isEmpty {
            Section("时间节点 · 不等同于任务截止") {
                ForEach((task.milestones ?? []).sorted { $0.date < $1.date }) { node in
                    HStack(alignment: .top) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(SelnoDesign.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title).fontWeight(.medium)
                            Text(node.date, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(SelnoDesign.secondary)
                            HStack {
                                if node.isOnCalendar { Text("已显示在日历") }
                                if let lead = node.reminderLeadMinutes { Text(lead == 0 ? "准时提醒" : "提前 \(lead) 分钟提醒"); Text(reminderStatus(node.reminderStateRaw)) }
                            }.font(.caption2).foregroundStyle(SelnoDesign.tertiary)
                        }
                    }.padding(.vertical, 3)
                }
            }
        }
    }
    private func reminderStatus(_ state: String) -> String {
        switch state { case "scheduled": "已安排"; case "blocked": "通知权限未开放"; case "failed": "安排失败，稍后重试"; case "expired": "提醒时间已过"; case "paused": "任务已结束，提醒已停用"; default: "待安排" }
    }
}
