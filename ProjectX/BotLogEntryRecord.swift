import Foundation
import SwiftData

// ─────────────────────────────────────────────
// Bot Log Entry Record — SwiftData Model
//
// Persists individual bot activity log entries
// so the log survives cold starts and app kills.
// Cleared only when a bot is explicitly restarted.
// ─────────────────────────────────────────────

@Model
final class BotLogEntryRecord {
    var id:        UUID
    var timestamp: Date
    var botId:     UUID
    var typeRaw:   String
    var message:   String

    init(entry: BotLogEntry) {
        self.id        = entry.id
        self.timestamp = entry.timestamp
        self.botId     = entry.botId
        self.typeRaw   = entry.type.rawValue
        self.message   = entry.message
    }

    func asLogEntry() -> BotLogEntry {
        BotLogEntry(
            id:        id,
            timestamp: timestamp,
            botId:     botId,
            type:      BotLogType(rawValue: typeRaw) ?? .info,
            message:   message
        )
    }
}
