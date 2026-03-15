import Foundation

extension ProjectXService {

    // ── Search open positions ─────────────────

    func searchOpenPositions(accountId: Int) async -> [Position] {
        guard let token = sessionToken else { return [] }
        let body = PositionSearchRequest(accountId: accountId)
        guard let response: PositionSearchResponse = await post(
            path: "/api/Position/searchOpen", body: body, token: token
        ) else { return [] }
        return response.positions ?? []
    }

    // ── Close entire position ─────────────────

    func closePosition(accountId: Int, contractId: String) async -> Bool {
        guard let token = sessionToken else { return false }
        let body = ClosePositionRequest(accountId: accountId, contractId: contractId)
        guard let response: BasicResponse = await post(
            path: "/api/Position/closeContract", body: body, token: token
        ) else { return false }
        return response.success
    }

    // ── Partially close a position ────────────

    func partialClosePosition(accountId: Int, contractId: String, size: Int) async -> Bool {
        guard let token = sessionToken else { return false }
        let body = PartialClosePositionRequest(accountId: accountId, contractId: contractId, size: size)
        guard let response: BasicResponse = await post(
            path: "/api/Position/partialCloseContract", body: body, token: token
        ) else { return false }
        return response.success
    }
}
