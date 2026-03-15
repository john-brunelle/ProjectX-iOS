import SwiftUI

struct ContentView: View {
    @EnvironmentObject var service: ProjectXService
    @State private var isValidating = true

    var body: some View {
        Group {
            if isValidating {
                ProgressView("Checking session...")
            } else if service.isAuthenticated {
                DashboardView()
            } else {
                AuthView()
            }
        }
        .task {
            _ = await service.validateAndRefreshToken()
            isValidating = false
        }
    }
}
