import SwiftUI
import SwiftData

@main
struct ProjectXApp: App {
    @State private var service        = ProjectXService.shared
    @State private var realtime       = RealtimeService.shared
    @State private var themeManager   = ThemeManager.shared
    @State private var botRunner      = BotRunner.shared
    @State private var networkLogger  = NetworkLogger.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(service)
                .environment(realtime)
                .environment(themeManager)
                .environment(botRunner)
                .environment(networkLogger)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .modelContainer(for: [IndicatorConfig.self, BotConfig.self, BotLogEntryRecord.self, AccountProfile.self])
    }
}
