import Foundation

// ─────────────────────────────────────────────
// Bar Service — ProjectXService Extension
//
// Convenience wrappers around retrieveBars()
// for bot seeding and wizard validation.
// ─────────────────────────────────────────────

extension ProjectXService {

    /// Fetch historical bars for a bot's configuration.
    /// Used by the bot runner for initial seeding (Phase 3)
    /// and by the detail view for data validation.
    func retrieveBarsForBot(
        _ bot: BotConfig,
        daysBack: Int = 30,
        limit: Int = 500
    ) async -> [Bar] {
        guard let unit = bot.barUnitEnum else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
        return await retrieveBars(
            contractId: bot.contractId,
            live: false,
            startTime: start,
            endTime: Date(),
            unit: unit,
            unitNumber: bot.barUnitNumber,
            limit: limit
        )
    }

    /// Fetch bars using raw wizard parameters (before bot is persisted).
    /// Used by the review step to show bar availability count.
    func retrieveBarsForConfig(
        contractId: String,
        barUnit: BarUnit,
        barUnitNumber: Int,
        daysBack: Int = 7,
        limit: Int = 200
    ) async -> [Bar] {
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
        return await retrieveBars(
            contractId: contractId,
            live: false,
            startTime: start,
            endTime: Date(),
            unit: barUnit,
            unitNumber: barUnitNumber,
            limit: limit
        )
    }
}
