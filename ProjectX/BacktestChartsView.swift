import SwiftUI
import Charts

// ─────────────────────────────────────────────
// Backtest Charts View
//
// Full-screen sheet with 9 charts derived from
// BacktestResult data. Opened from the Equity
// Curve section in BotDetailView.
// ─────────────────────────────────────────────

struct BacktestChartsView: View {
    let result: BacktestResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    equityCurveChart
                    tradePnLChart
                    drawdownChart
                    directionChart
                    exitReasonChart
                    durationChart
                    timeOfDayChart
                    rollingWinRateChart
                    streakChart
                }
                .padding()
            }
            .navigationTitle("Backtest Charts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - 1. Equity Curve

    private var equityCurveChart: some View {
        chartCard(
            "Equity Curve",
            subtitle: "Cumulative P&L over all trades",
            detail: "This is the single most important chart in your backtest. It tells the story of your strategy's performance over time — every peak is a new high-water mark, every valley is a drawdown you'd need to stomach in live trading.\n\n\u{1F7E2} Green zone = equity above zero (net profitable)\n\u{1F534} Red zone = equity below zero (net losing)\n\nWhat to look for:\n\u{2022} Smooth upward slope = consistent edge\n\u{2022} Staircase pattern = wins come in bursts\n\u{2022} Steady climb then cliff = strategy may have stopped working\n\u{2022} Flat line = strategy isn't generating meaningful P&L\n\nPro tip: If the curve ends positive but spent most of its time underwater, the strategy may not be reliable enough for live capital."
        ) {
            Chart {
                // Zero reference line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                LineMark(x: .value("Trade", 0), y: .value("P&L", 0))
                    .foregroundStyle(.green)
                ForEach(Array(result.equityCurve.enumerated()), id: \.offset) { index, value in
                    AreaMark(
                        x: .value("Trade", index + 1),
                        y: .value("P&L", value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [value >= 0 ? .green.opacity(0.25) : .red.opacity(0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Trade", index + 1),
                        y: .value("P&L", value)
                    )
                    .foregroundStyle(value >= 0 ? .green : .red)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
                // Final value point marker
                if let last = result.equityCurve.last {
                    PointMark(
                        x: .value("Trade", result.equityCurve.count),
                        y: .value("P&L", last)
                    )
                    .foregroundStyle(last >= 0 ? .green : .red)
                    .symbolSize(40)
                    .annotation(position: .top, spacing: 4) {
                        Text(last, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(last >= 0 ? .green : .red)
                    }
                }
            }
            .chartYAxis { currencyAxis }
            .chartXAxisLabel("Trade #")
            .frame(height: 220)
        }
    }

    // MARK: - 2. Trade P&L

    private var tradePnLChart: some View {
        chartCard(
            "Trade P&L",
            subtitle: "Individual profit or loss per trade",
            detail: "Every bar is one trade. This chart reveals the texture of your strategy — not just whether it wins, but how it wins and loses.\n\n\u{1F7E2} Green bars = winning trades\n\u{1F534} Red bars = losing trades\n\nWhat to look for:\n\u{2022} Green bars taller than red = good risk/reward ratio\n\u{2022} Red bars consistently taller = losses outsize wins (dangerous even with high win rate)\n\u{2022} One massive green bar = beware of a single outlier inflating results\n\u{2022} Uniform bar heights = tight SL/TP brackets are capping outcomes\n\nPro tip: Compare this with your Profit Factor. If it's below 1.5, your wins aren't big enough relative to your losses to survive real-world slippage and commissions."
        ) {
            let bestIdx = result.trades.enumerated().max(by: { $0.element.pnlDollars < $1.element.pnlDollars })
            let worstIdx = result.trades.enumerated().min(by: { $0.element.pnlDollars < $1.element.pnlDollars })
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                ForEach(Array(result.trades.enumerated()), id: \.offset) { index, trade in
                    BarMark(
                        x: .value("Trade", index + 1),
                        y: .value("P&L", trade.pnlDollars)
                    )
                    .foregroundStyle(trade.pnlDollars >= 0 ? .green.opacity(0.8) : .red.opacity(0.8))
                    .cornerRadius(2)
                }
                // Best trade marker
                if let best = bestIdx, best.element.pnlDollars > 0 {
                    PointMark(
                        x: .value("Trade", best.offset + 1),
                        y: .value("P&L", best.element.pnlDollars)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(30)
                    .annotation(position: .top, spacing: 2) {
                        Text("Best")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                    }
                }
                // Worst trade marker
                if let worst = worstIdx, worst.element.pnlDollars < 0 {
                    PointMark(
                        x: .value("Trade", worst.offset + 1),
                        y: .value("P&L", worst.element.pnlDollars)
                    )
                    .foregroundStyle(.red)
                    .symbolSize(30)
                    .annotation(position: .bottom, spacing: 2) {
                        Text("Worst")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .chartYAxis { currencyAxis }
            .chartXAxisLabel("Trade #")
            .frame(height: 220)
        }
    }

    // MARK: - 3. Drawdown

    private var drawdownChart: some View {
        chartCard(
            "Drawdown",
            subtitle: "Peak-to-trough decline in equity",
            detail: "Drawdown is the pain chart — it shows how much you'd lose from your best point before recovering. This is what keeps traders up at night.\n\nHow to read it:\n\u{2022} The deeper the red, the worse the drawdown\n\u{2022} Wide valleys = long recovery periods\n\u{2022} Narrow spikes = quick recoveries\n\nBenchmarks:\n\u{2022} < 10% of total P&L = excellent risk control\n\u{2022} 10-25% = acceptable for most strategies\n\u{2022} 25-50% = aggressive, may be hard to hold through\n\u{2022} > 50% = serious risk, reconsider position sizing\n\nPro tip: Multiply your max drawdown by 2x — that's a realistic worst case in live trading. Can your account survive it? If not, reduce quantity or widen stops."
        ) {
            let drawdownData = buildDrawdownData()
            let maxDD = drawdownData.min() ?? 0
            let maxDDIndex = drawdownData.firstIndex(of: maxDD) ?? 0
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                ForEach(Array(drawdownData.enumerated()), id: \.offset) { index, value in
                    AreaMark(
                        x: .value("Trade", index + 1),
                        y: .value("Drawdown", value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.red.opacity(0.35), .red.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Trade", index + 1),
                        y: .value("Drawdown", value)
                    )
                    .foregroundStyle(.red.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                // Max drawdown marker
                if maxDD < 0 {
                    PointMark(
                        x: .value("Trade", maxDDIndex + 1),
                        y: .value("Drawdown", maxDD)
                    )
                    .foregroundStyle(.red)
                    .symbolSize(50)
                    .annotation(position: .bottom, spacing: 4) {
                        Text(maxDD, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .chartYAxis { currencyAxis }
            .chartXAxisLabel("Trade #")
            .frame(height: 220)
        }
    }

    private func buildDrawdownData() -> [Double] {
        var peak = 0.0
        return result.equityCurve.map { value in
            peak = max(peak, value)
            return -(peak - value)
        }
    }

    // MARK: - 4. Cumulative P&L by Direction

    private var directionChart: some View {
        chartCard(
            "P&L by Direction",
            subtitle: "Long vs short cumulative performance",
            detail: "This chart splits your strategy into two: one that only takes longs, and one that only takes shorts. It answers a critical question — is your strategy actually good in both directions, or is one side carrying the other?\n\n\u{1F7E2} Green line = cumulative long P&L\n\u{1F534} Red line = cumulative short P&L\n\nScenarios:\n\u{2022} Both rising = strategy works both ways (ideal)\n\u{2022} Green up, red down = long-only strategy in disguise. Set Trade Direction to Long Only\n\u{2022} Red up, green down = short-only edge. Set Trade Direction to Short Only\n\u{2022} Both flat = no real edge in either direction\n\nPro tip: In trending markets, one direction usually dominates. If you see a divergence, check if the losing side would improve with a different indicator setup rather than disabling it entirely."
        ) {
            directionChartContent
        }
    }

    @ViewBuilder
    private var directionChartContent: some View {
        let curves = buildDirectionCurves()
        let longData = Array(curves.long.enumerated())
        let shortData = Array(curves.short.enumerated())
        let lastLong = curves.long.last ?? 0
        let lastShort = curves.short.last ?? 0

        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Long: \(lastLong, format: .currency(code: "USD").precision(.fractionLength(0)))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Short: \(lastShort, format: .currency(code: "USD").precision(.fractionLength(0)))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
            directionLineChart(longData: longData, shortData: shortData)
        }
    }

    private func directionLineChart(longData: [(offset: Int, element: Double)], shortData: [(offset: Int, element: Double)]) -> some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(dash: [4, 4]))
            ForEach(longData, id: \.offset) { index, value in
                LineMark(x: .value("Trade", index + 1), y: .value("P&L", value), series: .value("Direction", "Long"))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(shortData, id: \.offset) { index, value in
                LineMark(x: .value("Trade", index + 1), y: .value("P&L", value), series: .value("Direction", "Short"))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxis { currencyAxis }
        .chartXAxisLabel("Trade #")
        .chartForegroundStyleScale(["Long": .green, "Short": .red])
        .frame(height: 200)
    }

    private func buildDirectionCurves() -> (long: [Double], short: [Double]) {
        var longCum = 0.0
        var shortCum = 0.0
        var longCurve: [Double] = []
        var shortCurve: [Double] = []
        for trade in result.trades {
            if trade.direction == .long {
                longCum += trade.pnlDollars
            } else {
                shortCum += trade.pnlDollars
            }
            longCurve.append(longCum)
            shortCurve.append(shortCum)
        }
        return (longCurve, shortCurve)
    }

    // MARK: - 5. Exit Reason Breakdown

    private var exitReasonChart: some View {
        chartCard(
            "Exit Reasons",
            subtitle: "How trades were closed",
            detail: "How your trades end tells you a lot about your SL/TP calibration.\n\n\u{1F7E2} Take Profit = strategy reached its target\n\u{1F534} Stop Loss = strategy hit its safety exit\n\u{1F7E0} End of Data = trade was still open when the backtest ended\n\nHealthy ratios:\n\u{2022} ~40-60% Take Profit = SL/TP are well balanced\n\u{2022} > 70% Stop Loss = stops are likely too tight, or the entry signal is poor. Try widening SL or using the ATR tool\n\u{2022} > 70% Take Profit = you might be leaving money on the table with a TP that's too tight\n\u{2022} Many End of Data = trades are lasting too long, consider if your exits are triggering at all\n\nPro tip: The ideal ratio depends on your risk/reward. A strategy with 40% TP rate can still be very profitable if each TP is 2-3x larger than each SL."
        ) {
            let reasons = buildExitReasonData()
            let total = reasons.reduce(0) { $0 + $1.count }
            Chart(reasons, id: \.reason) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.55),
                    outerRadius: .ratio(0.95),
                    angularInset: 3
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Reason", item.reason))
                .annotation(position: .overlay) {
                    VStack(spacing: 1) {
                        Text("\(item.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                        if total > 0 {
                            Text("\(Int(round(Double(item.count) / Double(total) * 100)))%")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
            }
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text("\(total)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("trades")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartForegroundStyleScale([
                "Stop Loss": .red,
                "Take Profit": .green,
                "End of Data": .orange
            ])
            .frame(height: 220)
        }
    }

    private struct ExitReasonCount {
        let reason: String
        let count: Int
    }

    private func buildExitReasonData() -> [ExitReasonCount] {
        var counts: [String: Int] = [:]
        for trade in result.trades {
            counts[trade.exitReason.rawValue, default: 0] += 1
        }
        return counts.map { ExitReasonCount(reason: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - 6. Trade Duration Distribution

    private var durationChart: some View {
        chartCard(
            "Trade Duration",
            subtitle: "How long trades lasted in bars",
            detail: "How long your bot holds each trade reveals its trading personality.\n\nPatterns:\n\u{2022} Clustered at 2-3 bars = fast scalping strategy, SL/TP brackets are tight relative to volatility\n\u{2022} Spread across many bars = strategy holds through noise, waiting for bigger moves\n\u{2022} Bimodal (two clusters) = some trades hit quick exits, others ride longer — could indicate two different market conditions\n\nWhat to do with this:\n\u{2022} If most trades are 1-2 bars, your SL/TP may be too tight — the ATR tool can help calibrate\n\u{2022} If trades last dozens of bars, you're exposed to overnight/weekend risk in live trading\n\u{2022} Compare winners vs losers — if losers last longer, the strategy holds losers hoping for recovery (bad habit)\n\nPro tip: Multiply the average bar count by your bar size to get real-world hold time. 10 bars on 5-min = 50 minutes of market exposure per trade."
        ) {
            let buckets = buildDurationBuckets()
            let maxBucket = buckets.max(by: { $0.count < $1.count })
            Chart(buckets, id: \.label) { bucket in
                BarMark(
                    x: .value("Bars", bucket.label),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(
                    bucket.label == maxBucket?.label
                        ? .blue
                        : .blue.opacity(0.5)
                )
                .cornerRadius(3)
                .annotation(position: .top, spacing: 2) {
                    if bucket.count > 0 {
                        Text("\(bucket.count)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxisLabel("Duration (bars)")
            .frame(height: 220)
        }
    }

    private struct DurationBucket {
        let label: String
        let count: Int
    }

    private func buildDurationBuckets() -> [DurationBucket] {
        var counts: [Int: Int] = [:]
        for trade in result.trades {
            counts[trade.barCount, default: 0] += 1
        }
        return counts.keys.sorted().map { DurationBucket(label: "\($0)", count: counts[$0]!) }
    }

    // MARK: - 7. P&L by Time of Day

    private var timeOfDayChart: some View {
        chartCard(
            "P&L by Time of Day",
            subtitle: "Which hours are most profitable",
            detail: "Markets have personality throughout the day — the open is chaotic, midday is quiet, the close gets volatile again. This chart shows which hours your strategy thrives in and which ones it should avoid.\n\n\u{1F7E2} Green bars = profitable hours\n\u{1F534} Red bars = losing hours\n\nCommon patterns:\n\u{2022} Strong at the open (9-10 AM) = strategy capitalizes on opening volatility\n\u{2022} Weak at midday (12-1 PM) = low volume chop is killing entries\n\u{2022} Strong at close (3-4 PM) = strategy benefits from end-of-day momentum\n\nWhat to do:\n\u{2022} If 1-2 hours account for all your losses, consider scheduling your bot to avoid those hours entirely\n\u{2022} If profits concentrate in one hour, the edge might be time-specific — test if it holds across different date ranges\n\nPro tip: Times are in your local timezone. If trading global markets, consider what's happening at that hour in the contract's native exchange timezone."
        ) {
            let hourData = buildTimeOfDayData()
            let bestHour = hourData.max(by: { $0.pnl < $1.pnl })
            let worstHour = hourData.min(by: { $0.pnl < $1.pnl })
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                ForEach(hourData, id: \.hour) { item in
                    BarMark(
                        x: .value("Hour", item.label),
                        y: .value("P&L", item.pnl)
                    )
                    .foregroundStyle(item.pnl >= 0 ? .green.opacity(0.8) : .red.opacity(0.8))
                    .cornerRadius(3)
                    .annotation(position: item.pnl >= 0 ? .top : .bottom, spacing: 2) {
                        if item.hour == bestHour?.hour || item.hour == worstHour?.hour {
                            Text(item.pnl, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(item.pnl >= 0 ? .green : .red)
                        }
                    }
                }
            }
            .chartYAxis { currencyAxis }
            .chartXAxisLabel("Hour (local)")
            .frame(height: 220)
        }
    }

    private struct HourPnL {
        let hour: Int
        let label: String
        let pnl: Double
    }

    private func buildTimeOfDayData() -> [HourPnL] {
        var hourPnL: [Int: Double] = [:]
        let calendar = Calendar.current
        for trade in result.trades {
            if let date = BacktestEngine.parseTimestamp(trade.entryTimestamp) {
                let hour = calendar.component(.hour, from: date)
                hourPnL[hour, default: 0] += trade.pnlDollars
            }
        }
        return hourPnL.keys.sorted().map { hour in
            let formatter = DateFormatter()
            formatter.dateFormat = "ha"
            let components = DateComponents(hour: hour)
            let label = calendar.date(from: components).map { formatter.string(from: $0) } ?? "\(hour)"
            return HourPnL(hour: hour, label: label, pnl: hourPnL[hour]!)
        }
    }

    // MARK: - 8. Rolling Win Rate

    private var rollingWinRateChart: some View {
        chartCard(
            "Rolling Win Rate",
            subtitle: "20-trade sliding window win percentage",
            detail: "Your overall win rate is just one number — this chart shows how it evolves over time. A strategy with 55% win rate overall might have spent half the backtest at 30% before a hot streak pulled it up.\n\n\u{2022} Dashed line = 50% (breakeven win rate)\n\u{1F7E2} Above the line = winning more than losing\n\u{1F534} Below the line = losing more than winning\n\nWhat to watch for:\n\u{2022} Stable above 50% = consistent edge, reliable strategy\n\u{2022} Trending downward = strategy may be curve-fit to early data and degrading\n\u{2022} Wild swings = unstable edge, may not survive live trading\n\u{2022} Dips then recovers = normal variance, but check if dips correlate with specific market conditions\n\nPro tip: A strategy with 40% win rate can still be very profitable if the average win is 2x+ the average loss. Don't chase high win rates — chase high expectancy (win rate x avg win - loss rate x avg loss)."
        ) {
            let data = buildRollingWinRate(window: 20)
            Chart {
                // 50% reference line
                RuleMark(y: .value("50%", 50))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(dash: [6, 4]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("50%")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                // Win rate area fill
                ForEach(Array(data.enumerated()), id: \.offset) { index, rate in
                    AreaMark(
                        x: .value("Trade", index + 1),
                        y: .value("Win %", rate)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [rate >= 50 ? .green.opacity(0.15) : .red.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Trade", index + 1),
                        y: .value("Win %", rate)
                    )
                    .foregroundStyle(rate >= 50 ? .green : .red)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
                // Final value marker
                if let last = data.last {
                    PointMark(
                        x: .value("Trade", data.count),
                        y: .value("Win %", last)
                    )
                    .foregroundStyle(last >= 50 ? .green : .red)
                    .symbolSize(40)
                    .annotation(position: .top, spacing: 4) {
                        Text("\(Int(round(last)))%")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(last >= 50 ? .green : .red)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%")
                        }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxisLabel("Trade #")
            .frame(height: 220)
        }
    }

    private func buildRollingWinRate(window: Int) -> [Double] {
        guard result.trades.count >= window else {
            // If fewer trades than window, compute cumulative rate
            var wins = 0
            return result.trades.enumerated().map { index, trade in
                if trade.pnlDollars > 0 { wins += 1 }
                return Double(wins) / Double(index + 1) * 100
            }
        }
        var rates: [Double] = []
        for i in (window - 1)..<result.trades.count {
            let slice = result.trades[(i - window + 1)...i]
            let wins = slice.filter { $0.pnlDollars > 0 }.count
            rates.append(Double(wins) / Double(window) * 100)
        }
        return rates
    }

    // MARK: - 9. Win/Loss Streaks

    private var streakChart: some View {
        chartCard(
            "Win/Loss Streaks",
            subtitle: "Consecutive win and loss runs",
            detail: "This is the psychological stress test. Even profitable strategies have losing streaks — the question is whether you can survive them financially and mentally.\n\n\u{1F7E2} Green bars (up) = consecutive wins, height = streak length\n\u{1F534} Red bars (down) = consecutive losses, depth = streak length\n\nReality check:\n\u{2022} 3-4 loss streak = normal for any strategy\n\u{2022} 5-7 loss streak = uncomfortable but expected over 100+ trades\n\u{2022} 8+ loss streak = rare, but if it appears in a backtest it WILL happen live\n\nThe math that matters:\nIf your worst losing streak is 6 and each loss is $100, you need to survive a $600 drawdown minimum. In live trading, assume 1.5-2x worse than your backtest shows.\n\nPro tip: Count the total number of streaks vs their lengths. Many short streaks (2-3) with occasional long ones is healthier than a few very long streaks. The latter suggests the strategy has regime-dependent performance."
        ) {
            let streaks = buildStreakData()
            let longestWin = streaks.filter(\.isWin).max(by: { $0.length < $1.length })
            let longestLoss = streaks.filter { !$0.isWin }.max(by: { $0.length < $1.length })
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                ForEach(streaks, id: \.index) { item in
                    BarMark(
                        x: .value("Streak", item.index),
                        y: .value("Length", item.isWin ? item.length : -item.length)
                    )
                    .foregroundStyle(item.isWin ? .green.opacity(0.8) : .red.opacity(0.8))
                    .cornerRadius(3)
                    .annotation(position: item.isWin ? .top : .bottom, spacing: 2) {
                        if item.index == longestWin?.index || item.index == longestLoss?.index {
                            Text("\(item.length)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(item.isWin ? .green : .red)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(abs(v))")
                        }
                    }
                }
            }
            .chartXAxisLabel("Streak #")
            .frame(height: 220)
        }
    }

    private struct StreakItem {
        let index: Int
        let length: Int
        let isWin: Bool
    }

    private func buildStreakData() -> [StreakItem] {
        guard !result.trades.isEmpty else { return [] }
        var streaks: [StreakItem] = []
        var currentWin = result.trades[0].pnlDollars > 0
        var currentLength = 1
        var streakIndex = 0

        for i in 1..<result.trades.count {
            let isWin = result.trades[i].pnlDollars > 0
            if isWin == currentWin {
                currentLength += 1
            } else {
                streaks.append(StreakItem(index: streakIndex, length: currentLength, isWin: currentWin))
                streakIndex += 1
                currentWin = isWin
                currentLength = 1
            }
        }
        streaks.append(StreakItem(index: streakIndex, length: currentLength, isWin: currentWin))
        return streaks
    }

    // MARK: - Shared Helpers

    private func chartCard<Content: View>(
        _ title: String,
        subtitle: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ChartCardView(title: title, subtitle: subtitle, detail: detail, content: content)
    }

    // ── State‑owning wrapper so each card can expand its own detail ──
    private struct ChartCardView<Content: View>: View {
        let title: String
        let subtitle: String
        let detail: String
        @ViewBuilder let content: Content
        @State private var showDetail = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    HStack(alignment: .top, spacing: 4) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: showDetail ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) { showDetail.toggle() }
                    }

                    if showDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 4)

                content
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @AxisContentBuilder
    private var currencyAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(v, format: .currency(code: "USD").precision(.fractionLength(0)))
                }
            }
        }
    }
}
