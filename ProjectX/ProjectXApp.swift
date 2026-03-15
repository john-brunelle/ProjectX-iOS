import SwiftUI

@main
struct ProjectXApp: App {
    @StateObject private var service = ProjectXService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
        }
    }
}
