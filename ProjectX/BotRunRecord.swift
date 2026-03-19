import Foundation
import SwiftData

// ─────────────────────────────────────────────
// Bot Run Record — SwiftData Model
//
// Tracks which (bot, account) pairs are currently
// running. Persisted so cold-start restore can
// re-launch the correct instances after an app kill.
// ─────────────────────────────────────────────

@Model
final class BotRunRecord {
    var botId: UUID
    var accountId: Int
    var startedAt: Date
    @Attribute(originalName: "sessionPnL") var todayPnL: Double = 0
    @Attribute(originalName: "sessionTradeCount") var todayTradeCount: Int = 0

    init(botId: UUID, accountId: Int) {
        self.botId     = botId
        self.accountId = accountId
        self.startedAt = Date()
    }
}
