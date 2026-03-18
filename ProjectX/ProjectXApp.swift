import SwiftUI
import SwiftData

@main
struct PojectXApp: App {
    @State private var service        = ProjectXService.shared
    @State private var realtime       = RealtimeService.shared
    @State private var themeManager   = ThemeManager.shared
    @State private var botRunner      = BotRunner.shared
    @State private var networkLogger  = NetworkLogger.shared

    let modelContainer: ModelContainer

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

        // Try with migration first; if the store is incompatible, wipe and recreate
        let schema = Schema(ProjectXSchemaV1.models)
        if let container = try? ModelContainer(
            for: schema,
            migrationPlan: ProjectXMigrationPlan.self
        ) {
            modelContainer = container
        } else {
            print("ModelContainer migration failed. Recreating store.")
            let config = ModelConfiguration()
            if let url = config.url as URL? {
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(
                        at: URL(fileURLWithPath: url.path + suffix)
                    )
                }
            }
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: ProjectXMigrationPlan.self
                )
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

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
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                handleForegroundResume()
            }
        }
    }

    /// Re-establish connections and refresh data when returning from background.
    private func handleForegroundResume() {
        guard service.isAuthenticated,
              let accountId = service.activeAccount?.id else { return }

        Task {
            // Validate token is still good (refreshes if needed)
            let valid = await service.validateAndRefreshToken()
            guard valid else { return }

            // Reconnect SignalR if needed — the hub's auto-reconnect
            // handles the connection itself, but switching account
            // forces a fresh subscribe for positions/orders/quotes
            realtime.switchAccount(to: accountId)

            // Refresh account data
            await service.fetchAccounts()
        }
    }
}
