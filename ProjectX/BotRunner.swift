import Foundation
import SwiftData

// ─────────────────────────────────────────────
// Bot Runner — Live Trading Engine
//
// Manages running bots: polls bars, evaluates
// indicators, places orders when signals fire.
//
// Each (bot, account) pair runs independently.
// The same bot can run on multiple accounts
// concurrently, each with its own poll loop,
// signal state, and session P&L.
// ─────────────────────────────────────────────

// MARK: - Log Types

enum BotLogType: String {
    case signal
    case order
    case error
    case info
}

struct BotLogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let botId: UUID
    let accountId: Int
    let type: BotLogType
    let message: String

    /// New entry — generates a fresh id.
    init(timestamp: Date, botId: UUID, accountId: Int = 0, type: BotLogType, message: String) {
        self.id        = UUID()
        self.timestamp = timestamp
        self.botId     = botId
        self.accountId = accountId
        self.type      = type
        self.message   = message
    }

    /// Reconstructed from a persisted record — preserves the original id.
    init(id: UUID, timestamp: Date, botId: UUID, accountId: Int = 0, type: BotLogType, message: String) {
        self.id        = id
        self.timestamp = timestamp
        self.botId     = botId
        self.accountId = accountId
        self.type      = type
        self.message   = message
    }
}

// MARK: - Composite Run Key

struct BotRunKey: Hashable {
    let botId: UUID
    let accountId: Int
}

// MARK: - Per-Instance Runtime State

struct BotRunState {
    var task: Task<Void, Never>?
    var lastSignal: Signal = .neutral
    var lastBarTime: String?
    var lastPollTime: Date?
    var log: [BotLogEntry] = []

    // P&L tracking — matched via orderId against liveTrades
    var placedOrderIds: Set<Int> = []
    var customTags: Set<String> = []      // tags from parent orders to match bracket children
    var sessionPnL: Double = 0            // realized P&L from closed trades
    var unrealizedPnL: Double = 0         // unrealized P&L from open position
    var sessionTradeCount: Int = 0
}

// MARK: - Bot Runner

@MainActor
@Observable
class BotRunner {
    static let shared = BotRunner()

    private let service = ProjectXService.shared
    private let realtime = RealtimeService.shared

    private(set) var runStates: [BotRunKey: BotRunState] = [:]

    var runningCount: Int {
        runStates.values.filter { $0.task != nil && !($0.task?.isCancelled ?? true) }.count
    }

    /// Returns the name of a currently-running bot on the given contract/account, or nil.
    /// Used by UI to disable start buttons and show hints.
    func runningBotName(on contractId: String, accountId: Int, excluding botId: UUID) -> String? {
        for (key, state) in runStates where key.botId != botId && key.accountId == accountId {
            guard let task = state.task, !task.isCancelled else { continue }
            if let info = runningBotInfo[key], info.contractId == contractId {
                return info.name
            }
        }
        return nil
    }

    /// Lightweight info kept per running instance so we can query contract without holding BotConfig.
    private struct RunningBotInfo {
        let contractId: String
        let name: String
    }
    private var runningBotInfo: [BotRunKey: RunningBotInfo] = [:]

    /// Cached tick size/value per contractId for unrealized P&L calculation.
    struct TickInfo { let tickSize: Double; let tickValue: Double }
    private var contractTickInfo: [String: TickInfo] = [:]

    /// Injected by DashboardView before any restore/start calls.
    var modelContext: ModelContext?

    private init() {}

    // MARK: - Lifecycle

    func start(bot: BotConfig, accountId: Int) {
        let key = BotRunKey(botId: bot.id, accountId: accountId)

        guard bot.isActive else {
            logToState(key: key, type: .error, message: "Cannot start: bot is inactive")
            return
        }

        guard !bot.indicators.isEmpty else {
            logToState(key: key, type: .error, message: "Cannot start: no indicators configured")
            return
        }

        // Prevent multiple bots on the same contract/account
        if let conflictName = runningBotName(on: bot.contractId, accountId: accountId, excluding: bot.id) {
            logToState(key: key, type: .error,
                       message: "Cannot start: \"\(conflictName)\" is already running on \(bot.contractName)")
            return
        }

        // Stop this specific instance if already running
        stopInstance(key: key, bot: bot)

        // Clear persisted log — this is a fresh start, not a restore
        clearPersistedLog(for: key)

        bot.updatedAt = Date()

        // Persist running state for cold-start restore
        persistRunRecord(key: key)

        // Track contract info for conflict detection
        runningBotInfo[key] = RunningBotInfo(contractId: bot.contractId, name: bot.name)

        // Fetch tick info for unrealized P&L (if not already cached)
        if contractTickInfo[bot.contractId] == nil {
            Task {
                if let contract = await service.contractById(bot.contractId) {
                    contractTickInfo[bot.contractId] = TickInfo(
                        tickSize: contract.tickSize, tickValue: contract.tickValue)
                }
            }
        }

        // Subscribe to live quotes for this contract via SignalR Market Hub
        Task { @MainActor in
            realtime.connectMarketHub(contractId: bot.contractId)
        }

        var state = BotRunState()
        log(key: key, type: .info, message: "Bot started on account \(accountId)", state: &state)

        state.task = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop(bot: bot, accountId: accountId)
        }

        runStates[key] = state
    }

    func stop(bot: BotConfig, accountId: Int) {
        let key = BotRunKey(botId: bot.id, accountId: accountId)
        stopInstance(key: key, bot: bot)
    }

    /// Stops all instances of a bot across all accounts.
    func stopAllInstances(of bot: BotConfig) {
        let keys = runStates.keys.filter { $0.botId == bot.id }
        for key in keys {
            stopInstance(key: key, bot: bot)
        }
    }

    private func stopInstance(key: BotRunKey, bot: BotConfig) {
        if let existing = runStates[key] {
            // Flush session P&L into lifetime before clearing
            bot.lifetimePnL += existing.sessionPnL
            bot.lifetimeTradeCount += existing.sessionTradeCount

            existing.task?.cancel()
            var updated = existing
            updated.task = nil
            log(key: key, type: .info, message: "Bot stopped", state: &updated)
            runStates[key] = updated
        }

        runningBotInfo.removeValue(forKey: key)
        removeRunRecord(key: key)
        bot.updatedAt = Date()

        // Unsubscribe Market Hub if no other running bot uses this contract
        let contractStillInUse = runningBotInfo.values.contains { $0.contractId == bot.contractId }
        if !contractStillInUse {
            Task { @MainActor in
                realtime.disconnectMarketContract(contractId: bot.contractId)
            }
        }
    }

    func stopAll() {
        for (key, state) in runStates {
            state.task?.cancel()
            var updated = state
            updated.task = nil
            log(key: key, type: .info, message: "Bot stopped (stop all)", state: &updated)
            runStates[key] = updated
        }
        runningBotInfo.removeAll()
        removeAllRunRecords()
    }

    /// Stops all bot instances running on a specific account.
    func stopAll(accountId: Int) {
        for (key, state) in runStates where key.accountId == accountId {
            guard let task = state.task, !task.isCancelled else { continue }
            task.cancel()
            var updated = state
            updated.task = nil
            log(key: key, type: .info, message: "Bot stopped (stop all on account)", state: &updated)
            runStates[key] = updated
            runningBotInfo.removeValue(forKey: key)
            removeRunRecord(key: key)
        }
    }

    /// Returns the number of running instances on a specific account.
    func runningCount(accountId: Int) -> Int {
        runStates.filter { key, state in
            key.accountId == accountId && state.task != nil && !(state.task?.isCancelled ?? true)
        }.count
    }

    /// Nuclear stop: halts all bots, cancels every open order,
    /// and closes every open position concurrently.
    func nuclearStop() async {
        // 1. Stop all bots immediately
        stopAll()

        // Snapshot live state before async work
        let openOrders    = realtime.liveOrders.filter { $0.status == 1 }
        let openPositions = realtime.livePositions

        // 2. Cancel open orders + close positions concurrently
        await withTaskGroup(of: Void.self) { group in
            for order in openOrders {
                group.addTask {
                    _ = await self.service.cancelOrder(
                        accountId: order.accountId,
                        orderId:   order.id
                    )
                }
            }
            for position in openPositions {
                group.addTask {
                    _ = await self.service.closePosition(
                        accountId:  position.accountId,
                        contractId: position.contractId
                    )
                }
            }
        }
    }

    /// Nuclear stop scoped to a single account.
    func nuclearStop(accountId: Int) async {
        stopAll(accountId: accountId)

        let openOrders = realtime.liveOrders.filter { $0.status == 1 && $0.accountId == accountId }
        let openPositions = realtime.livePositions.filter { $0.accountId == accountId }

        await withTaskGroup(of: Void.self) { group in
            for order in openOrders {
                group.addTask {
                    _ = await self.service.cancelOrder(
                        accountId: order.accountId,
                        orderId:   order.id
                    )
                }
            }
            for position in openPositions {
                group.addTask {
                    _ = await self.service.closePosition(
                        accountId:  position.accountId,
                        contractId: position.contractId
                    )
                }
            }
        }
    }

    /// Is this bot running on a specific account?
    func isRunning(_ bot: BotConfig, accountId: Int) -> Bool {
        let key = BotRunKey(botId: bot.id, accountId: accountId)
        guard let state = runStates[key], let task = state.task else { return false }
        return !task.isCancelled
    }

    /// Is this bot running on ANY account?
    func isRunningAnywhere(_ bot: BotConfig) -> Bool {
        runStates.keys.contains { key in
            key.botId == bot.id && isRunning(bot, accountId: key.accountId)
        }
    }

    /// Returns the account IDs where this bot is currently running.
    func runningAccountIds(for bot: BotConfig) -> [Int] {
        runStates.keys.filter { key in
            key.botId == bot.id && {
                guard let state = runStates[key], let task = state.task else { return false }
                return !task.isCancelled
            }()
        }.map(\.accountId)
    }

    /// Get run state for a specific (bot, account) pair.
    func runState(for bot: BotConfig, accountId: Int) -> BotRunState? {
        runStates[BotRunKey(botId: bot.id, accountId: accountId)]
    }

    /// Clears the in-memory log and deletes all persisted records for a bot instance.
    func clearLog(for botId: UUID, accountId: Int) {
        let key = BotRunKey(botId: botId, accountId: accountId)
        if var state = runStates[key] {
            state.log = []
            runStates[key] = state
        }
        clearPersistedLog(for: key)
    }

    /// Called once on app launch to restart any bot instances that were
    /// running before a cold start/kill.
    func restoreRunningBots(_ bots: [BotConfig]) {
        guard UserDefaults.standard.bool(forKey: "pref_autoRestoreBots") else { return }
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<BotRunRecord>()
        guard let records = try? ctx.fetch(descriptor) else { return }

        let botMap = Dictionary(uniqueKeysWithValues: bots.map { ($0.id, $0) })

        for record in records {
            guard let bot = botMap[record.botId] else {
                // Bot no longer exists — clean up record
                ctx.delete(record)
                continue
            }
            restoreInstance(bot: bot, accountId: record.accountId)
        }
        try? ctx.save()
    }

    /// Resumes a bot instance after a cold start without clearing its activity log.
    private func restoreInstance(bot: BotConfig, accountId: Int) {
        guard bot.isActive, !bot.indicators.isEmpty else { return }

        let key = BotRunKey(botId: bot.id, accountId: accountId)

        // Cancel any orphaned task just in case
        runStates[key]?.task?.cancel()

        runningBotInfo[key] = RunningBotInfo(contractId: bot.contractId, name: bot.name)

        // Fetch tick info for unrealized P&L (if not already cached)
        if contractTickInfo[bot.contractId] == nil {
            Task {
                if let contract = await service.contractById(bot.contractId) {
                    contractTickInfo[bot.contractId] = TickInfo(
                        tickSize: contract.tickSize, tickValue: contract.tickValue)
                }
            }
        }

        // Reload the persisted log so history survives cold starts
        var state = BotRunState()
        state.log = loadPersistedLog(for: key)

        // Restore session P&L from the run record
        if let ctx = modelContext {
            let botId = key.botId
            let acctId = key.accountId
            let descriptor = FetchDescriptor<BotRunRecord>(
                predicate: #Predicate { $0.botId == botId && $0.accountId == acctId }
            )
            if let record = try? ctx.fetch(descriptor).first {
                state.sessionPnL = record.sessionPnL
                state.sessionTradeCount = record.sessionTradeCount
            }
        }

        log(key: key, type: .info, message: "Bot resumed after app restart", state: &state)

        state.task = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop(bot: bot, accountId: accountId)
        }

        runStates[key] = state
    }

    // MARK: - Polling Loop

    private func pollLoop(bot: BotConfig, accountId: Int) async {
        while !Task.isCancelled {
            await pollOnce(bot: bot, accountId: accountId)
            let interval = pollingInterval(for: bot)
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private func pollOnce(bot: BotConfig, accountId: Int) async {
        let key = BotRunKey(botId: bot.id, accountId: accountId)

        // Prefer SignalR live data; fall back to REST only when User Hub is disconnected.
        let userConnected = await MainActor.run { realtime.isUserConnected }
        if !userConnected {
            async let freshPositions = service.searchOpenPositions(accountId: accountId)
            async let freshOrders    = service.searchOpenOrders(accountId: accountId)
            async let freshTrades    = service.searchTrades(
                accountId: accountId, startTimestamp: RealtimeService.sessionStart())

            let (positions, orders, trades) = await (freshPositions, freshOrders, freshTrades)
            realtime.updateFromREST(positions: positions, orders: orders, trades: trades)
            logToState(key: key, type: .info, message: "Data source: REST fallback (SignalR disconnected)")
        }

        // Fetch bars — use a shorter window to ensure we get the most recent bars.
        // For indicators we need enough history, but the last bar must be current.
        let bars = await service.retrieveBarsForBot(bot, daysBack: 7, limit: 500)

        guard !bars.isEmpty else {
            logToState(key: key, type: .error, message: "Failed to fetch bars (0 returned)")
            return
        }

        // Update state
        updateState(key: key) { state in
            state.lastBarTime = bars.last?.t
            state.lastPollTime = Date()
        }

        logToState(key: key, type: .info, message: "Fetched \(bars.count) bars")

        // Evaluate indicators
        let signal = IndicatorEngine.evaluateAll(bars: bars, configs: bot.indicators)

        updateState(key: key) { state in
            state.lastSignal = signal
        }

        // Get current price: prefer SignalR live quote, fall back to 1-second bars
        let signalrPrice = await MainActor.run { realtime.contractQuotes[bot.contractId]?.lastPrice }
        let lastPrice: Double
        if let sqp = signalrPrice, sqp > 0 {
            lastPrice = sqp
            logToState(key: key, type: .info, message: "Price source: SignalR (\(String(format: "%.2f", sqp)))")
        } else {
            let now = Date()
            let priceBars = await service.retrieveBars(
                contractId: bot.contractId,
                live: false,
                startTime: now.addingTimeInterval(-10),
                endTime: now,
                unit: .second,
                unitNumber: 1,
                limit: 10,
                includePartialBar: true
            )
            let fallback = priceBars.last?.c ?? bars.last?.c ?? 0
            lastPrice = fallback
            logToState(key: key, type: .info, message: "Price source: REST fallback (\(String(format: "%.2f", fallback)))")
        }
        updateSessionPnL(key: key, bot: bot, lastPrice: lastPrice)

        switch signal {
        case .buy:
            logToState(key: key, type: .signal, message: "Signal: BUY")
            if bot.tradeDirection == .shortOnly {
                logToState(key: key, type: .info, message: "Skipped: bot set to Shorts Only")
                return
            }
        case .sell:
            logToState(key: key, type: .signal, message: "Signal: SELL")
            if bot.tradeDirection == .longOnly {
                logToState(key: key, type: .info, message: "Skipped: bot set to Longs Only")
                return
            }
        case .neutral:
            logToState(key: key, type: .signal, message: "Signal: Neutral")
            return
        }

        // Handle non-neutral signal
        await handleSignal(signal, bot: bot, accountId: accountId)
    }

    // MARK: - Signal → Order

    private func handleSignal(_ signal: Signal, bot: BotConfig, accountId: Int) async {
        let key = BotRunKey(botId: bot.id, accountId: accountId)
        let side: OrderSide = signal == .buy ? .bid : .ask

        // Wait for initial position/order data before placing any orders
        if !realtime.initialDataLoaded {
            logToState(key: key, type: .info,
                       message: "Waiting for position data to load, skipping \(signal == .buy ? "buy" : "sell") signal")
            return
        }

        // Check for existing position
        let existingPosition = realtime.livePositions.first {
            $0.accountId == accountId && $0.contractId == bot.contractId
        }

        if let position = existingPosition {
            let posDir = position.isLong ? "long" : "short"
            let sigDir = signal == .buy ? "buy" : "sell"
            logToState(key: key, type: .info,
                       message: "Position exists (\(posDir)), skipping \(sigDir) entry")
            return
        }

        // Build bracket orders
        // Longs:  stop loss negative (price drops), take profit positive (price rises)
        // Shorts: stop loss positive (price rises), take profit negative (price drops)
        let isLong = signal == .buy
        let stopLoss = bot.stopLossTicks.map {
            BracketOrder(ticks: isLong ? -abs($0) : abs($0), type: OrderType.stop.rawValue)
        }
        let takeProfit = bot.takeProfitTicks.map {
            BracketOrder(ticks: isLong ? abs($0) : -abs($0), type: OrderType.limit.rawValue)
        }

        // Place order
        let tag = "bot-\(bot.id.uuidString.prefix(8))-\(UUID().uuidString.prefix(8))"
        let orderId = await service.placeOrder(
            accountId: accountId,
            contractId: bot.contractId,
            type: .market,
            side: side,
            size: bot.quantity,
            customTag: tag,
            stopLoss: stopLoss,
            takeProfit: takeProfit
        )

        if let orderId {
            updateState(key: key) { state in
                state.placedOrderIds.insert(orderId)
                state.customTags.insert(tag)
            }
            logToState(key: key, type: .order,
                       message: "Placed \(side.label) order #\(orderId) (qty: \(bot.quantity))")
        } else {
            let errorMsg = service.errorMessage ?? "unknown error"
            if errorMsg.hasPrefix("Blocked:") {
                logToState(key: key, type: .error, message: errorMsg)
            } else {
                logToState(key: key, type: .error,
                           message: "Order placement failed: \(errorMsg)")
                logToState(key: key, type: .info,
                           message: "Stopping bot due to order error")
                stopInstance(key: key, bot: bot)
            }
        }
    }

    // MARK: - Session P&L

    private func updateSessionPnL(key: BotRunKey, bot: BotConfig, lastPrice: Double) {
        // Calculate unrealized P&L from open position (even before any trades)
        if let position = realtime.livePositions.first(where: {
            $0.accountId == key.accountId && $0.contractId == bot.contractId
        }) {
            let priceDiff = lastPrice - position.averagePrice
            let direction: Double = position.isLong ? 1 : -1
            // Convert price diff to dollar P&L: (priceDiff / tickSize) * tickValue
            // position.size is NOT multiplied — each contract already represents full notional
            let tickInfo = contractTickInfo[bot.contractId]
            let tickSize = tickInfo?.tickSize ?? 0.25
            let tickValue = tickInfo?.tickValue ?? 12.50
            let ticks = priceDiff / tickSize
            let unrealized = ticks * tickValue * direction
            logToState(key: key, type: .info,
                       message: "Unrealized: posId=\(position.id) \(position.isLong ? "LONG" : "SHORT") last=\(lastPrice) avg=\(position.averagePrice) diff=\(String(format: "%.2f", priceDiff)) ticks=\(String(format: "%.1f", ticks)) tickSize=\(tickSize) tickVal=\(tickValue) size=\(position.size) dir=\(direction) pnl=\(String(format: "%.2f", unrealized))")
            updateState(key: key) { state in
                state.unrealizedPnL = unrealized
            }
        } else {
            updateState(key: key) { state in
                state.unrealizedPnL = 0
            }
        }

        guard var state = runStates[key], !state.placedOrderIds.isEmpty else { return }
        let botContractId = runningBotInfo[key]?.contractId ?? ""

        // Capture bracket child order IDs by matching customTag or by
        // finding stop/limit orders on the same contract whose orderId is
        // adjacent to a known parent order (bracket children typically have
        // IDs close to the parent).
        for order in realtime.liveOrders {
            guard order.accountId == key.accountId,
                  order.contractId == botContractId,
                  !state.placedOrderIds.contains(order.id) else { continue }

            // Match by customTag (if API propagates to bracket children)
            if let tag = order.customTag, state.customTags.contains(tag) {
                state.placedOrderIds.insert(order.id)
                runStates[key]?.placedOrderIds.insert(order.id)
                continue
            }

            // Match bracket children: stop or limit orders with IDs within
            // a small range of any known parent order ID (brackets are
            // created immediately after the parent, so IDs are sequential)
            if order.type == OrderType.stop.rawValue ||
               order.type == OrderType.limit.rawValue {
                let isNearParent = state.placedOrderIds.contains {
                    abs(order.id - $0) <= 5
                }
                if isNearParent {
                    state.placedOrderIds.insert(order.id)
                    runStates[key]?.placedOrderIds.insert(order.id)
                }
            }
        }

        let orderIds = state.placedOrderIds
        let matched = realtime.liveTrades.filter {
            orderIds.contains($0.orderId) && !$0.voided && $0.profitAndLoss != nil
        }
        // Fire SL/TP notifications for newly matched trades
        let botName = runningBotInfo[key]?.name ?? "Bot"
        let contractId = runningBotInfo[key]?.contractId ?? ""
        for trade in matched {
            guard let tradePnL = trade.profitAndLoss else { continue }
            if tradePnL < 0 {
                NotificationService.shared.notifyStopLossHit(
                    tradeId: trade.id, botName: botName, pnl: tradePnL, contractId: contractId)
            } else if tradePnL > 0 {
                NotificationService.shared.notifyTakeProfitHit(
                    tradeId: trade.id, botName: botName, pnl: tradePnL, contractId: contractId)
            }
        }

        let pnl = matched.compactMap { $0.profitAndLoss }.reduce(0, +)
        let count = matched.count
        updateState(key: key) { state in
            state.sessionPnL = pnl
            state.sessionTradeCount = count
        }
        flushSessionPnL(key: key, pnl: pnl, tradeCount: count)
    }

    /// Persists session P&L to the run record so it survives force closes.
    private func flushSessionPnL(key: BotRunKey, pnl: Double, tradeCount: Int) {
        guard let ctx = modelContext else { return }
        let botId = key.botId
        let accountId = key.accountId
        let descriptor = FetchDescriptor<BotRunRecord>(
            predicate: #Predicate { $0.botId == botId && $0.accountId == accountId }
        )
        guard let record = try? ctx.fetch(descriptor).first else { return }
        record.sessionPnL = pnl
        record.sessionTradeCount = tradeCount
        try? ctx.save()
    }

    // MARK: - Polling Interval

    private func pollingInterval(for bot: BotConfig) -> Double {
        let secondsPerUnit: [Int: Double] = [
            1: 1,        // second
            2: 60,       // minute
            3: 3600,     // hour
            4: 86400,    // day
            5: 604800,   // week
            6: 2592000   // month
        ]

        let unitSeconds = secondsPerUnit[bot.barUnit] ?? 60
        let barDuration = unitSeconds * Double(bot.barUnitNumber)
        return min(300, max(15, barDuration / 5))
    }

    // MARK: - Logging Helpers

    private func log(key: BotRunKey, type: BotLogType, message: String, state: inout BotRunState) {
        let entry = BotLogEntry(timestamp: Date(), botId: key.botId, accountId: key.accountId, type: type, message: message)
        state.log.insert(entry, at: 0)
        if state.log.count > 200 {
            state.log = Array(state.log.prefix(200))
        }
        insertLogRecord(entry)
    }

    // MARK: - Log Persistence (SwiftData)

    private func insertLogRecord(_ entry: BotLogEntry) {
        guard let ctx = modelContext else { return }
        ctx.insert(BotLogEntryRecord(entry: entry))
        trimLogRecords(botId: entry.botId, accountId: entry.accountId, in: ctx)
        try? ctx.save()
    }

    /// Keeps only the 200 most-recent records for a given bot instance.
    private func trimLogRecords(botId: UUID, accountId: Int, in ctx: ModelContext) {
        let descriptor = FetchDescriptor<BotLogEntryRecord>(
            predicate: #Predicate { $0.botId == botId && $0.accountId == accountId },
            sortBy:    [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? ctx.fetch(descriptor), all.count > 200 else { return }
        Array(all.dropFirst(200)).forEach { ctx.delete($0) }
    }

    /// Returns logs for a bot: in-memory if running, persisted (SwiftData) otherwise.
    func logsForBot(botId: UUID) -> [BotLogEntry] {
        // Gather in-memory logs from all running instances of this bot
        var logs: [BotLogEntry] = []
        for (key, state) in runStates where key.botId == botId {
            logs.append(contentsOf: state.log)
        }
        // If no in-memory logs, fall back to persisted logs across all accounts
        if logs.isEmpty {
            guard let ctx = modelContext else { return [] }
            let descriptor = FetchDescriptor<BotLogEntryRecord>(
                predicate: #Predicate { $0.botId == botId },
                sortBy:    [SortDescriptor(\.timestamp, order: .reverse)]
            )
            logs = ((try? ctx.fetch(descriptor)) ?? []).map { $0.asLogEntry() }
        }
        return logs.sorted { $0.timestamp > $1.timestamp }
    }

    private func loadPersistedLog(for key: BotRunKey) -> [BotLogEntry] {
        guard let ctx = modelContext else { return [] }
        let botId = key.botId
        let accountId = key.accountId
        let descriptor = FetchDescriptor<BotLogEntryRecord>(
            predicate: #Predicate { $0.botId == botId && $0.accountId == accountId },
            sortBy:    [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return ((try? ctx.fetch(descriptor)) ?? []).map { $0.asLogEntry() }
    }

    private func clearPersistedLog(for key: BotRunKey) {
        guard let ctx = modelContext else { return }
        let botId = key.botId
        let accountId = key.accountId
        let descriptor = FetchDescriptor<BotLogEntryRecord>(
            predicate: #Predicate { $0.botId == botId && $0.accountId == accountId }
        )
        ((try? ctx.fetch(descriptor)) ?? []).forEach { ctx.delete($0) }
        try? ctx.save()
    }

    private func logToState(key: BotRunKey, type: BotLogType, message: String) {
        var state = runStates[key] ?? BotRunState()
        log(key: key, type: type, message: message, state: &state)
        runStates[key] = state

        if type == .error {
            let botName = runningBotInfo[key]?.name ?? "Bot"
            NotificationService.shared.notifyBotError(botName: botName, message: message)
        }
    }

    private func updateState(key: BotRunKey, update: (inout BotRunState) -> Void) {
        var state = runStates[key] ?? BotRunState()
        update(&state)
        runStates[key] = state
    }

    // MARK: - Run Record Persistence (cold-start restore)

    private func persistRunRecord(key: BotRunKey) {
        guard let ctx = modelContext else { return }
        // Avoid duplicates
        let botId = key.botId
        let accountId = key.accountId
        let descriptor = FetchDescriptor<BotRunRecord>(
            predicate: #Predicate { $0.botId == botId && $0.accountId == accountId }
        )
        if (try? ctx.fetchCount(descriptor)) ?? 0 > 0 { return }
        ctx.insert(BotRunRecord(botId: key.botId, accountId: key.accountId))
        try? ctx.save()
    }

    private func removeRunRecord(key: BotRunKey) {
        guard let ctx = modelContext else { return }
        let botId = key.botId
        let accountId = key.accountId
        let descriptor = FetchDescriptor<BotRunRecord>(
            predicate: #Predicate { $0.botId == botId && $0.accountId == accountId }
        )
        ((try? ctx.fetch(descriptor)) ?? []).forEach { ctx.delete($0) }
        try? ctx.save()
    }

    private func removeAllRunRecords() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<BotRunRecord>()
        ((try? ctx.fetch(descriptor)) ?? []).forEach { ctx.delete($0) }
        try? ctx.save()
    }
}
