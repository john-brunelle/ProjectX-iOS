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
    var todayPnL: Double = 0            // realized P&L from closed trades
    var unrealizedPnL: Double = 0         // unrealized P&L from open position
    var todayTradeCount: Int = 0

    // Claude AI — only call when a new bar closes
    var lastClaudeBarTime: String?

    // Operating hours — track last state for transition logging
    var wasWithinOperatingHours: Bool = true
    var lastClaudeSignal: Signal = .neutral
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
    private(set) var contractTickInfo: [String: TickInfo] = [:]

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

        // Check for existing position on this contract — adopt if ours, reject if foreign
        if let existingPos = realtime.livePositions.first(where: {
            $0.accountId == accountId && $0.contractId == bot.contractId
        }) {
            let botPrefix = bot.tagPrefix
            let hasBotOrders = realtime.liveOrders.contains {
                $0.accountId == accountId && $0.contractId == bot.contractId
                && ($0.customTag?.hasPrefix(botPrefix) == true)
            }
            if !hasBotOrders {
                let dir = existingPos.isLong ? "long" : "short"
                logToState(key: key, type: .error,
                           message: "Cannot start: existing \(dir) position on \(bot.contractName) was not opened by this bot. Close the position first.")
                return
            }
            // Position is ours — bot will adopt it and track P&L
            logToState(key: key, type: .info,
                       message: "Adopting existing \(existingPos.isLong ? "long" : "short") position on \(bot.contractName)")
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
        state.wasWithinOperatingHours = isWithinOperatingHours(bot: bot)
        log(key: key, type: .info, message: "Bot started on account \(accountId)", state: &state)
        log(key: key, type: .info, message: "Operating hours: \(bot.operatingHoursLabel)", state: &state)

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
            existing.task?.cancel()
            var updated = existing
            updated.task = nil
            log(key: key, type: .info, message: "Bot stopped", state: &updated)
            runStates[key] = updated
        }

        // Close positions and/or cancel orders, then flush P&L to lifetime
        let closePositions = UserDefaults.standard.bool(forKey: "pref_closePositionsOnStop")
        let cancelOrders = UserDefaults.standard.bool(forKey: "pref_cancelOrdersOnStop")
        if closePositions || cancelOrders {
            let accountId = key.accountId
            let contractId = bot.contractId
            Task {
                if closePositions {
                    let closed = await service.closePosition(accountId: accountId, contractId: contractId)
                    if closed {
                        logToState(key: key, type: .info, message: "Closed position on \(bot.contractName)")
                    }
                }
                if cancelOrders {
                    let openOrders = await MainActor.run {
                        realtime.liveOrders.filter { $0.accountId == accountId && $0.contractId == contractId && $0.status == 1 }
                    }
                    for order in openOrders {
                        _ = await service.cancelOrder(accountId: accountId, orderId: order.id)
                    }
                    if !openOrders.isEmpty {
                        logToState(key: key, type: .info, message: "Cancelled \(openOrders.count) order(s) on \(bot.contractName)")
                    }
                }
                // Wait briefly for the close trade to arrive via SignalR
                try? await Task.sleep(for: .seconds(2))
                // Now flush today's P&L (including the close trade) to lifetime
                self.flushPnLToLifetime(key: key, bot: bot)
            }
        } else {
            // No close-on-stop — flush immediately
            flushPnLToLifetime(key: key, bot: bot)
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

    /// Resets session P&L and trade count to zero for a running bot instance.
    func resetTodayPnL(for bot: BotConfig, accountId: Int) {
        let key = BotRunKey(botId: bot.id, accountId: accountId)
        guard runStates[key] != nil else { return }
        runStates[key]?.todayPnL = 0
        runStates[key]?.unrealizedPnL = 0
        runStates[key]?.todayTradeCount = 0
        runStates[key]?.placedOrderIds.removeAll()
        runStates[key]?.customTags.removeAll()
        flushTodayPnL(key: key, pnl: 0, tradeCount: 0)
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

        // Subscribe to live quotes for this contract via SignalR Market Hub
        Task { @MainActor in
            realtime.connectMarketHub(contractId: bot.contractId)
        }

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
                state.todayPnL = record.todayPnL
                state.todayTradeCount = record.todayTradeCount
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
        if pollingMode(for: bot) == .aiOnly {
            await aiOnlyPollLoop(bot: bot, accountId: accountId)
        } else {
            while !Task.isCancelled {
                await pollOnce(bot: bot, accountId: accountId)
                let interval = pollingInterval(for: bot)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    // MARK: - AI-Only Polling

    private func aiOnlyPollLoop(bot: BotConfig, accountId: Int) async {
        let key = BotRunKey(botId: bot.id, accountId: accountId)
        let barDuration = barDurationSeconds(for: bot)
        let housekeepingInterval: Double = 30
        var lastHousekeepingTime: Date = .distantPast
        var lastInPositionLog: Date = .distantPast

        while !Task.isCancelled {
            let now = Date()

            // 1. Housekeeping (positions, orders, P&L) every 30s
            if now.timeIntervalSince(lastHousekeepingTime) >= housekeepingInterval {
                await housekeepingPass(bot: bot, accountId: accountId)
                lastHousekeepingTime = Date()
            }

            // 2. Skip indicator evaluation if in a position
            let hasPosition = realtime.livePositions.contains {
                $0.accountId == accountId && $0.contractId == bot.contractId
            }
            if hasPosition {
                // Log once per bar duration cycle
                if Date().timeIntervalSince(lastInPositionLog) >= barDuration {
                    logToState(key: key, type: .info, message: "In position — AI Bot paused")
                    lastInPositionLog = Date()
                }
                try? await Task.sleep(for: .seconds(housekeepingInterval))
                continue
            }

            // 3. Lightweight bar-close check (small window, completed only)
            let checkBars = await service.retrieveBars(
                contractId: bot.contractId,
                live: false,
                startTime: Date().addingTimeInterval(-barDuration * 3),
                endTime: Date(),
                unit: bot.barUnitEnum ?? .minute,
                unitNumber: bot.barUnitNumber,
                limit: 10,
                includePartialBar: false
            )

            let currentBarTime = checkBars.last?.t
            let cachedBarTime = runStates[key]?.lastClaudeBarTime

            if currentBarTime != cachedBarTime && currentBarTime != nil {
                // Check operating hours before evaluating
                let key = BotRunKey(botId: bot.id, accountId: accountId)
                guard await checkOperatingHours(bot: bot, key: key) else {
                    try? await Task.sleep(for: .seconds(min(30, barDuration / 2)))
                    continue
                }
                // New bar closed — fetch precise data and evaluate
                await aiEvaluationPass(bot: bot, accountId: accountId)
                // Sleep for the full bar duration — next bar won't close sooner
                try? await Task.sleep(for: .seconds(barDuration))
            } else {
                // No new bar yet — check again in 30s or half the bar duration
                try? await Task.sleep(for: .seconds(min(30, barDuration / 2)))
            }
        }
    }

    /// Lightweight pass: refresh positions/orders/trades and update P&L.
    /// No bar fetches, no indicator evaluation.
    private func housekeepingPass(bot: BotConfig, accountId: Int) async {
        let key = BotRunKey(botId: bot.id, accountId: accountId)

        async let freshPositions = service.searchOpenPositions(accountId: accountId)
        async let freshOrders    = service.searchOpenOrders(accountId: accountId)
        async let freshTrades    = service.searchTrades(
            accountId: accountId, startTimestamp: RealtimeService.sessionStart())

        let (positions, orders, trades) = await (freshPositions, freshOrders, freshTrades)
        realtime.updateFromREST(positions: positions, orders: orders, trades: trades)

        // Get price for P&L tracking
        let signalrPrice = await MainActor.run { realtime.contractQuotes[bot.contractId]?.lastPrice }
        let lastPrice: Double
        if let sqp = signalrPrice, sqp > 0 {
            lastPrice = sqp
        } else {
            let now = Date()
            let priceBars = await service.retrieveBars(
                contractId: bot.contractId, live: false,
                startTime: now.addingTimeInterval(-10), endTime: now,
                unit: .second, unitNumber: 1, limit: 10, includePartialBar: true
            )
            lastPrice = priceBars.last?.c ?? 0
        }

        updateState(key: key) { state in
            state.lastPollTime = Date()
        }
        updateTodayPnL(key: key, bot: bot, lastPrice: lastPrice)
    }

    /// Fetch only the bars Claude needs, call the API, and act on the signal.
    private func aiEvaluationPass(bot: BotConfig, accountId: Int) async {
        let key = BotRunKey(botId: bot.id, accountId: accountId)

        guard let claudeConfig = bot.indicators.first(where: { $0.indicatorType == .claudeAI }),
              case .claudeAI(let model, let barCount, let customPrompt) = claudeConfig.parameters
        else { return }

        // Fetch only the bars Claude needs — completed bars only, 7-day window
        // to ensure enough trading sessions even with market gaps
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let bars = await service.retrieveBars(
            contractId: bot.contractId,
            live: false,
            startTime: start,
            endTime: Date(),
            unit: bot.barUnitEnum ?? .minute,
            unitNumber: bot.barUnitNumber,
            limit: barCount,
            includePartialBar: false
        )

        guard !bars.isEmpty else {
            logToState(key: key, type: .error, message: "Failed to fetch bars for AI evaluation")
            return
        }

        // Call Claude
        let tick = contractTickInfo[bot.contractId]
        let result = await ClaudeAIService.shared.evaluate(
            bars: bars,
            contractName: bot.contractName,
            contractId: bot.contractId,
            barSize: bot.barSizeLabel,
            model: model,
            barCount: barCount,
            tickSize: tick?.tickSize,
            tickValue: tick?.tickValue,
            customPrompt: customPrompt
        )

        let signal = result.signal
        updateState(key: key) { state in
            state.lastClaudeBarTime = bars.last?.t
            state.lastClaudeSignal = signal
            state.lastBarTime = bars.last?.t
            state.lastPollTime = Date()
            state.lastSignal = signal
        }

        // Log market data first, then Claude result
        let signalrPrice = await MainActor.run { realtime.contractQuotes[bot.contractId]?.lastPrice }
        let lastPrice = (signalrPrice != nil && signalrPrice! > 0) ? signalrPrice! : (bars.last?.c ?? 0)
        let priceSource = (signalrPrice != nil && signalrPrice! > 0) ? "SR" : "REST"
        let signalLabel = signal == .buy ? "BUY" : signal == .sell ? "SELL" : "NEUTRAL"
        logToState(key: key, type: .signal,
                   message: "\(signalLabel) | \(bars.count) bars | \(priceSource) \(String(format: "%.2f", lastPrice))")

        let confPct = String(format: "%.0f%%", result.confidence * 100)
        logToState(key: key, type: .signal,
                   message: "Claude: \(signalLabel) (\(confPct)) — \(result.reason)")

        updateTodayPnL(key: key, bot: bot, lastPrice: lastPrice)

        // Direction filter
        switch signal {
        case .buy:
            if bot.tradeDirection == .shortOnly {
                logToState(key: key, type: .info, message: "Skipped: bot set to Shorts Only")
                return
            }
        case .sell:
            if bot.tradeDirection == .longOnly {
                logToState(key: key, type: .info, message: "Skipped: bot set to Longs Only")
                return
            }
        case .neutral:
            return
        }

        await handleSignal(signal, bot: bot, accountId: accountId)
    }

    // MARK: - Traditional Polling

    private func pollOnce(bot: BotConfig, accountId: Int) async {
        let key = BotRunKey(botId: bot.id, accountId: accountId)

        // REST refresh on every poll — keeps P&L and position tracking accurate
        async let freshPositions = service.searchOpenPositions(accountId: accountId)
        async let freshOrders    = service.searchOpenOrders(accountId: accountId)
        async let freshTrades    = service.searchTrades(
            accountId: accountId, startTimestamp: RealtimeService.sessionStart())

        let (positions, orders, trades) = await (freshPositions, freshOrders, freshTrades)
        realtime.updateFromREST(positions: positions, orders: orders, trades: trades)

        // Check if we have an open position on this contract
        let hasPosition = realtime.livePositions.contains {
            $0.accountId == accountId && $0.contractId == bot.contractId
        }

        // Get current price for P&L tracking (needed whether or not we have a position)
        let signalrPrice = await MainActor.run { realtime.contractQuotes[bot.contractId]?.lastPrice }
        let lastPrice: Double
        if let sqp = signalrPrice, sqp > 0 {
            lastPrice = sqp
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
            lastPrice = priceBars.last?.c ?? 0
        }

        // If in a position, just track P&L — skip bars, indicators, and Claude
        if hasPosition {
            updateState(key: key) { state in
                state.lastPollTime = Date()
            }
            updateTodayPnL(key: key, bot: bot, lastPrice: lastPrice)
            return
        }

        // No position — check operating hours before evaluating
        guard await checkOperatingHours(bot: bot, key: key) else { return }

        // Fetch bars
        let bars = await service.retrieveBarsForBot(bot, daysBack: 7, limit: 500)

        guard !bars.isEmpty else {
            logToState(key: key, type: .error, message: "Failed to fetch bars (0 returned)")
            return
        }

        // Split indicators: sync (local) vs async (Claude AI)
        let syncIndicators = bot.indicators.filter { $0.indicatorType != .claudeAI }
        let claudeConfig = bot.indicators.first { $0.indicatorType == .claudeAI }

        // Evaluate local indicators synchronously
        let syncSignal = IndicatorEngine.evaluateAll(bars: bars, configs: syncIndicators)

        // Evaluate Claude AI indicator asynchronously (if configured)
        // Only calls the API when a new bar closes — reuses cached signal otherwise
        let currentBarTime = bars.last?.t
        var claudeSignal: Signal = .neutral
        if let config = claudeConfig,
           case .claudeAI(let model, let barCount, let customPrompt) = config.parameters {
            let cachedBarTime = runStates[key]?.lastClaudeBarTime
            if currentBarTime != cachedBarTime {
                // New bar closed — call Claude
                let tick = contractTickInfo[bot.contractId]
                let result = await ClaudeAIService.shared.evaluate(
                    bars: bars,
                    contractName: bot.contractName,
                    contractId: bot.contractId,
                    barSize: bot.barSizeLabel,
                    model: model,
                    barCount: barCount,
                    tickSize: tick?.tickSize,
                    tickValue: tick?.tickValue,
                    customPrompt: customPrompt
                )
                claudeSignal = result.signal
                updateState(key: key) { state in
                    state.lastClaudeBarTime = currentBarTime
                    state.lastClaudeSignal = result.signal
                }
                let confPct = String(format: "%.0f%%", result.confidence * 100)
                logToState(key: key, type: .signal,
                           message: "Claude: \(result.signal == .buy ? "BUY" : result.signal == .sell ? "SELL" : "NEUTRAL") (\(confPct)) — \(result.reason)")
            } else {
                // Same bar — reuse last Claude signal
                claudeSignal = runStates[key]?.lastClaudeSignal ?? .neutral
            }
        }

        // Merge sync + Claude signals with AND logic
        let signal: Signal
        let nonNeutral = [syncSignal, claudeSignal].filter { $0 != .neutral }
        if nonNeutral.isEmpty {
            signal = .neutral
        } else if nonNeutral.allSatisfy({ $0 == .buy }) {
            signal = .buy
        } else if nonNeutral.allSatisfy({ $0 == .sell }) {
            signal = .sell
        } else {
            signal = .neutral
        }

        // Batch all state updates into a single mutation to minimize SwiftUI re-renders
        updateState(key: key) { state in
            state.lastBarTime = bars.last?.t
            state.lastPollTime = Date()
            state.lastSignal = signal
        }
        updateTodayPnL(key: key, bot: bot, lastPrice: lastPrice)

        // Compact log line
        let signalLabel = signal == .buy ? "BUY" : signal == .sell ? "SELL" : "NEUTRAL"
        let priceSource = signalrPrice != nil && signalrPrice! > 0 ? "SR" : "REST"
        logToState(key: key, type: .signal,
                   message: "\(signalLabel) | \(bars.count) bars | \(priceSource) \(String(format: "%.2f", lastPrice))")

        switch signal {
        case .buy:
            if bot.tradeDirection == .shortOnly {
                logToState(key: key, type: .info, message: "Skipped: bot set to Shorts Only")
                return
            }
        case .sell:
            if bot.tradeDirection == .longOnly {
                logToState(key: key, type: .info, message: "Skipped: bot set to Longs Only")
                return
            }
        case .neutral:
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

    private func updateTodayPnL(key: BotRunKey, bot: BotConfig, lastPrice: Double) {
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
            updateState(key: key) { state in
                state.unrealizedPnL = unrealized
            }
        } else {
            updateState(key: key) { state in
                state.unrealizedPnL = 0
            }
        }

        // Tag-based order ownership: find all orders belonging to this bot
        // (currently visible in liveOrders — includes open + recently filled via SignalR)
        let botPrefix = bot.tagPrefix
        let tagMatchedIds = Set(realtime.liveOrders
            .filter { $0.accountId == key.accountId && ($0.customTag?.hasPrefix(botPrefix) == true) }
            .map(\.id))

        // Merge with accumulated placedOrderIds (catches orders evicted from liveOrders by REST refresh)
        updateState(key: key) { state in
            state.placedOrderIds.formUnion(tagMatchedIds)
        }
        let allBotOrderIds = (runStates[key]?.placedOrderIds ?? []).union(tagMatchedIds)

        // Match trades by all known bot-owned order IDs
        let matched = realtime.liveTrades.filter {
            allBotOrderIds.contains($0.orderId) && !$0.voided && $0.profitAndLoss != nil
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
            state.todayPnL = pnl
            state.todayTradeCount = count
        }
        flushTodayPnL(key: key, pnl: pnl, tradeCount: count)
    }

    /// Persists session P&L to the run record so it survives force closes.
    private func flushTodayPnL(key: BotRunKey, pnl: Double, tradeCount: Int) {
        guard let ctx = modelContext else { return }
        let botId = key.botId
        let accountId = key.accountId
        let descriptor = FetchDescriptor<BotRunRecord>(
            predicate: #Predicate { $0.botId == botId && $0.accountId == accountId }
        )
        guard let record = try? ctx.fetch(descriptor).first else { return }
        record.todayPnL = pnl
        record.todayTradeCount = tradeCount
        try? ctx.save()
    }

    /// Flushes today's realized P&L from the current run state into the bot's lifetime totals.
    private func flushPnLToLifetime(key: BotRunKey, bot: BotConfig) {
        guard let state = runStates[key] else { return }
        bot.lifetimePnL += state.todayPnL
        bot.lifetimeTradeCount += state.todayTradeCount
    }

    // MARK: - Bot Polling Mode

    private enum BotPollingMode {
        case traditional   // no Claude AI indicator, or Claude + sync indicators (hybrid)
        case aiOnly        // Claude AI is the ONLY indicator
    }

    private func pollingMode(for bot: BotConfig) -> BotPollingMode {
        let hasClaude = bot.indicators.contains { $0.indicatorType == .claudeAI }
        let hasSync = bot.indicators.contains { $0.indicatorType != .claudeAI }
        return (hasClaude && !hasSync) ? .aiOnly : .traditional
    }

    // MARK: - Polling Interval

    private static let secondsPerUnit: [Int: Double] = [
        1: 1,        // second
        2: 60,       // minute
        3: 3600,     // hour
        4: 86400,    // day
        5: 604800,   // week
        6: 2592000   // month
    ]

    private func barDurationSeconds(for bot: BotConfig) -> Double {
        let unitSeconds = Self.secondsPerUnit[bot.barUnit] ?? 60
        return unitSeconds * Double(bot.barUnitNumber)
    }

    private func pollingInterval(for bot: BotConfig) -> Double {
        let barDuration = barDurationSeconds(for: bot)
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

    // MARK: - Log Persistence (SwiftData) — batched

    private var pendingLogRecords: [BotLogEntry] = []
    private var logSaveTask: Task<Void, Never>?
    private let logSaveDebounce: TimeInterval = 5.0

    private func insertLogRecord(_ entry: BotLogEntry) {
        pendingLogRecords.append(entry)
        logSaveTask?.cancel()
        logSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.logSaveDebounce ?? 5))
            self?.flushPendingLogs()
        }
    }

    private func flushPendingLogs() {
        guard let ctx = modelContext, !pendingLogRecords.isEmpty else { return }
        let toFlush = pendingLogRecords
        pendingLogRecords.removeAll()
        for entry in toFlush {
            ctx.insert(BotLogEntryRecord(entry: entry))
        }
        // Trim once per flush, not per record
        if let first = toFlush.first {
            trimLogRecords(botId: first.botId, accountId: first.accountId, in: ctx)
        }
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

    // MARK: - Operating Hours

    private func isWithinOperatingHours(bot: BotConfig) -> Bool {
        guard bot.operatingMode != "24/7" else { return true }
        let cal = Calendar.current
        let now = Date()
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let startMin = bot.opStartHour * 60 + bot.opStartMinute
        let endMin = bot.opEndHour * 60 + bot.opEndMinute

        // Check if within operating window (handles overnight wrap)
        let withinHours: Bool
        if endMin <= startMin {
            // Overnight: e.g. 6PM (1080) → 9:30AM (570)
            withinHours = nowMin >= startMin || nowMin < endMin
        } else {
            withinHours = nowMin >= startMin && nowMin < endMin
        }
        guard withinHours else { return false }

        // Check sleep windows
        for window in bot.decodedSleepWindows {
            let sleepStart = window.startHour * 60 + window.startMinute
            let sleepEnd = window.endHour * 60 + window.endMinute
            if sleepEnd > sleepStart {
                if nowMin >= sleepStart && nowMin < sleepEnd { return false }
            } else {
                // Overnight sleep window
                if nowMin >= sleepStart || nowMin < sleepEnd { return false }
            }
        }
        return true
    }

    /// Finds the sleep window the bot is currently in, if any.
    private func currentSleepWindow(bot: BotConfig) -> SleepWindow? {
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        return bot.decodedSleepWindows.first { window in
            let s = window.startHour * 60 + window.startMinute
            let e = window.endHour * 60 + window.endMinute
            if e > s { return nowMin >= s && nowMin < e }
            else { return nowMin >= s || nowMin < e }
        }
    }

    /// Closes position and cancels open orders for a bot on a specific account.
    private func closeBotPosition(bot: BotConfig, accountId: Int, key: BotRunKey, reason: String) async {
        let closed = await service.closePosition(accountId: accountId, contractId: bot.contractId)
        if closed {
            logToState(key: key, type: .order, message: "Closed position on \(bot.contractName) (\(reason))")
        }
        let openOrders = await MainActor.run {
            realtime.liveOrders.filter { $0.accountId == accountId && $0.contractId == bot.contractId && $0.status == 1 }
        }
        for order in openOrders {
            _ = await service.cancelOrder(accountId: accountId, orderId: order.id)
        }
        if !openOrders.isEmpty {
            logToState(key: key, type: .order, message: "Cancelled \(openOrders.count) order(s) on \(bot.contractName) (\(reason))")
        }
    }

    /// Checks operating hours, logs transitions, and closes positions on sleep entry if configured. Returns true if within hours.
    private func checkOperatingHours(bot: BotConfig, key: BotRunKey) async -> Bool {
        let within = isWithinOperatingHours(bot: bot)
        let wasWithin = runStates[key]?.wasWithinOperatingHours ?? true

        if within != wasWithin {
            updateState(key: key) { state in
                state.wasWithinOperatingHours = within
            }
            if within {
                logToState(key: key, type: .info, message: "Entering operating hours — resuming signal evaluation")
            } else {
                // Determine if entering a sleep window or leaving operating hours
                if let sleepWindow = currentSleepWindow(bot: bot) {
                    if sleepWindow.closePosition {
                        logToState(key: key, type: .info, message: "Entering sleep window (\(sleepWindow.label)) — closing position & orders")
                        await closeBotPosition(bot: bot, accountId: key.accountId, key: key, reason: "sleep window")
                    } else {
                        logToState(key: key, type: .info, message: "Entering sleep window (\(sleepWindow.label)) — pausing (position kept open)")
                    }
                } else {
                    logToState(key: key, type: .info, message: "Outside operating hours — pausing signal evaluation")
                }
            }
        }
        return within
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
