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
    private let userHubURL   = "https://rtc.thefuturesdesk.projectx.com/hubs/user"
    private let marketHubURL = "https://rtc.thefuturesdesk.projectx.com/hubs/market"

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

    // ── Observable state — Market Hub ─────────
    var currentQuote:   Quote?     = nil
    var marketTrades:   [MarketTrade] = []
    var domEntries:     [DOMEntry]    = []

    private var subscribedAccountId:  Int?
    private var subscribedContractId: String?

    // ─────────────────────────────────────────
    // MARK: User Hub
    // ─────────────────────────────────────────

    func connectUserHub(accountId: Int) {
        guard let token = ProjectXService.shared.sessionToken else {
            print("RealtimeService: No session token")
            return
        }
        subscribedAccountId = accountId

        let url = URL(string: "\(userHubURL)?access_token=\(token)")!

        userDelegate = HubDelegate(
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
            .withLogging(minLogLevel: .warning)
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

    private func subscribeUserHub() {
        guard let conn = userConnection,
              let accountId = subscribedAccountId else { return }
        conn.invoke(method: "SubscribeAccounts")       { _ in }
        conn.invoke(method: "SubscribeOrders",    accountId) { _ in }
        conn.invoke(method: "SubscribePositions", accountId) { _ in }
        conn.invoke(method: "SubscribeTrades",    accountId) { _ in }
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
                                  canTrade: canTrade, isVisible: isVisible)
            Task { @MainActor in
                if let idx = self.liveAccounts.firstIndex(where: { $0.id == id }) {
                    self.liveAccounts[idx] = updated
                } else {
                    self.liveAccounts.append(updated)
                }
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
                    // Position closed — remove it
                    self.livePositions.removeAll { $0.id == id }
                } else if let idx = self.livePositions.firstIndex(where: { $0.id == id }) {
                    self.livePositions[idx] = position
                } else {
                    self.livePositions.append(position)
                }
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
                // Keep last 200 trades in memory
                if self.liveTrades.count > 200 {
                    self.liveTrades = Array(self.liveTrades.prefix(200))
                }
            }
        })
    }

    // ─────────────────────────────────────────
    // MARK: Market Hub
    // ─────────────────────────────────────────

    func connectMarketHub(contractId: String) {
        guard let token = ProjectXService.shared.sessionToken else { return }

        // Unsubscribe previous contract if any
        if let prev = subscribedContractId, prev != contractId {
            unsubscribeMarketHub(contractId: prev)
        }
        subscribedContractId = contractId

        if marketConnection == nil {
            let url = URL(string: "\(marketHubURL)?access_token=\(token)")!

            marketDelegate = HubDelegate(
                onOpen: { [weak self] _ in
                    Task { @MainActor in
                        self?.isMarketConnected = true
                        if let cid = self?.subscribedContractId {
                            self?.subscribeMarketHub(contractId: cid)
                        }
                    }
                },
                onClose: { [weak self] _ in
                    Task { @MainActor in self?.isMarketConnected = false }
                },
                onReconnect: { [weak self] in
                    Task { @MainActor in
                        self?.isMarketConnected = true
                        if let cid = self?.subscribedContractId {
                            self?.subscribeMarketHub(contractId: cid)
                        }
                    }
                }
            )

            marketConnection = HubConnectionBuilder(url: url)
                .withLogging(minLogLevel: .warning)
                .withAutoReconnect()
                .withHubConnectionDelegate(delegate: marketDelegate!)
                .build()
            registerMarketHandlers()

            marketConnection?.on(method: "connected") { [weak self] in
                Task { @MainActor in
                    self?.isMarketConnected = true
                    if let cid = self?.subscribedContractId {
                        self?.subscribeMarketHub(contractId: cid)
                    }
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

    private func unsubscribeMarketHub(contractId: String) {
        marketConnection?.invoke(method: "UnsubscribeContractQuotes",      contractId) { _ in }
        marketConnection?.invoke(method: "UnsubscribeContractTrades",      contractId) { _ in }
        marketConnection?.invoke(method: "UnsubscribeContractMarketDepth", contractId) { _ in }
        currentQuote  = nil
        marketTrades  = []
        domEntries    = []
    }

    private func registerMarketHandlers() {
        // ── Live Quote ────────────────────────
        marketConnection?.on(method: "GatewayQuote", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let _            = try data.getArgument(type: String.self) // contractId
            let symbol       = try data.getArgument(type: String.self)
            let symbolName   = try data.getArgument(type: String.self)
            let lastPrice    = try data.getArgument(type: Double.self)
            let bestBid      = try data.getArgument(type: Double.self)
            let bestAsk      = try data.getArgument(type: Double.self)
            let change       = try data.getArgument(type: Double.self)
            let changePct    = try data.getArgument(type: Double.self)
            let open         = try data.getArgument(type: Double.self)
            let high         = try data.getArgument(type: Double.self)
            let low          = try data.getArgument(type: Double.self)
            let volume       = try data.getArgument(type: Double.self)
            let lastUpdated  = try data.getArgument(type: String.self)
            let timestamp    = try data.getArgument(type: String.self)
            let quote = Quote(
                symbol: symbol, symbolName: symbolName,
                lastPrice: lastPrice, bestBid: bestBid, bestAsk: bestAsk,
                change: change, changePercent: changePct,
                open: open, high: high, low: low, volume: volume,
                lastUpdated: lastUpdated, timestamp: timestamp
            )
            Task { @MainActor in self.currentQuote = quote }
        })

        // ── Market Trades ─────────────────────
        marketConnection?.on(method: "GatewayTrade", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let _         = try data.getArgument(type: String.self) // contractId
            let symbolId  = try data.getArgument(type: String.self)
            let price     = try data.getArgument(type: Double.self)
            let timestamp = try data.getArgument(type: String.self)
            let type      = try data.getArgument(type: Int.self)
            let volume    = try data.getArgument(type: Int.self)
            let trade = MarketTrade(
                symbolId: symbolId, price: price,
                timestamp: timestamp, type: type, volume: volume
            )
            Task { @MainActor in
                self.marketTrades.insert(trade, at: 0)
                if self.marketTrades.count > 100 {
                    self.marketTrades = Array(self.marketTrades.prefix(100))
                }
            }
        })

        // ── DOM / Depth ───────────────────────
        marketConnection?.on(method: "GatewayDepth", callback: { [weak self] (data: ArgumentExtractor) throws in
            guard let self else { return }
            let _             = try data.getArgument(type: String.self) // contractId
            let timestamp     = try data.getArgument(type: String.self)
            let type          = try data.getArgument(type: Int.self)
            let price         = try data.getArgument(type: Double.self)
            let volume        = try data.getArgument(type: Int.self)
            let currentVolume = try data.getArgument(type: Int.self)

            // Handle DOM reset
            if type == DomType.reset.rawValue {
                Task { @MainActor in self.domEntries = [] }
                return
            }

            let entry = DOMEntry(
                timestamp: timestamp, type: type,
                price: price, volume: volume, currentVolume: currentVolume
            )
            Task { @MainActor in
                self.domEntries.removeAll { $0.price == price && $0.type == type }
                if volume > 0 { self.domEntries.append(entry) }
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
        unsubscribeUserHub()
        if let cid = subscribedContractId {
            unsubscribeMarketHub(contractId: cid)
        }
        userConnection?.stop()
        marketConnection?.stop()
        userConnection   = nil
        marketConnection = nil
        isUserConnected  = false
        isMarketConnected = false
    }

    func disconnectMarket() {
        if let cid = subscribedContractId {
            unsubscribeMarketHub(contractId: cid)
        }
        marketConnection?.stop()
        marketConnection  = nil
        isMarketConnected = false
    }
}

// ─────────────────────────────────────────────
// HubDelegate — bridges HubConnectionDelegate
// lifecycle events to closures
// ─────────────────────────────────────────────

class HubDelegate: HubConnectionDelegate {
    private let onOpenHandler:      (HubConnection) -> Void
    private let onCloseHandler:     (Error?) -> Void
    private let onReconnectHandler: () -> Void

    init(
        onOpen:      @escaping (HubConnection) -> Void = { _ in },
        onClose:     @escaping (Error?) -> Void         = { _ in },
        onReconnect: @escaping () -> Void               = {}
    ) {
        self.onOpenHandler      = onOpen
        self.onCloseHandler     = onClose
        self.onReconnectHandler = onReconnect
    }

    func connectionDidOpen(hubConnection: HubConnection) {
        onOpenHandler(hubConnection)
    }

    func connectionDidFailToOpen(error: Error) {
        print("RealtimeService: Connection failed to open: \(error)")
    }

    func connectionDidClose(error: Error?) {
        onCloseHandler(error)
    }

    func connectionDidReconnect() {
        onReconnectHandler()
    }
}
