import Foundation
import Observation

// ─────────────────────────────────────────────
// NetworkLogger
//
// Centralized, in-memory log of all network
// activity (REST + SignalR). Entries auto-prune
// after 24 hours. Observable so SwiftUI views
// update live.
// ─────────────────────────────────────────────

@MainActor
@Observable
class NetworkLogger {

    static let shared = NetworkLogger()

    // MARK: - Types

    enum Source: String, CaseIterable, Identifiable {
        case all     = "All"
        case rest    = "REST"
        case signalR = "SignalR"

        var id: String { rawValue }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let source: Source          // .rest or .signalR
        let method: String          // "POST" or SignalR method name
        let path: String            // "/api/Account/search" or "UserHub"
        let statusCode: Int?        // HTTP status (REST) or nil (SignalR)
        let duration: TimeInterval? // elapsed seconds (REST) or nil
        let requestBody: String?
        let responseBody: String?
        let error: String?

        var isSuccess: Bool {
            if let code = statusCode {
                return (200..<300).contains(code)
            }
            return error == nil
        }
    }

    // MARK: - State

    private(set) var entries: [Entry] = []

    // MARK: - Actions

    func log(_ entry: Entry) {
        entries.insert(entry, at: 0)
        pruneOldEntries()
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: - Helpers

    /// Remove entries older than 24 hours.
    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        entries.removeAll { $0.timestamp < cutoff }
    }
}
