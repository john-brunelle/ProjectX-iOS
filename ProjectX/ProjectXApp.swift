import SwiftUI

@main
struct ProjectXApp: App {
    @State private var service  = ProjectXService.shared
    @State private var realtime = RealtimeService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(service)
                .environment(realtime)
        }
    }
}
