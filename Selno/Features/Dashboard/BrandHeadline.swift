import SwiftUI
import Observation
import AppKit

nonisolated enum BrandCopy {
    static let phrases = ["每一件事，有条不紊。", "把时间，留给真正重要的事。", "秩序之中，自有从容。", "让计划清晰，让行动发生。",
                          "不必匆忙，只需坚定。", "今天的每一步，都算数。", "从容安排，专注当下。", "让想法落地，让日子有序。"]
    static let typing = Duration.milliseconds(100)
    static let deleting = Duration.milliseconds(55)
    static let pause = Duration.milliseconds(400)
}

@MainActor @Observable
final class BrandTypingState {
    enum Phase { case typing, reading, deleting, pause }
    let phrases: [String]
    private let characters: [[Character]]
    private(set) var index = 0
    private(set) var count = 1
    private(set) var phase: Phase = .typing
    init(phrases: [String] = BrandCopy.phrases) {
        self.phrases = phrases.filter { !$0.isEmpty }.isEmpty ? ["序宁"] : phrases.filter { !$0.isEmpty }
        characters = self.phrases.map(Array.init)
    }
    var fullText: String { phrases[index] }
    var text: String { String(characters[index].prefix(count)) }
    var delay: Duration {
        switch phase {
        case .typing: BrandCopy.typing
        case .reading: .milliseconds(min(5500, max(3500, characters[index].count * 300)))
        case .deleting: BrandCopy.deleting
        case .pause: BrandCopy.pause
        }
    }
    func advance() {
        switch phase {
        case .typing:
            count = min(count + 1, characters[index].count)
            if count == characters[index].count { phase = .reading }
        case .reading: phase = .deleting
        case .deleting:
            count = max(0, count - 1)
            if count == 0 { phase = .pause }
        case .pause: index = (index + 1) % phrases.count; count = 0; phase = .typing
        }
    }
}

struct BrandHeadline: View {
    let state: BrandTypingState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.selnoTestReduceMotion) private var testReduceMotion
    @Environment(\.selnoTestVoiceOver) private var testVoiceOver
    @Environment(\.selnoUITesting) private var uiTesting
    @State private var windowActive = false
    private var isStatic: Bool { reduceMotion || voiceOver || testReduceMotion || testVoiceOver }
    private var runs: Bool { windowActive && scenePhase == .active && !isStatic }
    var body: some View {
        Text(isStatic ? state.fullText : state.text)
        .accessibilityLabel(state.fullText)
        // Observe the actual animation in isolated UI tests; production accessibility stays sentence based.
        .accessibilityValue(uiTesting && !isStatic ? state.text : "")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("dashboard.heading")
        .font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.5)
        .lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity, alignment: .leading).frame(height: 36, alignment: .leading)
        .background(WindowActivityProbe { windowActive = $0 }.frame(width: 0, height: 0))
        .task(id: runs) {
            guard runs else { return }
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: state.delay)
                    try Task.checkCancellation()
                    state.advance()
                }
            } catch { }
        }
    }
}

private struct WindowActivityProbe: NSViewRepresentable {
    let report: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.report = report; return view }
    func updateNSView(_ view: Probe, context: Context) { view.report = report }
    final class Probe: NSView {
        var report: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification,
                         NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateActivity() }
                })
            }
            Task { @MainActor [weak self] in self?.updateActivity() }
        }
        private func updateActivity() { report?(NSApp.isActive && window?.isKeyWindow == true && window?.occlusionState.contains(.visible) == true) }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
