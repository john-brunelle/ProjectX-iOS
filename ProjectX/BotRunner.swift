import Foundation

// ─────────────────────────────────────────────
// Bot Runner — Live Trading Engine
//
// Manages running bots: polls bars, evaluates
// indicators, places orders when signals fire.
//
// Polling-based: SignalR does not stream bars,
// so we fetch via REST at calculated intervals.
// ─────────────────────────────────────────────

// MARK: - Log Types

enum BotLogType: String {
    case signal
    case order
    case error
    case info
}

struct BotLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let botId: UUID
    let type: BotLogType
    let message: String
}

// MARK: - Per-Bot Runtime State

struct BotRunState {
    var task: Task<Void, Never>?
    var lastSignal: Signal = .neutral
    var lastBarTime: String?
    var lastPollTime: Date?
    var log: [BotLogEntry] = []
}

// MARK: - Bot Runner

@MainActor
@Observable
class BotRunner {
    static let shared = BotRunner()

    private let service = ProjectXService.shared
    private let realtime = RealtimeService.shared

    private(set) var runStates: [UUID: BotRunState] = [:]

    var runningCount: Int {
        runStates.values.filter { $0.task != nil && !($0.task?.isCancelled ?? true) }.count
    }

    private init() {}

    // MARK: - Lifecycle

    func start(bot: BotConfig) {
        guard !bot.indicators.isEmpty else {
            logToState(botId: bot.id, type: .error, message: "Cannot start: no indicators configured")
            return
        }

        // Initialize or reset run state
        stop(bot: bot)

        bot.status = .running
        bot.updatedAt = Date()

        var state = BotRunState()
        log(botId: bot.id, type: .info, message: "Bot started", state: &state)

        let botId = bot.id
        state.task = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop(bot: bot)
            // If loop exits naturally (cancellation), ensure cleanup
            await MainActor.run {
                if bot.status == .running {
                    bot.status = .stopped
                    bot.updatedAt = Date()
                }
            }
        }

        runStates[botId] = state
    }

    func stop(bot: BotConfig) {
        let botId = bot.id
        if let existing = runStates[botId] {
            existing.task?.cancel()
            var updated = existing
            updated.task = nil
            log(botId: botId, type: .info, message: "Bot stopped", state: &updated)
            runStates[botId] = updated
        }

        if bot.status == .running {
            bot.status = .stopped
            bot.updatedAt = Date()
        }
    }

    func stopAll() {
        for (botId, state) in runStates {
            state.task?.cancel()
            var updated = state
            updated.task = nil
            log(botId: botId, type: .info, message: "Bot stopped (stop all)", state: &updated)
            runStates[botId] = updated
        }
    }

    func isRunning(_ bot: BotConfig) -> Bool {
        bot.status == .running
    }

    // MARK: - Polling Loop

    private func pollLoop(bot: BotConfig) async {
        while !Task.isCancelled {
            await pollOnce(bot: bot)
            let interval = pollingInterval(for: bot)
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private func pollOnce(bot: BotConfig) async {
        let botId = bot.id

        // Fetch bars
        let bars = await service.retrieveBarsForBot(bot, daysBack: 7, limit: 500)

        guard !bars.isEmpty else {
            logToState(botId: botId, type: .error, message: "Failed to fetch bars (0 returned)")
            return
        }

        // Update state
        updateState(botId: botId) { state in
            state.lastBarTime = bars.last?.t
            state.lastPollTime = Date()
        }

        logToState(botId: botId, type: .info, message: "Fetched \(bars.count) bars")

        // Evaluate indicators
        let signal = IndicatorEngine.evaluateAll(bars: bars, configs: bot.indicators)

        updateState(botId: botId) { state in
            state.lastSignal = signal
        }

        switch signal {
        case .buy:
            logToState(botId: botId, type: .signal, message: "Signal: BUY")
            if bot.tradeDirection == .shortOnly {
                logToState(botId: botId, type: .info, message: "Skipped: bot set to Shorts Only")
                return
            }
        case .sell:
            logToState(botId: botId, type: .signal, message: "Signal: SELL")
            if bot.tradeDirection == .longOnly {
                logToState(botId: botId, type: .info, message: "Skipped: bot set to Longs Only")
                return
            }
        case .neutral:
            logToState(botId: botId, type: .signal, message: "Signal: Neutral")
            return
        }

        // Handle non-neutral signal
        await handleSignal(signal, bot: bot)
    }

    // MARK: - Signal → Order

    private func handleSignal(_ signal: Signal, bot: BotConfig) async {
        let botId = bot.id
        let side: OrderSide = signal == .buy ? .bid : .ask

        // Check for existing position
        let existingPosition = realtime.livePositions.first {
            $0.accountId == bot.accountId && $0.contractId == bot.contractId
        }

        if let position = existingPosition {
            let posDir = position.isLong ? "long" : "short"
            let sigDir = signal == .buy ? "buy" : "sell"
            logToState(botId: botId, type: .info,
                       message: "Position exists (\(posDir)), skipping \(sigDir) entry")
            return
        }

        // Build bracket orders
        let stopLoss = bot.stopLossTicks.map {
            BracketOrder(ticks: $0, type: OrderType.stop.rawValue)
        }
        let takeProfit = bot.takeProfitTicks.map {
            BracketOrder(ticks: $0, type: OrderType.limit.rawValue)
        }

        // Place order
        let orderId = await service.placeOrder(
            accountId: bot.accountId,
            contractId: bot.contractId,
            type: .market,
            side: side,
            size: bot.quantity,
            customTag: "bot-\(botId.uuidString.prefix(8))",
            stopLoss: stopLoss,
            takeProfit: takeProfit
        )

        if let orderId {
            logToState(botId: botId, type: .order,
                       message: "Placed \(side.label) order #\(orderId) (qty: \(bot.quantity))")
        } else {
            logToState(botId: botId, type: .error,
                       message: "Order placement failed: \(service.errorMessage ?? "unknown error")")
            bot.status = .error
            bot.updatedAt = Date()
        }
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

    private func log(botId: UUID, type: BotLogType, message: String, state: inout BotRunState) {
        let entry = BotLogEntry(timestamp: Date(), botId: botId, type: type, message: message)
        state.log.insert(entry, at: 0)
        if state.log.count > 200 {
            state.log = Array(state.log.prefix(200))
        }
    }

    private func logToState(botId: UUID, type: BotLogType, message: String) {
        var state = runStates[botId] ?? BotRunState()
        log(botId: botId, type: type, message: message, state: &state)
        runStates[botId] = state
    }

    private func updateState(botId: UUID, update: (inout BotRunState) -> Void) {
        var state = runStates[botId] ?? BotRunState()
        update(&state)
        runStates[botId] = state
    }
}
