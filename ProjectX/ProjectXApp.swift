import SwiftUI

@main
struct ProjectXApp: App {
    @State private var service = ProjectXService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(service)
        }
    }
}
