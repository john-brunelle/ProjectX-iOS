import Foundation
import Observation
import SignalRClient

// ─────────────────────────────────────────────
// RealtimeService
//
// Manages two SignalR hub connections:
//   - User Hub:   account, order, position, trade updates
//   - Market Hub: quotes, DOM, market trades for a contract
//
// Usage:
//   await realtimeService.connectUserHub(accountId: 123)
//   await realtimeService.connectMarketHub(contractId: "CON.F.US.EP.U25")
//   realtimeService.disconnect()
// ─────────────────────────────────────────────

@MainActor
@Observable
class RealtimeService {

    static let shared = RealtimeService()

    // ── Hub URLs ──────────────────────────────
    private let userHubURL   = "https://rtc.topstepx.com/hubs/user"
    private let marketHubURL = "https://rtc.topstepx.com/hubs/market"

    // ── Connections ───────────────────────────
    private var userConnection:   HubConnection?
    private var marketConnection: HubConnection?

    // ── Delegates (must be retained) ─────────
    private var userDelegate:   HubDelegate?
    private var marketDelegate: HubDelegate?

    // ── Observable state — User Hub ───────────
    var isUserConnected    = false
    var isMarketConnected  = false

    var liveAccounts:   [Account]  = []
    var liveOrders:     [Order]    = []
    var livePositions:  [Position] = []
    var liveTrades:     [Trade]    = []
    var initialDataLoaded = false

    // ── Observable state — Market Hub ─────────
    var contractQuotes: [String: Quote] = [:]
    var marketTrades:   [MarketTrade] = []
    var domEntries:     [DOMEntry]    = []

    /// Backward-compatible accessor for views that only show one quote.
    var currentQuote: Quote? { contractQuotes.values.first }

    private var subscribedAccountId:  Int?
    private(set) var subscribedContractIds: Set<String> = []

    /// The most recently subscribed contract (for foreground-resume reconnection).
    private(set) var subscribedContractId: String?

    // ─────────────────────────────────────────
    // MARK: User Hub
    // ─────────────────────────────────────────

    func connectUserHub(accountId: Int) {
        guard let token = ProjectXService.shared.sessionToken else {
            NetworkLogger.shared.log(NetworkLogger.Entry(
                timestamp: Date(), source: .signalR, method: "connectUserHub",
                path: "UserHub", statusCode: nil, duration: nil,
                requestBody: nil, responseBody: nil, error: "No session token"
            ))
            return
        }
        NetworkLogger.shared.log(NetworkLogger.Entry(
            timestamp: Date(), source: .signalR, method: "connectUserHub",
            path: "UserHub", statusCode: nil, duration: nil,
            requestBody: "accountId=\(accountId)", responseBody: "attempting...", error: nil
        ))
        subscribedAccountId = accountId

        let url = URL(string: "\(userHubURL)?access_token=\(token)")!

        userDelegate = HubDelegate(
            hubName: "UserHub",
            onOpen: { [weak self] _ in
                Task { @MainActor in
                    self?.isUserConnected = true
                    self?.subscribeUserHub()
                }
            },
            onClose: { [weak self] _ in
                Task { @MainActor in self?.isUserConnected = false }
            },
            onReconnect: { [weak self] in
                Task { @MainActor in
                    self?.isUserConnected = true
                    self?.subscribeUserHub()
                }
            }
        )

        userConnection = HubConnectionBuilder(url: url)
            .withHttpConnectionOptions { options in
                options.skipNegotiation = true
            }
            .withLogging(minLogLevel: .debug)
            .withAutoReconnect()
            .withHubConnectionDelegate(delegate: userDelegate!)
            .build()

        registerUserHandlers()

        userConnection?.on(method: "connected") { [weak self] in
            Task { @MainActor in
                self?.isUserConnected = true
                self?.subscribeUserHub()
            }
        }

        userConnection?.start()
    }

    func switchAccount(to accountId: Int) {
        NetworkLogger.shared.log(NetworkLogger.Entry(
            timestamp: Date(), source: .signalR, method: "switchAccount",
            path: "UserHub", statusCode: nil, duration: nil,
            requestBody: "accountId=\(accountId)", responseBody: "stopping+reconnecting", error: nil
        ))
        userConnection?.stop()
        userConnection = nil
        userDelegate = nil
        isUserConnected = false
        liveOrders    = []
        livePositions = []
        liveTrades    = []
        initialDataLoaded = false
        connectUserHub(accountId: accountId)
    }

    private func subscribeUserHub() {
        guard let conn = userConnection,
              let accountId = subscribedAccountId else { return }
        conn.invoke(method: "SubscribeAccounts")       { _ in }
        conn.invoke(method: "SubscribeOrders",    accountId) { _ in }
        conn.invoke(method: "SubscribePositions", accountId) { _ in }
        conn.invoke(method: "SubscribeTrades",    accountId) { _ in }

        // Seed initial state — SignalR only delivers future updates, not existing data
        Task { await fetchInitialUserData(accountId: accountId) }
    }

    private func fetchInitialUserData(accountId: Int) async {
        async let orders    = ProjectXService.shared.searchOpenOrders(accountId: accountId)
        async let positions = ProjectXService.shared.searchOpenPositions(accountId: accountId)
        async let trades    = ProjectXService.shared.searchTrades(accountId: accountId,
                                                                   startTimestamp: Self.sessionStart())
        let (fetchedOrders, fetchedPositions, fetchedTrades) = await (orders, positions, trades)

        // Replace: ensures clean, accurate state on every connect/reconnect
        liveOrders    = fetchedOrders
        livePositions = fetchedPositions
        liveTrades    = Array(fetchedTrades.prefix(200))
        initialDataLoaded = true

    }

    // ── Manual refresh (pull-to-refresh on HomeView) ──

    /// Re-fetches open positions, open orders, and today's trades.
    /// Called from HomeView's pull-to-refresh gesture.
    func refreshHomeData() async {
        guard let accountId = subscribedAccountId else { return }

        // Refresh account balance alongside trades/orders/positions
        async let acctRefresh      = ProjectXService.shared.fetchAccounts()
        async let fetchedOrders    = ProjectXService.shared.searchOpenOrders(accountId: accountId)
        async let fetchedPositions = ProjectXService.shared.searchOpenPositions(accountId: accountId)
        async let fetchedTrades    = ProjectXService.shared.searchTrades(accountId: accountId,
                                                                          startTimestamp: Self.sessionStart())
        let (_, orders, positions, trades) = await (acctRefresh, fetchedOrders, fetchedPositions, fetchedTrades)

        // Only overwrite if we got data — don't clear existing data with empty results
        // (can happen if REST call fails or races with fetchInitialUserData)
        if !positions.isEmpty || livePositions.isEmpty {
            livePositions = positions
        }
        if !orders.isEmpty || liveOrders.isEmpty {
            liveOrders = orders
        }
        if !trades.isEmpty || liveTrades.isEmpty {
            liveTrades = trades
        }
    }

    /// Called by BotRunner on each poll to keep data fresh via REST,
    /// independent of SignalR connection status.
    func updateFromREST(positions: [Position], orders: [Order], trades: [Trade]) {
        if !positions.isEmpty || livePositions.isEmpty {
            livePositions = positions
        }
        if !orders.isEmpty || liveOrders.isEmpty {
            liveOrders = orders
        }
        if !trades.isEmpty || liveTrades.isEmpty {
            liveTrades = Array(trades.prefix(200))
        }
        if !initialDataLoaded { initialDataLoaded = true }
    }

    private func unsubscribeUserHub() {
        guard let conn = userConnection,
              let accountId = subscribedAccountId else { return }
        conn.invoke(method: "UnsubscribeAccounts")       { _ in }
        conn.invoke(method: "UnsubscribeOrders",    accountId) { _ in }
        conn.invoke(method: "UnsubscribePositions", accountId) { _ in }
        conn.invoke(method: "UnsubscribeTrades",    accountId) { _ in }
    }

    private func registerUserHandlers() {
        // ── Account updates ───────────────────
        userConnection?.on(method: "GatewayUserAccount", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let id        = try data.getArgument(type: Int.self)
            let name      = try data.getArgument(type: String.self)
            let balance   = try data.getArgument(type: Double.self)
            let canTrade  = try data.getArgument(type: Bool.self)
            let isVisible = try data.getArgument(type: Bool.self)
            let updated = Account(id: id, name: name, balance: balance,
                                  canTrade: canTrade, isVisible: isVisible, simulated: nil)
            Task { @MainActor in
                if let idx = self.liveAccounts.firstIndex(where: { $0.id == id }) {
                    self.liveAccounts[idx] = updated
                } else {
                    self.liveAccounts.append(updated)
                }
                NetworkLogger.shared.log(NetworkLogger.Entry(
                    timestamp: Date(), source: .signalR, method: "GatewayUserAccount",
                    path: "UserHub", statusCode: nil, duration: nil,
                    requestBody: nil,
                    responseBody: "id=\(id) name=\(name) bal=\(balance) canTrade=\(canTrade)",
                    error: nil
                ))
            }
        })

        // ── Order updates ─────────────────────
        userConnection?.on(method: "GatewayUserOrder", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let id           = try data.getArgument(type: Int.self)
            let accountId    = try data.getArgument(type: Int.self)
            let contractId   = try data.getArgument(type: String.self)
            let symbolId     = try? data.getArgument(type: String.self)
            let creationTs   = try data.getArgument(type: String.self)
            let updateTs     = try data.getArgument(type: String.self)
            let status       = try data.getArgument(type: Int.self)
            let type         = try data.getArgument(type: Int.self)
            let side         = try data.getArgument(type: Int.self)
            let size         = try data.getArgument(type: Int.self)
            let order = Order(
                id: id, accountId: accountId, contractId: contractId,
                symbolId: symbolId, creationTimestamp: creationTs,
                updateTimestamp: updateTs, status: status, type: type,
                side: side, size: size,
                limitPrice: try? data.getArgument(type: Double.self),
                stopPrice:  try? data.getArgument(type: Double.self),
                fillVolume: try? data.getArgument(type: Int.self),
                filledPrice: try? data.getArgument(type: Double.self),
                customTag:  try? data.getArgument(type: String.self)
            )
            Task { @MainActor in
                if let idx = self.liveOrders.firstIndex(where: { $0.id == id }) {
                    self.liveOrders[idx] = order
                } else {
                    self.liveOrders.insert(order, at: 0)
                }
                if order.status == 2 {
                    NotificationService.shared.notifyOrderFilled(
                        orderId: order.id, side: order.sideLabel,
                        size: order.size, contractId: order.contractId)
                }
                NetworkLogger.shared.log(NetworkLogger.Entry(
                    timestamp: Date(), source: .signalR, method: "GatewayUserOrder",
                    path: "UserHub", statusCode: nil, duration: nil,
                    requestBody: nil,
                    responseBody: "id=\(id) contract=\(contractId) side=\(side) size=\(size) status=\(status) type=\(type)",
                    error: nil
                ))
            }
        })

        // ── Position updates ──────────────────
        userConnection?.on(method: "GatewayUserPosition", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let id         = try data.getArgument(type: Int.self)
            let accountId  = try data.getArgument(type: Int.self)
            let contractId = try data.getArgument(type: String.self)
            let creationTs = try data.getArgument(type: String.self)
            let type       = try data.getArgument(type: Int.self)
            let size       = try data.getArgument(type: Int.self)
            let avgPrice   = try data.getArgument(type: Double.self)
            let position = Position(
                id: id, accountId: accountId, contractId: contractId,
                creationTimestamp: creationTs, type: type,
                size: size, averagePrice: avgPrice
            )
            Task { @MainActor in
                if size == 0 {
                    self.livePositions.removeAll { $0.id == id }
                } else if let idx = self.livePositions.firstIndex(where: { $0.id == id }) {
                    self.livePositions[idx] = position
                } else {
                    self.livePositions.append(position)
                }
                NetworkLogger.shared.log(NetworkLogger.Entry(
                    timestamp: Date(), source: .signalR, method: "GatewayUserPosition",
                    path: "UserHub", statusCode: nil, duration: nil,
                    requestBody: nil,
                    responseBody: "id=\(id) contract=\(contractId) type=\(type) size=\(size) avgPrice=\(avgPrice)",
                    error: nil
                ))
            }
        })

        // ── Trade updates ─────────────────────
        userConnection?.on(method: "GatewayUserTrade", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let id         = try data.getArgument(type: Int.self)
            let accountId  = try data.getArgument(type: Int.self)
            let contractId = try data.getArgument(type: String.self)
            let creationTs = try data.getArgument(type: String.self)
            let price      = try data.getArgument(type: Double.self)
            let fees       = try data.getArgument(type: Double.self)
            let side       = try data.getArgument(type: Int.self)
            let size       = try data.getArgument(type: Int.self)
            let voided     = try data.getArgument(type: Bool.self)
            let orderId    = try data.getArgument(type: Int.self)
            let trade = Trade(
                id: id, accountId: accountId, contractId: contractId,
                creationTimestamp: creationTs, price: price,
                profitAndLoss: try? data.getArgument(type: Double.self),
                fees: fees, side: side, size: size,
                voided: voided, orderId: orderId
            )
            Task { @MainActor in
                self.liveTrades.insert(trade, at: 0)
                if self.liveTrades.count > 200 {
                    self.liveTrades = Array(self.liveTrades.prefix(200))
                }
                NetworkLogger.shared.log(NetworkLogger.Entry(
                    timestamp: Date(), source: .signalR, method: "GatewayUserTrade",
                    path: "UserHub", statusCode: nil, duration: nil,
                    requestBody: nil,
                    responseBody: "id=\(id) orderId=\(orderId) side=\(side) size=\(size) price=\(price) pnl=\(trade.profitAndLoss.map { String($0) } ?? "nil")",
                    error: nil
                ))
            }
        })
    }

    // ─────────────────────────────────────────
    // MARK: Market Hub
    // ─────────────────────────────────────────

    func connectMarketHub(contractId: String) {
        guard let token = ProjectXService.shared.sessionToken else { return }

        subscribedContractIds.insert(contractId)
        subscribedContractId = contractId

        if marketConnection == nil {
            let url = URL(string: "\(marketHubURL)?access_token=\(token)")!

            NetworkLogger.shared.log(NetworkLogger.Entry(
                timestamp: Date(), source: .signalR, method: "connectMarketHub",
                path: "MarketHub", statusCode: nil, duration: nil,
                requestBody: "contractId=\(contractId)", responseBody: "attempting...", error: nil
            ))

            marketDelegate = HubDelegate(
                hubName: "MarketHub",
                onOpen: { [weak self] _ in
                    Task { @MainActor in
                        self?.isMarketConnected = true
                        self?.resubscribeAllMarketContracts()
                    }
                },
                onClose: { [weak self] _ in
                    Task { @MainActor in self?.isMarketConnected = false }
                },
                onReconnect: { [weak self] in
                    Task { @MainActor in
                        self?.isMarketConnected = true
                        self?.resubscribeAllMarketContracts()
                    }
                }
            )

            marketConnection = HubConnectionBuilder(url: url)
                .withHttpConnectionOptions { options in
                    options.skipNegotiation = true
                }
                .withLogging(minLogLevel: .debug)
                .withAutoReconnect()
                .withHubConnectionDelegate(delegate: marketDelegate!)
                .build()
            registerMarketHandlers()

            marketConnection?.on(method: "connected") { [weak self] in
                Task { @MainActor in
                    self?.isMarketConnected = true
                    self?.resubscribeAllMarketContracts()
                }
            }

            marketConnection?.start()
        } else {
            subscribeMarketHub(contractId: contractId)
        }
    }

    private func subscribeMarketHub(contractId: String) {
        marketConnection?.invoke(method: "SubscribeContractQuotes",      contractId) { _ in }
        marketConnection?.invoke(method: "SubscribeContractTrades",      contractId) { _ in }
        marketConnection?.invoke(method: "SubscribeContractMarketDepth", contractId) { _ in }
    }

    /// Re-subscribe all tracked contracts after a reconnection.
    private func resubscribeAllMarketContracts() {
        for cid in subscribedContractIds {
            subscribeMarketHub(contractId: cid)
        }
    }

    private func unsubscribeMarketHub(contractId: String) {
        marketConnection?.invoke(method: "UnsubscribeContractQuotes",      contractId) { _ in }
        marketConnection?.invoke(method: "UnsubscribeContractTrades",      contractId) { _ in }
        marketConnection?.invoke(method: "UnsubscribeContractMarketDepth", contractId) { _ in }
        subscribedContractIds.remove(contractId)
        contractQuotes.removeValue(forKey: contractId)
        marketTrades  = []
        domEntries    = []
    }

    /// Unsubscribe a single contract without tearing down the whole Market Hub.
    func disconnectMarketContract(contractId: String) {
        unsubscribeMarketHub(contractId: contractId)
        if subscribedContractIds.isEmpty {
            subscribedContractId = nil
        }
    }

    private func registerMarketHandlers() {
        // ── Live Quote ────────────────────────
        // Server sends: ["contractId", { quote object }]
        marketConnection?.on(method: "GatewayQuote", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let contractId = try data.getArgument(type: String.self)
            let quote      = try data.getArgument(type: Quote.self)
            Task { @MainActor in
                self.contractQuotes[contractId] = quote
                NetworkLogger.shared.log(NetworkLogger.Entry(
                    timestamp: Date(), source: .signalR, method: "GatewayQuote",
                    path: "MarketHub", statusCode: nil, duration: nil,
                    requestBody: nil,
                    responseBody: "\(quote.symbol) last=\(quote.lastPrice) bid=\(quote.bestBid) ask=\(quote.bestAsk) vol=\(quote.volume)",
                    error: nil
                ))
            }
        })

        // ── Market Trades ─────────────────────
        // Server sends: ["contractId", { trade object }]
        marketConnection?.on(method: "GatewayTrade", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let _       = try data.getArgument(type: String.self) // contractId
            let payload = try data.getArgument(type: MarketTradePayload.self)
            let trade   = MarketTrade(from: payload)
            Task { @MainActor in
                self.marketTrades.insert(trade, at: 0)
                if self.marketTrades.count > 100 {
                    self.marketTrades = Array(self.marketTrades.prefix(100))
                }
                NetworkLogger.shared.log(NetworkLogger.Entry(
                    timestamp: Date(), source: .signalR, method: "GatewayTrade",
                    path: "MarketHub", statusCode: nil, duration: nil,
                    requestBody: nil,
                    responseBody: "\(payload.symbolId) price=\(payload.price) vol=\(payload.volume) type=\(payload.type)",
                    error: nil
                ))
            }
        })

        // ── DOM / Depth ───────────────────────
        // Server sends: ["contractId", [array of depth entries]]
        marketConnection?.on(method: "GatewayDepth", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let _       = try data.getArgument(type: String.self) // contractId
            let entries = try data.getArgument(type: [DepthEntry].self)

            Task { @MainActor in
                // Check for DOM reset
                if entries.count == 1 && entries[0].type == DomType.reset.rawValue {
                    self.domEntries = []
                    return
                }

                for entry in entries {
                    let domEntry = DOMEntry(
                        timestamp: entry.timestamp, type: entry.type,
                        price: entry.price, volume: entry.volume, currentVolume: entry.currentVolume
                    )
                    self.domEntries.removeAll { $0.price == entry.price && $0.type == entry.type }
                    if entry.volume > 0 { self.domEntries.append(domEntry) }
                }
                self.domEntries.sort { $0.price > $1.price }
                if self.domEntries.count > 40 {
                    self.domEntries = Array(self.domEntries.prefix(40))
                }
            }
        })
    }

    // ─────────────────────────────────────────
    // MARK: Disconnect
    // ─────────────────────────────────────────

    func disconnectAll() {
        NetworkLogger.shared.log(NetworkLogger.Entry(
            timestamp: Date(), source: .signalR, method: "disconnectAll",
            path: "UserHub+MarketHub", statusCode: nil, duration: nil,
            requestBody: nil, responseBody: "stopping all connections", error: nil
        ))
        unsubscribeUserHub()
        for cid in subscribedContractIds {
            unsubscribeMarketHub(contractId: cid)
        }
        subscribedContractIds.removeAll()
        subscribedContractId = nil
        userConnection?.stop()
        marketConnection?.stop()
        userConnection   = nil
        marketConnection = nil
        isUserConnected  = false
        isMarketConnected = false
    }

    func disconnectMarket() {
        for cid in subscribedContractIds {
            unsubscribeMarketHub(contractId: cid)
        }
        subscribedContractIds.removeAll()
        subscribedContractId = nil
        marketConnection?.stop()
        marketConnection  = nil
        isMarketConnected = false
    }

    // ── CME session start ─────────────────────

    /// Returns the start of the current CME Globex trading session.
    /// CME sessions open at 5:00 PM CT and run until 4:00 PM CT the next day.
    /// Trades between 5 PM CT yesterday and midnight are part of "today's" session
    /// but would be missed if we used calendar midnight as the boundary.
    static func sessionStart(for date: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        let hour = cal.component(.hour, from: date)
        // Before 5 PM CT → session started yesterday at 17:00 CT
        // At or after 5 PM CT → session started today at 17:00 CT
        let sessionDay = hour < 17
            ? cal.date(byAdding: .day, value: -1, to: date)!
            : date
        var comps = cal.dateComponents([.year, .month, .day], from: sessionDay)
        comps.hour = 17; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? date
    }
}

// ─────────────────────────────────────────────
// HubDelegate — bridges HubConnectionDelegate
// lifecycle events to closures
// ─────────────────────────────────────────────

class HubDelegate: HubConnectionDelegate {
    private let hubName:            String
    private let onOpenHandler:      (HubConnection) -> Void
    private let onCloseHandler:     (Error?) -> Void
    private let onReconnectHandler: () -> Void

    init(
        hubName:     String,
        onOpen:      @escaping (HubConnection) -> Void = { _ in },
        onClose:     @escaping (Error?) -> Void         = { _ in },
        onReconnect: @escaping () -> Void               = {}
    ) {
        self.hubName            = hubName
        self.onOpenHandler      = onOpen
        self.onCloseHandler     = onClose
        self.onReconnectHandler = onReconnect
    }

    func connectionDidOpen(hubConnection: HubConnection) {
        NetworkLogger.shared.log(NetworkLogger.Entry(
            timestamp: Date(), source: .signalR, method: "connectionDidOpen",
            path: hubName, statusCode: nil, duration: nil,
            requestBody: nil, responseBody: "connected", error: nil
        ))
        onOpenHandler(hubConnection)
    }

    func connectionDidFailToOpen(error: Error) {
        NetworkLogger.shared.log(NetworkLogger.Entry(
            timestamp: Date(), source: .signalR, method: "connectionDidFailToOpen",
            path: hubName, statusCode: nil, duration: nil,
            requestBody: nil, responseBody: nil, error: String(describing: error)
        ))
    }

    func connectionDidClose(error: Error?) {
        NetworkLogger.shared.log(NetworkLogger.Entry(
            timestamp: Date(), source: .signalR, method: "connectionDidClose",
            path: hubName, statusCode: nil, duration: nil,
            requestBody: nil, responseBody: nil,
            error: error.map { String(describing: $0) }
        ))
        onCloseHandler(error)
    }

    func connectionWillReconnect(error: Error) {
        NetworkLogger.shared.log(NetworkLogger.Entry(
            timestamp: Date(), source: .signalR, method: "connectionWillReconnect",
            path: hubName, statusCode: nil, duration: nil,
            requestBody: nil, responseBody: nil, error: String(describing: error)
        ))
    }

    func connectionDidReconnect() {
        NetworkLogger.shared.log(NetworkLogger.Entry(
            timestamp: Date(), source: .signalR, method: "connectionDidReconnect",
            path: hubName, statusCode: nil, duration: nil,
            requestBody: nil, responseBody: "reconnected", error: nil
        ))
        onReconnectHandler()
    }
}
