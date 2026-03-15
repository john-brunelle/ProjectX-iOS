import SwiftUI

struct ContentView: View {
    @Environment(ProjectXService.self) var service
    @State private var isValidating    = true
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            // ── Main app content ──────────────
            Group {
                if isValidating {
                    // Silent validation — no UI shown here,
                    // splash covers it during cold start
                    Color.clear
                } else if service.isAuthenticated {
                    DashboardView()
                } else {
                    AuthView()
                }
            }

            // ── Splash overlay ────────────────
            if isShowingSplash {
                SplashView(isShowingSplash: $isShowingSplash)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            _ = await service.validateAndRefreshToken()
            isValidating = false
            // Splash dismisses itself after animation completes
            // so we don't force-dismiss it here
        }
    }
}
