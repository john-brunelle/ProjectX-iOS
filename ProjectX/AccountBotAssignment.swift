import Foundation
import SwiftData

// ─────────────────────────────────────────────
// AccountBotAssignment — SwiftData Join Model
//
// Links accounts to bots (many-to-many).
// Bots are account-agnostic strategy definitions;
// accounts select which bots belong to them.
// ─────────────────────────────────────────────

@Model
final class AccountBotAssignment {
    var accountId: Int    // references Account.id
    var botId: UUID       // references BotConfig.id
    var assignedAt: Date

    init(accountId: Int, botId: UUID) {
        self.accountId = accountId
        self.botId = botId
        self.assignedAt = Date()
    }
}
