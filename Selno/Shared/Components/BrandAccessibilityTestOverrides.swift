import SwiftUI

extension EnvironmentValues {
    @Entry var selnoUITesting = false
    @Entry var selnoTestReduceMotion = false
    @Entry var selnoTestVoiceOver = false
}

struct BrandAccessibilityTestOverrides: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--selno-ui-testing")
        let style = arguments.lastIndex(of: "-AppleInterfaceStyle").flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
        let scheme: ColorScheme? = testing ? (style == "Light" ? .light : style == "Dark" ? .dark : nil) : nil
        content.environment(\.selnoUITesting, testing)
            .environment(\.selnoTestReduceMotion, testing && arguments.contains("--selno-test-reduce-motion"))
            .environment(\.selnoTestVoiceOver, testing && arguments.contains("--selno-test-voiceover"))
            .preferredColorScheme(scheme)
        #else
        content
        #endif
    }
}
