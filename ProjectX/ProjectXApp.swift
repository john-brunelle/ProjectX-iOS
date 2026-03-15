import SwiftUI
import SwiftData

@main
struct ProjectXApp: App {
    @State private var service      = ProjectXService.shared
    @State private var realtime     = RealtimeService.shared
    @State private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(service)
                .environment(realtime)
                .environment(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .modelContainer(for: [IndicatorConfig.self, BotConfig.self])
    }
}
