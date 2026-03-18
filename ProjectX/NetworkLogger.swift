import Foundation
import Observation
import SwiftData

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

    enum Endpoint: String, CaseIterable, Identifiable {
        case all          = "All Endpoints"
        case auth         = "Auth"
        case accounts     = "Accounts"
        case orders       = "Orders"
        case positions    = "Positions"
        case trades       = "Trades"
        case quotes       = "Quotes"
        case bars         = "Bars"
        case marketDepth  = "Market Depth"
        case connection   = "Connection"
        case lifecycle    = "Lifecycle"
        case guards       = "Guards"

        var id: String { rawValue }

        func matches(_ entry: Entry) -> Bool {
            switch self {
            case .all:         return true
            case .auth:        return entry.path.contains("/api/Auth")
            case .accounts:    return entry.path.contains("/api/Account") || entry.method == "GatewayUserAccount"
            case .orders:      return entry.method == "GatewayUserOrder"
            case .positions:   return entry.method == "GatewayUserPosition"
            case .trades:      return entry.method == "GatewayUserTrade" || entry.method == "GatewayTrade"
            case .quotes:      return entry.method == "GatewayQuote"
            case .bars:        return entry.path.contains("/api/History/retrieveBars")
            case .marketDepth: return entry.method == "GatewayDepth"
            case .connection:  return entry.method.hasPrefix("connect") || entry.method.hasPrefix("disconnect") || entry.method.hasPrefix("switch") || entry.method.hasPrefix("connectionDid") || entry.method.hasPrefix("connectionWill")
            case .lifecycle:   return entry.path == "lifecycle"
            case .guards:      return entry.path.hasPrefix("guard/")
            }
        }
    }

    struct Entry: Identifiable {
        let id: UUID
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

        init(
            id: UUID = UUID(),
            timestamp: Date,
            source: Source,
            method: String,
            path: String,
            statusCode: Int?,
            duration: TimeInterval?,
            requestBody: String?,
            responseBody: String?,
            error: String?
        ) {
            self.id = id
            self.timestamp = timestamp
            self.source = source
            self.method = method
            self.path = path
            self.statusCode = statusCode
            self.duration = duration
            self.requestBody = requestBody
            self.responseBody = responseBody
            self.error = error
        }
    }

    // MARK: - Rate Monitoring

    /// Number of bars feed requests in the last 30 seconds (limit: 50).
    var barsFeedRequestsPer30s: Int {
        let cutoff = Date().addingTimeInterval(-30)
        return entries.count { $0.timestamp >= cutoff && $0.path.contains("/api/History/retrieveBars") }
    }

    /// Number of non-bars REST requests in the last 60 seconds (limit: 200).
    var otherRequestsPer60s: Int {
        let cutoff = Date().addingTimeInterval(-60)
        return entries.count { $0.timestamp >= cutoff && $0.source == .rest && !$0.path.contains("/api/History/retrieveBars") }
    }

    // MARK: - State

    private(set) var entries: [Entry] = []
    var modelContext: ModelContext?

    private let maxRecords = 500

    // MARK: - Actions

    func log(_ entry: Entry) {
        entries.insert(entry, at: 0)
        pruneOldEntries()
        persistRecord(entry)
    }

    func clear() {
        entries.removeAll()
        removeAllRecords()
    }

    /// Load persisted entries from SwiftData on cold start.
    func restoreEntries() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<NetworkLogRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let records = try? ctx.fetch(descriptor) else { return }
        entries = records.map { $0.asEntry() }
        pruneOldEntries()
    }

    // MARK: - Persistence Helpers

    private func persistRecord(_ entry: Entry) {
        guard let ctx = modelContext else { return }
        ctx.insert(NetworkLogRecord(entry: entry))
        trimRecords(in: ctx)
        try? ctx.save()
    }

    private func trimRecords(in ctx: ModelContext) {
        let cutoff = Date().addingTimeInterval(-12 * 60 * 60)
        let staleDescriptor = FetchDescriptor<NetworkLogRecord>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        if let stale = try? ctx.fetch(staleDescriptor) {
            for record in stale { ctx.delete(record) }
        }

        let countDescriptor = FetchDescriptor<NetworkLogRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let all = try? ctx.fetch(countDescriptor), all.count > maxRecords {
            for record in all.dropFirst(maxRecords) { ctx.delete(record) }
        }
    }

    private func removeAllRecords() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<NetworkLogRecord>()
        if let records = try? ctx.fetch(descriptor) {
            for record in records { ctx.delete(record) }
        }
        try? ctx.save()
    }

    // MARK: - In-Memory Helpers

    /// Remove entries older than 12 hours.
    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-12 * 60 * 60)
        entries.removeAll { $0.timestamp < cutoff }
    }
}
