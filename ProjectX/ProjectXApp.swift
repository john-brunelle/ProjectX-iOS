import SwiftUI
import SwiftData

@main
struct ProjectXApp: App {
    @State private var service        = ProjectXService.shared
    @State private var realtime       = RealtimeService.shared
    @State private var themeManager   = ThemeManager.shared
    @State private var botRunner      = BotRunner.shared
    @State private var networkLogger  = NetworkLogger.shared

    init() {
        UserDefaults.standard.register(defaults: [
            "pref_autoRestoreBots": true,
            "pref_notifyOnStopLoss": false,
            "pref_notifyOnTakeProfit": false,
            "pref_notifyOnOrderFill": false,
            "pref_notifyOnBotError": false,
            "pref_enableRateLimiter": true
        ])
        _ = NotificationService.shared
    }

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
        .modelContainer(for: [IndicatorConfig.self, BotConfig.self, BotLogEntryRecord.self, AccountProfile.self, AccountBotAssignment.self, BotRunRecord.self, NetworkLogRecord.self])
    }
}
