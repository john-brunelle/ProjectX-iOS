import Foundation

// ─────────────────────────────────────────────
// Backtest Engine — Historical Simulation
//
// Pure logic, Foundation-only. Mirrors the live
// BotRunner flow: evaluate indicators on a
// growing bar window, enter on signal if flat,
// exit via stop-loss / take-profit brackets
// checked against bar highs and lows.
//
// Reuses IndicatorEngine.evaluateAll() for
// signal generation — same logic as live trading.
// ─────────────────────────────────────────────

// MARK: - Data Types

enum TradeDirection: String, Equatable {
    case long
    case short
}

enum ExitReason: String {
    case stopLoss    = "Stop Loss"
    case takeProfit  = "Take Profit"
    case endOfData   = "End of Data"
}

struct BacktestTrade: Identifiable {
    let id = UUID()
    let direction: TradeDirection
    let entryBarIndex: Int
    let entryPrice: Double
    let entryTimestamp: String
    let exitBarIndex: Int
    let exitPrice: Double
    let exitTimestamp: String
    let exitReason: ExitReason
    let pnlTicks: Double
    let pnlDollars: Double
    var barCount: Int { exitBarIndex - entryBarIndex }
}

struct BacktestStatistics {
    let totalTrades: Int
    let winningTrades: Int
    let losingTrades: Int
    let winRate: Double
    let totalPnL: Double
    let averageWin: Double
    let averageLoss: Double
    let maxDrawdown: Double
    let sharpeRatio: Double
    let profitFactor: Double
    let largestWin: Double
    let largestLoss: Double

    // Long / Short breakdown
    let longTrades: Int
    let longWinRate: Double
    let shortTrades: Int
    let shortWinRate: Double

    // Duration
    let averageTradeDuration: TimeInterval
}

struct BacktestResult {
    let trades: [BacktestTrade]
    let statistics: BacktestStatistics
    let equityCurve: [Double]
}

struct BacktestParameters {
    let bars: [Bar]
    let indicatorConfigs: [IndicatorConfig]
    let quantity: Int
    let stopLossTicks: Int?
    let takeProfitTicks: Int?
    let tickSize: Double
    let tickValue: Double
    let tradeDirection: TradeDirectionFilter
}

// MARK: - Open Position State (internal)

private struct OpenPosition {
    let direction: TradeDirection
    let entryPrice: Double
    let entryBarIndex: Int
    let entryTimestamp: String
    let stopPrice: Double?
    let takeProfitPrice: Double?
}

// MARK: - Backtest Engine

struct BacktestEngine {

    /// Run a full backtest simulation. Pure function — all inputs in, result out.
    static func run(parameters: BacktestParameters) -> BacktestResult {
        let bars = parameters.bars
        let configs = parameters.indicatorConfigs

        // Validate inputs
        guard bars.count >= 2, !configs.isEmpty else {
            return BacktestResult(
                trades: [],
                statistics: emptyStatistics(),
                equityCurve: []
            )
        }

        var trades: [BacktestTrade] = []
        var position: OpenPosition? = nil

        for i in 0..<bars.count {
            let bar = bars[i]

            // ── Step 1: Check exits if in position (skip the entry bar) ──
            if let pos = position, i > pos.entryBarIndex {
                if let exitResult = checkExit(position: pos, bar: bar, barIndex: i, parameters: parameters) {
                    trades.append(exitResult)
                    position = nil
                }
            }

            // ── Step 2: Check entries if flat ────────
            if position == nil {
                let window = Array(bars.prefix(through: i))
                let signal = IndicatorEngine.evaluateAll(bars: window, configs: configs)

                // Apply trade direction filter
                let filteredSignal: Signal = {
                    switch (signal, parameters.tradeDirection) {
                    case (.buy, .shortOnly): return .neutral
                    case (.sell, .longOnly): return .neutral
                    default: return signal
                    }
                }()

                switch filteredSignal {
                case .buy:
                    let entryPrice = bar.c
                    let sl = parameters.stopLossTicks.map { entryPrice - Double($0) * parameters.tickSize }
                    let tp = parameters.takeProfitTicks.map { entryPrice + Double($0) * parameters.tickSize }
                    position = OpenPosition(
                        direction: .long,
                        entryPrice: entryPrice,
                        entryBarIndex: i,
                        entryTimestamp: bar.t,
                        stopPrice: sl,
                        takeProfitPrice: tp
                    )

                case .sell:
                    let entryPrice = bar.c
                    let sl = parameters.stopLossTicks.map { entryPrice + Double($0) * parameters.tickSize }
                    let tp = parameters.takeProfitTicks.map { entryPrice - Double($0) * parameters.tickSize }
                    position = OpenPosition(
                        direction: .short,
                        entryPrice: entryPrice,
                        entryBarIndex: i,
                        entryTimestamp: bar.t,
                        stopPrice: sl,
                        takeProfitPrice: tp
                    )

                case .neutral:
                    break
                }
            }
        }

        // ── Step 3: Force close at end of data ──────
        if let pos = position, let lastBar = bars.last {
            let trade = closeTrade(
                position: pos,
                exitPrice: lastBar.c,
                exitBarIndex: bars.count - 1,
                exitTimestamp: lastBar.t,
                exitReason: .endOfData,
                parameters: parameters
            )
            trades.append(trade)
        }

        // ── Step 4: Calculate results ───────────────
        let equityCurve = buildEquityCurve(trades: trades)
        let statistics = calculateStatistics(trades: trades, equityCurve: equityCurve)

        return BacktestResult(
            trades: trades,
            statistics: statistics,
            equityCurve: equityCurve
        )
    }

    // MARK: - Exit Check

    /// Check if a position should be closed on this bar. Stop loss has priority.
    private static func checkExit(
        position: OpenPosition,
        bar: Bar,
        barIndex: Int,
        parameters: BacktestParameters
    ) -> BacktestTrade? {

        switch position.direction {
        case .long:
            // Stop loss: bar low breaches stop price
            if let sl = position.stopPrice, bar.l <= sl {
                return closeTrade(
                    position: position, exitPrice: sl,
                    exitBarIndex: barIndex, exitTimestamp: bar.t,
                    exitReason: .stopLoss, parameters: parameters
                )
            }
            // Take profit: bar high reaches TP price
            if let tp = position.takeProfitPrice, bar.h >= tp {
                return closeTrade(
                    position: position, exitPrice: tp,
                    exitBarIndex: barIndex, exitTimestamp: bar.t,
                    exitReason: .takeProfit, parameters: parameters
                )
            }

        case .short:
            // Stop loss: bar high breaches stop price
            if let sl = position.stopPrice, bar.h >= sl {
                return closeTrade(
                    position: position, exitPrice: sl,
                    exitBarIndex: barIndex, exitTimestamp: bar.t,
                    exitReason: .stopLoss, parameters: parameters
                )
            }
            // Take profit: bar low reaches TP price
            if let tp = position.takeProfitPrice, bar.l <= tp {
                return closeTrade(
                    position: position, exitPrice: tp,
                    exitBarIndex: barIndex, exitTimestamp: bar.t,
                    exitReason: .takeProfit, parameters: parameters
                )
            }
        }

        return nil
    }

    // MARK: - Trade Builder

    private static func closeTrade(
        position: OpenPosition,
        exitPrice: Double,
        exitBarIndex: Int,
        exitTimestamp: String,
        exitReason: ExitReason,
        parameters: BacktestParameters
    ) -> BacktestTrade {
        let pnlTicks: Double
        switch position.direction {
        case .long:
            pnlTicks = (exitPrice - position.entryPrice) / parameters.tickSize
        case .short:
            pnlTicks = (position.entryPrice - exitPrice) / parameters.tickSize
        }

        let pnlDollars = pnlTicks * parameters.tickValue * Double(parameters.quantity)

        return BacktestTrade(
            direction: position.direction,
            entryBarIndex: position.entryBarIndex,
            entryPrice: position.entryPrice,
            entryTimestamp: position.entryTimestamp,
            exitBarIndex: exitBarIndex,
            exitPrice: exitPrice,
            exitTimestamp: exitTimestamp,
            exitReason: exitReason,
            pnlTicks: pnlTicks,
            pnlDollars: pnlDollars
        )
    }

    // MARK: - Statistics

    private static func buildEquityCurve(trades: [BacktestTrade]) -> [Double] {
        var curve: [Double] = []
        var cumulative = 0.0
        for trade in trades {
            cumulative += trade.pnlDollars
            curve.append(cumulative)
        }
        return curve
    }

    private static func calculateStatistics(
        trades: [BacktestTrade],
        equityCurve: [Double]
    ) -> BacktestStatistics {
        guard !trades.isEmpty else { return emptyStatistics() }

        let pnls = trades.map(\.pnlDollars)
        let winners = pnls.filter { $0 > 0 }
        let losers = pnls.filter { $0 < 0 }

        let totalPnL = pnls.reduce(0, +)
        let grossProfit = winners.reduce(0, +)
        let grossLoss = abs(losers.reduce(0, +))

        // Long / Short breakdown
        let longs = trades.filter { $0.direction == .long }
        let shorts = trades.filter { $0.direction == .short }
        let longWins = longs.filter { $0.pnlDollars > 0 }.count
        let shortWins = shorts.filter { $0.pnlDollars > 0 }.count

        // Average trade duration
        let durations: [TimeInterval] = trades.compactMap { trade in
            guard let entry = parseTimestamp(trade.entryTimestamp),
                  let exit = parseTimestamp(trade.exitTimestamp) else { return nil }
            return exit.timeIntervalSince(entry)
        }
        let avgDuration = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)

        return BacktestStatistics(
            totalTrades: trades.count,
            winningTrades: winners.count,
            losingTrades: losers.count,
            winRate: Double(winners.count) / Double(trades.count),
            totalPnL: totalPnL,
            averageWin: winners.isEmpty ? 0 : grossProfit / Double(winners.count),
            averageLoss: losers.isEmpty ? 0 : grossLoss / Double(losers.count),
            maxDrawdown: maxDrawdown(equityCurve: equityCurve),
            sharpeRatio: sharpeRatio(pnls: pnls),
            profitFactor: grossLoss == 0 ? (grossProfit > 0 ? .infinity : 0) : grossProfit / grossLoss,
            largestWin: winners.max() ?? 0,
            largestLoss: losers.isEmpty ? 0 : abs(losers.min()!),
            longTrades: longs.count,
            longWinRate: longs.isEmpty ? 0 : Double(longWins) / Double(longs.count),
            shortTrades: shorts.count,
            shortWinRate: shorts.isEmpty ? 0 : Double(shortWins) / Double(shorts.count),
            averageTradeDuration: avgDuration
        )
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFrac.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func maxDrawdown(equityCurve: [Double]) -> Double {
        guard !equityCurve.isEmpty else { return 0 }
        var peak = 0.0
        var maxDD = 0.0
        for equity in equityCurve {
            peak = max(peak, equity)
            let drawdown = peak - equity
            maxDD = max(maxDD, drawdown)
        }
        return maxDD
    }

    private static func sharpeRatio(pnls: [Double]) -> Double {
        guard pnls.count >= 2 else { return 0 }
        let mean = pnls.reduce(0, +) / Double(pnls.count)
        let variance = pnls.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(pnls.count - 1)
        let stdDev = sqrt(variance)
        guard stdDev > 0 else { return 0 }
        return mean / stdDev
    }

    private static func emptyStatistics() -> BacktestStatistics {
        BacktestStatistics(
            totalTrades: 0, winningTrades: 0, losingTrades: 0,
            winRate: 0, totalPnL: 0, averageWin: 0, averageLoss: 0,
            maxDrawdown: 0, sharpeRatio: 0, profitFactor: 0,
            largestWin: 0, largestLoss: 0,
            longTrades: 0, longWinRate: 0,
            shortTrades: 0, shortWinRate: 0,
            averageTradeDuration: 0
        )
    }
}
