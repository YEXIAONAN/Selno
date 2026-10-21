import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum CalendarTaskDrag {
    static let contentType = UTType.utf8PlainText
    static let prefix = "selno-task:"

    static func provider(for id: UUID) -> NSItemProvider {
        NSItemProvider(object: "\(prefix)\(id.uuidString)" as NSString)
    }

    static func receive(_ providers: [NSItemProvider], reschedule: @escaping @MainActor (UUID) -> Void) -> Bool {
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(contentType.identifier) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: contentType.identifier) { data, _ in
            guard let data, let value = String(data: data, encoding: .utf8), value.hasPrefix(prefix),
                  let id = UUID(uuidString: String(value.dropFirst(prefix.count))) else { return }
            Task { @MainActor in reschedule(id) }
        }
        return true
    }
}

// AppKit tracks the mouse on task chips so a click and a drag have unambiguous
// behavior inside the SwiftUI calendar grid, including on macOS 15.
struct CalendarTaskDragButton: NSViewRepresentable {
    let occurrence: CalendarTaskOccurrence
    let showsRole: Bool
    let open: () -> Void

    func makeNSView(context: Context) -> TaskDraggingButton {
        let button = TaskDraggingButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.lineBreakMode = .byTruncatingTail
        button.font = .systemFont(ofSize: 10)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: TaskDraggingButton, context: Context) {
        let task = occurrence.task
        button.taskID = task.id
        button.open = open
        button.title = showsRole ? "\(occurrence.shortRoleTitle) · \(task.title)" : task.title
        let symbol = task.status == .completed ? "checkmark.circle.fill"
            : occurrence.roles.contains(.deadline) ? "flag" : occurrence.roles.contains(.planned) ? "checklist" : "play.circle"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        button.contentTintColor = task.status.isActive ? .labelColor : .secondaryLabelColor
        if task.status == .completed {
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor
            ])
        }
        button.setAccessibilityLabel("\(occurrence.roleTitle) · \(task.title)")
        button.setAccessibilityIdentifier("calendar.drag.\(task.id.uuidString)")
    }
}

final class TaskDraggingButton: NSButton, NSDraggingSource {
    var taskID = UUID()
    var open: () -> Void = {}

    init() {
        super.init(frame: .zero)
        target = self
        action = #selector(openTask)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func openTask() { open() }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let initial = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { performClick(nil) }
                return
            }
            let point = next.locationInWindow
            guard hypot(point.x - initial.x, point.y - initial.y) >= 4 else { continue }
            let pasteboard = NSPasteboardItem()
            pasteboard.setString("\(CalendarTaskDrag.prefix)\(taskID.uuidString)", forType: .string)
            let item = NSDraggingItem(pasteboardWriter: pasteboard)
            let image = NSImage(size: bounds.size)
            if let representation = bitmapImageRepForCachingDisplay(in: bounds) {
                cacheDisplay(in: bounds, to: representation)
                image.addRepresentation(representation)
            }
            item.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [item], event: next, source: self)
            return
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

}

extension View {
    func calendarTaskDraggable(_ id: UUID) -> some View {
        onDrag { CalendarTaskDrag.provider(for: id) }
    }
}
