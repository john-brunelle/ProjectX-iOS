import Foundation

extension ProjectXService {

    // ── Search trades by date range ───────────
    // Note: profitAndLoss == nil means a half-turn trade (entry without exit)

    func searchTrades(
        accountId: Int,
        startTimestamp: Date,
        endTimestamp: Date? = nil
    ) async -> [Trade] {
        guard let token = sessionToken else { return [] }
        let fmt = ISO8601DateFormatter()
        let body = TradeSearchRequest(
            accountId:      accountId,
            startTimestamp: fmt.string(from: startTimestamp),
            endTimestamp:   endTimestamp.map { fmt.string(from: $0) }
        )
        guard let response: TradeSearchResponse = await post(
            path: "/api/Trade/search", body: body, token: token
        ) else { return [] }
        return response.trades ?? []
    }
}
