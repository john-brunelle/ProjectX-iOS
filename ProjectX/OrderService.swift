import Foundation

extension ProjectXService {

    func searchOrders(
        accountId: Int,
        startTimestamp: Date,
        endTimestamp: Date? = nil
    ) async -> [Order] {
        guard let token = sessionToken else { return [] }
        let fmt = ISO8601DateFormatter()
        let body = OrderSearchRequest(
            accountId:      accountId,
            startTimestamp: fmt.string(from: startTimestamp),
            endTimestamp:   endTimestamp.map { fmt.string(from: $0) }
        )
        guard let response: OrderSearchResponse = await post(
            path: "/api/Order/search", body: body, token: token
        ) else { return [] }
        return response.orders ?? []
    }

    func searchOpenOrders(accountId: Int) async -> [Order] {
        guard let token = sessionToken else { return [] }
        let body = OpenOrderSearchRequest(accountId: accountId)
        guard let response: OrderSearchResponse = await post(
            path: "/api/Order/searchOpen", body: body, token: token
        ) else { return [] }
        return response.orders ?? []
    }

    func placeOrder(
        accountId: Int,
        contractId: String,
        type: OrderType,
        side: OrderSide,
        size: Int,
        limitPrice: Double? = nil,
        stopPrice: Double? = nil,
        trailPrice: Double? = nil,
        customTag: String? = nil,
        stopLoss: BracketOrder? = nil,
        takeProfit: BracketOrder? = nil
    ) async -> Int? {
        guard let token = sessionToken else { return nil }

        // ── Max Open Positions Guard ──────────────
        let maxPositions = UserDefaults.standard.object(forKey: "pref_maxOpenPositions") as? Int ?? 5
        let currentPositionCount = RealtimeService.shared.livePositions
            .filter { $0.accountId == accountId }
            .count

        if currentPositionCount >= maxPositions {
            let reason = "Blocked: \(currentPositionCount) open position\(currentPositionCount == 1 ? "" : "s") (limit: \(maxPositions)) on account \(accountId)"
            errorMessage = reason
            NetworkLogger.shared.log(NetworkLogger.Entry(
                timestamp: Date(),
                source: .rest,
                method: "GUARD",
                path: "guard/maxOpenPositions",
                statusCode: 403,
                duration: 0,
                requestBody: "{\"accountId\":\(accountId),\"contractId\":\"\(contractId)\",\"side\":\"\(side.rawValue)\",\"size\":\(size)}",
                responseBody: nil,
                error: reason
            ))
            return nil
        }

        // ── Max Daily Loss Guard ────────────────
        let dailyLossEnabled = UserDefaults.standard.bool(forKey: "pref_enableDailyLossLimit")
        if dailyLossEnabled {
            let maxDailyLoss = UserDefaults.standard.object(forKey: "pref_maxDailyLoss") as? Double ?? 500.0
            let dailyPnL = RealtimeService.shared.liveTrades
                .filter { $0.accountId == accountId && !$0.voided && !$0.isHalfTurn }
                .compactMap { $0.profitAndLoss }
                .reduce(0, +)

            if dailyPnL <= -maxDailyLoss {
                let reason = "Blocked: daily loss $\(String(format: "%.2f", abs(dailyPnL))) exceeds limit $\(String(format: "%.2f", maxDailyLoss)) on account \(accountId)"
                errorMessage = reason
                NetworkLogger.shared.log(NetworkLogger.Entry(
                    timestamp: Date(),
                    source: .rest,
                    method: "GUARD",
                    path: "guard/maxDailyLoss",
                    statusCode: 403,
                    duration: 0,
                    requestBody: "{\"accountId\":\(accountId),\"contractId\":\"\(contractId)\",\"side\":\"\(side.rawValue)\",\"size\":\(size)}",
                    responseBody: nil,
                    error: reason
                ))
                return nil
            }
        }

        let body = PlaceOrderRequest(
            accountId:         accountId,
            contractId:        contractId,
            type:              type.rawValue,
            side:              side.rawValue,
            size:              size,
            limitPrice:        limitPrice,
            stopPrice:         stopPrice,
            trailPrice:        trailPrice,
            customTag:         customTag,
            stopLossBracket:   stopLoss,
            takeProfitBracket: takeProfit
        )
        guard let response: PlaceOrderResponse = await post(
            path: "/api/Order/place", body: body, token: token
        ) else { return nil }
        guard response.success else {
            errorMessage = response.errorMessage ?? "Place order failed (code \(response.errorCode))"
            return nil
        }
        return response.orderId
    }

    func cancelOrder(accountId: Int, orderId: Int) async -> Bool {
        guard let token = sessionToken else { return false }
        let body = CancelOrderRequest(accountId: accountId, orderId: orderId)
        guard let response: BasicResponse = await post(
            path: "/api/Order/cancel", body: body, token: token
        ) else { return false }
        return response.success
    }

    func modifyOrder(
        accountId: Int,
        orderId: Int,
        size: Int? = nil,
        limitPrice: Double? = nil,
        stopPrice: Double? = nil,
        trailPrice: Double? = nil
    ) async -> Bool {
        guard let token = sessionToken else { return false }
        let body = ModifyOrderRequest(
            accountId:  accountId,
            orderId:    orderId,
            size:       size,
            limitPrice: limitPrice,
            stopPrice:  stopPrice,
            trailPrice: trailPrice
        )
        guard let response: BasicResponse = await post(
            path: "/api/Order/modify", body: body, token: token
        ) else { return false }
        return response.success
    }
}
