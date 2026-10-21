import SwiftUI
import SwiftData

@main
struct SelnoApp: App {
    @State private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup("Selno") {
            if let container = bootstrap.container {
                MainWindowView()
                    .modelContainer(container)
                    .modifier(BrandAccessibilityTestOverrides())
            } else {
                ContentUnavailableView {
                    Label("无法打开 Selno", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(bootstrap.failureMessage ?? "本地数据库暂时不可用。")
                        .textSelection(.enabled)
                } actions: {
                    Button("重试") { bootstrap.load() }
                }
                .frame(minWidth: 600, minHeight: 400)
            }
        }
        .defaultSize(width: 1280, height: 820)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        Settings {
            if let container = bootstrap.container {
                SettingsWorkspace().modelContainer(container).modifier(BrandAccessibilityTestOverrides())
            }
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
    }
}
