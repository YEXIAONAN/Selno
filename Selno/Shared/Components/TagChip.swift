import SwiftUI

enum TagPalette: String, CaseIterable, Identifiable {
    case sage = "#4F7A69", amber = "#A27A3F", slate = "#647C91", lavender = "#7E7391", clay = "#8B7865", rose = "#A15E67", olive = "#747C40", teal = "#397C80"
    var id: String { rawValue }
    var title: String {
        switch self { case .sage: "鼠尾草"; case .amber: "琥珀"; case .slate: "蓝灰"; case .lavender: "雾紫"; case .clay: "陶土"; case .rose: "蔷薇"; case .olive: "橄榄"; case .teal: "青绿" }
    }
    static func color(_ hex: String, dark: Bool) -> Color {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x4F7A69
        let channels = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
        let c = channels.map { dark ? $0 * 0.45 + 0.55 : $0 * 0.75 }
        return Color(red: c[0], green: c[1], blue: c[2])
    }
}

struct TagChip: View {
    let tag: TaskCategory
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let color = TagPalette.color(tag.colorHex, dark: scheme == .dark)
        HStack(spacing: 4) {
            if !tag.emoji.isEmpty { Text(tag.emoji).fixedSize() } else { Image(systemName: tag.symbolName).font(.caption2) }
            Text(tag.name).lineLimit(1).truncationMode(.tail)
        }.font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 4)
            .foregroundStyle(color).background(color.opacity(scheme == .dark ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(contrast == .increased ? 0.9 : 0.25)))
            .accessibilityElement(children: .ignore).accessibilityLabel("标签：\(tag.emoji)\(tag.name)")
    }
}

struct TaskTags: View {
    let task: TodoTask
    var limit = 2
    var body: some View {
        if !task.visibleTags.isEmpty {
            HStack(spacing: 5) {
                ForEach(Array(task.visibleTags.prefix(limit))) { TagChip(tag: $0).frame(maxWidth: 130) }
                if task.visibleTags.count > limit { Text("+\(task.visibleTags.count - limit)").font(.caption).foregroundStyle(SelnoDesign.secondary) }
                Spacer(minLength: 0)
            }.help(task.visibleTags.map { "\($0.emoji) \($0.name)" }.joined(separator: "、"))
        }
    }
}

struct TagSelection: View {
    let tags: [TaskCategory]
    @Binding var selectedIDs: Set<UUID>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading) {
            ForEach(tags.filter { !$0.isArchived }) { tag in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        if !selectedIDs.insert(tag.id).inserted { selectedIDs.remove(tag.id) }
                    }
                } label: {
                    HStack(spacing: 4) { Image(systemName: selectedIDs.contains(tag.id) ? "checkmark.circle.fill" : "circle"); TagChip(tag: tag) }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(tag.name).accessibilityValue(selectedIDs.contains(tag.id) ? "已选择" : "未选择")
                    .accessibilityIdentifier("tag.select.\(tag.id)")
            }
        }
    }
}
