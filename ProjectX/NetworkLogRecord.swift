import Foundation
import SwiftData

// ─────────────────────────────────────────────
// Network Log Record — SwiftData Model
//
// Persists NetworkLogger entries so the network
// activity log survives cold starts and app kills.
// ─────────────────────────────────────────────

@Model
final class NetworkLogRecord {
    var id:           UUID
    var timestamp:    Date
    var sourceRaw:    String
    var method:       String
    var path:         String
    var statusCode:   Int?
    var duration:     Double?
    var requestBody:  String?
    var responseBody: String?
    var error:        String?

    init(entry: NetworkLogger.Entry) {
        self.id           = entry.id
        self.timestamp    = entry.timestamp
        self.sourceRaw    = entry.source.rawValue
        self.method       = entry.method
        self.path         = entry.path
        self.statusCode   = entry.statusCode
        self.duration     = entry.duration
        self.requestBody  = entry.requestBody
        self.responseBody = entry.responseBody
        self.error        = entry.error
    }

    func asEntry() -> NetworkLogger.Entry {
        NetworkLogger.Entry(
            id:           id,
            timestamp:    timestamp,
            source:       NetworkLogger.Source(rawValue: sourceRaw) ?? .rest,
            method:       method,
            path:         path,
            statusCode:   statusCode,
            duration:     duration,
            requestBody:  requestBody,
            responseBody: responseBody,
            error:        error
        )
    }
}
