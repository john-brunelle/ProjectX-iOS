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
    var botName: String = ""
    var tradeDirection: TradeDirectionFilter = .both
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    equityCurveChart
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
            .navigationTitle(botName.isEmpty ? "Backtest Charts" : "\(botName) — Backtest Charts")
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
            equityCurveChartContent
        }
    }

    private var equityCurveChartContent: some View {
        let data = buildEquityCurveWithZeroCrossings()
        let minVal = data.map(\.value).min() ?? 0
        let maxVal = data.map(\.value).max() ?? 0
        let padding = max(abs(maxVal - minVal) * 0.05, 1)
        let finalValue = data.last?.value ?? 0

        return VStack(alignment: .trailing, spacing: 4) {
            Text(finalValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.caption.weight(.bold))
                .foregroundStyle(finalValue >= 0 ? .green : .red)
            let runs = buildEquityRuns(from: data)
            Chart {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                // Area fills — one continuous series per run
                ForEach(runs.indices, id: \.self) { runIdx in
                    let run = runs[runIdx]
                    ForEach(run.points.indices, id: \.self) { ptIdx in
                        AreaMark(
                            x: .value("Trade", run.points[ptIdx].x),
                            y: .value("P&L", run.points[ptIdx].value),
                            series: .value("run", runIdx)
                        )
                        .foregroundStyle(run.isNegative ? .red.opacity(0.15) : .green.opacity(0.15))
                    }
                }
                // Line segments
                ForEach(0..<max(data.count - 1, 0), id: \.self) { i in
                    let startValue = data[i].value
                    let endValue = data[i + 1].value
                    let isNeg = (startValue < 0 || endValue < 0) && !(startValue == 0 && endValue >= 0)
                    let color: Color = isNeg ? .red : .green
                    LineMark(
                        x: .value("Trade", data[i].x),
                        y: .value("P&L", data[i].value),
                        series: .value("seg", i)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    LineMark(
                        x: .value("Trade", data[i + 1].x),
                        y: .value("P&L", endValue),
                        series: .value("seg", i)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }
            .chartYScale(domain: (minVal - padding)...(maxVal + padding))
            .chartYAxis { currencyAxis }
            .chartXAxisLabel("Trade #")
            .frame(height: 210)
        }
    }

    private struct EquityPoint {
        let x: Double
        let value: Double
    }

    /// Inserts interpolated zero-crossing points so the color break happens exactly at $0.
    private func buildEquityCurveWithZeroCrossings() -> [EquityPoint] {
        let raw = result.equityCurve
        guard !raw.isEmpty else { return [] }
        var points: [EquityPoint] = [EquityPoint(x: 0, value: 0)]
        for i in 0..<raw.count {
            let prev = i == 0 ? 0.0 : raw[i - 1]
            let curr = raw[i]
            let prevX = Double(i)
            let currX = Double(i + 1)
            // Check if zero crossing between prev and curr
            if (prev > 0 && curr < 0) || (prev < 0 && curr > 0) {
                // Linear interpolation to find exact x where value = 0
                let fraction = prev / (prev - curr)
                let zeroX = prevX + fraction * (currX - prevX)
                points.append(EquityPoint(x: zeroX, value: 0))
            }
            points.append(EquityPoint(x: currX, value: curr))
        }
        return points
    }

    private struct EquityRun {
        let points: [EquityPoint]
        let isNegative: Bool
    }

    /// Splits equity points into contiguous runs of positive/negative values for area shading.
    private func buildEquityRuns(from data: [EquityPoint]) -> [EquityRun] {
        guard data.count >= 2 else { return [] }
        var runs: [EquityRun] = []
        var currentPoints: [EquityPoint] = [data[0]]
        var currentNeg = data[0].value < 0

        for i in 1..<data.count {
            let pt = data[i]
            let isNeg = pt.value < 0
            if isNeg == currentNeg || pt.value == 0 {
                currentPoints.append(pt)
            } else {
                // Include the zero-crossing point in both runs for continuity
                currentPoints.append(pt)
                runs.append(EquityRun(points: currentPoints, isNegative: currentNeg))
                currentPoints = [pt]
                currentNeg = isNeg
            }
        }
        if !currentPoints.isEmpty {
            runs.append(EquityRun(points: currentPoints, isNegative: currentNeg))
        }
        return runs
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
            drawdownChartContent
        }
    }

    private var drawdownChartContent: some View {
        let drawdownData = buildDrawdownData()
        let maxDD = drawdownData.min() ?? 0
        let maxDDIndex = drawdownData.firstIndex(of: maxDD) ?? 0
        let tradeCount = drawdownData.count
        let yPadding = max(abs(maxDD) * 0.1, 1)

        return VStack(alignment: .leading, spacing: 4) {
            if maxDD < 0 {
                HStack(spacing: 4) {
                    Text("Max Drawdown:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(maxDD, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
            drawdownLineChart(data: drawdownData, maxDD: maxDD, maxDDIndex: maxDDIndex)
                .chartXScale(domain: 1...max(tradeCount, 1))
                .chartYScale(domain: (maxDD - yPadding)...yPadding)
                .chartYAxis { currencyAxis }
                .chartXAxisLabel("Trade #")
                .frame(height: 200)
        }
    }

    @ViewBuilder
    private func drawdownLineChart(data: [Double], maxDD: Double, maxDDIndex: Int) -> some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(dash: [4, 4]))
            ForEach(Array(data.enumerated()), id: \.offset) { index, value in
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
            if maxDD < 0 {
                PointMark(
                    x: .value("Trade", maxDDIndex + 1),
                    y: .value("Drawdown", maxDD)
                )
                .foregroundStyle(.red)
                .symbolSize(50)
            }
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

    private var showLongLine: Bool { tradeDirection != .shortOnly }
    private var showShortLine: Bool { tradeDirection != .longOnly }

    private var directionChartContent: some View {
        let curves = buildDirectionCurves()
        let longData = showLongLine ? Array(curves.long.enumerated()) : []
        let shortData = showShortLine ? Array(curves.short.enumerated()) : []
        let lastLong = curves.long.last ?? 0
        let lastShort = curves.short.last ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                if showLongLine {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Long: \(lastLong, format: .currency(code: "USD").precision(.fractionLength(0)))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                if showShortLine {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("Short: \(lastShort, format: .currency(code: "USD").precision(.fractionLength(0)))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
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
                "Take Profit": .green,
                "Stop Loss": .red,
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
            detail: "How long your bot holds each trade reveals its trading personality. Each bar shows how many trades lasted a certain number of bars. When there are many distinct durations, values are grouped into ranges for readability.\n\nHow to read it:\n\u{2022} X-axis = number of bars held (or range, e.g. \"10-19\")\n\u{2022} Y-axis = how many trades lasted that long\n\u{2022} The brightest bar is the most common duration\n\u{2022} Count labels above each bar show exact numbers\n\nPatterns:\n\u{2022} One dominant bucket = strategy has a consistent rhythm. If it's the lowest range, exits are triggering quickly — SL/TP may be tight relative to volatility. If it's a higher range, the strategy lets trades breathe\n\u{2022} Spread across many ranges = variable hold times, strategy behavior changes with market conditions\n\u{2022} Two peaks (bimodal) = some trades exit quickly, others ride much longer — could indicate two different market regimes or a mix of SL and TP exits at different speeds\n\nWhat to do with this:\n\u{2022} If the tallest bar is in the lowest range, most trades are exiting quickly — your SL/TP brackets may be too tight relative to volatility. The ATR tool can help calibrate\n\u{2022} If the tallest bar is in a higher range, trades are holding for extended periods — consider overnight/weekend exposure risk in live trading\n\u{2022} A very uniform distribution (one tall bar) means SL or TP is being hit at a consistent speed — check the Exit Reasons chart to see which one\n\nPro tip: Focus on the tallest bar — that's your most common hold time and the best predictor of typical market exposure. If the tallest bar is far from the others, your strategy has a dominant rhythm. If bars are spread evenly, hold times are unpredictable — which makes position sizing and risk planning harder."
        ) {
            let buckets = buildDurationBuckets()
            let maxBucket = buckets.max(by: { $0.count < $1.count })
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption2).foregroundStyle(.blue)
                        Text("Bars held")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.and.down")
                            .font(.caption2).foregroundStyle(.blue)
                        Text("Trade count")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
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
                .chartXAxisLabel("Bars held")
                .chartYAxisLabel("Trades")
                .frame(height: 200)
            }
        }
    }

    private struct DurationBucket {
        let label: String
        let count: Int
        let sortKey: Int
    }

    private func buildDurationBuckets() -> [DurationBucket] {
        var rawCounts: [Int: Int] = [:]
        for trade in result.trades {
            rawCounts[trade.barCount, default: 0] += 1
        }

        let distinctValues = rawCounts.keys.sorted()

        // If 12 or fewer distinct values, show each individually
        if distinctValues.count <= 12 {
            return distinctValues.map {
                DurationBucket(label: "\($0)", count: rawCounts[$0]!, sortKey: $0)
            }
        }

        // Otherwise, bucket into ranges scaled to keep ≤ 12 buckets
        let maxVal = distinctValues.last ?? 1
        let step: Int
        if maxVal <= 30 { step = 3 }
        else if maxVal <= 60 { step = 5 }
        else if maxVal <= 120 { step = 10 }
        else if maxVal <= 250 { step = 25 }
        else { step = 50 }

        let ranges: [(Int, Int)] = stride(from: 0, to: maxVal + step, by: step)
            .map { ($0, min($0 + step - 1, maxVal)) }

        return ranges.compactMap { (low, high) in
            let count = rawCounts.filter { $0.key >= low && $0.key <= high }.values.reduce(0, +)
            guard count > 0 else { return nil }
            let label = low == high ? "\(low)" : "\(low)-\(high)"
            return DurationBucket(label: label, count: count, sortKey: low)
        }
    }

    // MARK: - 7. P&L by Time of Day

    private var timeOfDayChart: some View {
        chartCard(
            "P&L by Time of Day",
            subtitle: "Which hours are most profitable",
            detail: "Markets have personality throughout the day — the open is chaotic, midday is quiet, the close gets volatile again. This chart shows which time periods your strategy thrives in and which ones it should avoid. When many hours are active, they are grouped into blocks for readability.\n\n\u{1F7E2} Green bars = profitable periods\n\u{1F534} Red bars = losing periods\n\nCommon patterns:\n\u{2022} Strong at the open = strategy capitalizes on opening volatility\n\u{2022} Weak at midday = low volume chop is killing entries\n\u{2022} Strong at close = strategy benefits from end-of-day momentum\n\nWhat to do:\n\u{2022} If 1-2 periods account for all your losses, consider scheduling your bot to avoid those times entirely\n\u{2022} If profits concentrate in one period, the edge might be time-specific — test if it holds across different date ranges\n\nPro tip: Times are in your local timezone. The best and worst performing periods are annotated with their dollar values. If trading global markets, consider what's happening at that time in the contract's native exchange timezone."
        ) {
            let hourData = buildTimeOfDayData()
            let bestHour = hourData.max(by: { $0.pnl < $1.pnl })
            let worstHour = hourData.min(by: { $0.pnl < $1.pnl })
            VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Profitable")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Losing")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                ForEach(hourData, id: \.hour) { item in
                    let isBestOrWorst = item.hour == bestHour?.hour || item.hour == worstHour?.hour
                    let opacity: Double = isBestOrWorst ? 1.0 : 0.5
                    BarMark(
                        x: .value("Hour", item.label),
                        y: .value("P&L", item.pnl)
                    )
                    .foregroundStyle(item.pnl >= 0 ? .green.opacity(opacity) : .red.opacity(opacity))
                    .cornerRadius(3)
                    .annotation(position: item.pnl >= 0 ? .top : .bottom, spacing: 2) {
                        Text(item.pnl, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.system(size: isBestOrWorst ? 9 : 8, weight: isBestOrWorst ? .bold : .medium))
                            .foregroundStyle(item.pnl >= 0 ? .green : .red)
                    }
                }
            }
            .chartYAxis { currencyAxis }
            .chartXAxis {
                AxisMarks(values: hourData.map(\.label)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(anchor: .top) {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(size: 9))
                                .fixedSize()
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .frame(height: 220)
            .padding(.bottom, 8)
            }
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

        let activeHours = hourPnL.keys.sorted()
        guard !activeHours.isEmpty else { return [] }

        let minHour = activeHours.first!
        let maxHour = activeHours.last!
        let span = maxHour - minHour + 1

        // If 8 or fewer active hours, show each individually
        if activeHours.count <= 8 {
            return activeHours.map { hour in
                HourPnL(hour: hour, label: formatHourLabel(hour), pnl: hourPnL[hour]!)
            }
        }

        // Divide into exactly 8 buckets (or fewer if span < 8)
        let maxBuckets = min(8, span)
        let baseStep = span / maxBuckets
        let remainder = span % maxBuckets

        var buckets: [HourPnL] = []
        var h = minHour
        for i in 0..<maxBuckets {
            // Distribute remainder across first N buckets (1 extra hour each)
            let thisStep = baseStep + (i < remainder ? 1 : 0)
            let end = h + thisStep - 1
            let pnl = (h...end).reduce(0.0) { $0 + (hourPnL[$1] ?? 0) }
            let endLabel = formatHourLabel(min(end + 1, 24) % 24)
            let label = h == end ? formatHourLabel(h) : "\(formatHourLabel(h))-\(endLabel)"
            buckets.append(HourPnL(hour: h, label: label, pnl: pnl))
            h += thisStep
        }
        return buckets
    }

    private func formatHourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "a" : "p"
        return "\(h)\(suffix)"
    }

    // MARK: - 8. Rolling Win Rate

    private var rollingWinRateChart: some View {
        chartCard(
            "Rolling Win Rate",
            subtitle: "20-trade sliding window win percentage",
            detail: "Your overall win rate is just one number — this chart shows how it evolves over time. A strategy with 55% win rate overall might have spent half the backtest at 30% before a hot streak pulled it up.\n\n\u{2022} Dashed line = 50% (breakeven win rate)\n\u{1F7E2} Above the line = winning more than losing\n\u{1F534} Below the line = losing more than winning\n\nWhat to watch for:\n\u{2022} Stable above 50% = consistent edge, reliable strategy\n\u{2022} Trending downward = strategy may be curve-fit to early data and degrading\n\u{2022} Wild swings = unstable edge, may not survive live trading\n\u{2022} Dips then recovers = normal variance, but check if dips correlate with specific market conditions\n\nPro tip: A strategy with 40% win rate can still be very profitable if the average win is 2x+ the average loss. Don't chase high win rates — chase high expectancy (win rate x avg win - loss rate x avg loss)."
        ) {
            rollingWinRateChartContent
        }
    }

    private var rollingWinRateChartContent: some View {
        let rawData = buildRollingWinRate(window: 20)
        let data = buildWinRateWithCrossings(rawData)
        let finalValue = data.last?.value ?? 0
        let maxX = data.last?.x ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Final Win Rate:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(round(finalValue)))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(finalValue >= 50 ? .green : .red)
                }
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("> 50%")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("< 50%")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            winRateChart(data: data, maxX: maxX)
        }
    }

    private struct WinRatePoint {
        let x: Double
        let value: Double
    }

    private struct WinRateRun {
        let points: [WinRatePoint]
        let isBelow50: Bool
    }

    private func buildWinRateWithCrossings(_ raw: [Double]) -> [WinRatePoint] {
        guard !raw.isEmpty else { return [] }
        var points: [WinRatePoint] = []
        for i in 0..<raw.count {
            let prev = i == 0 ? raw[0] : raw[i - 1]
            let curr = raw[i]
            let prevX = i == 0 ? Double(i + 1) : Double(i)
            let currX = Double(i + 1)
            if i > 0 && ((prev > 50 && curr < 50) || (prev < 50 && curr > 50)) {
                let fraction = (prev - 50) / (prev - curr)
                let crossX = prevX + fraction * (currX - prevX)
                points.append(WinRatePoint(x: crossX, value: 50))
            }
            points.append(WinRatePoint(x: currX, value: curr))
        }
        return points
    }

    private func buildWinRateRuns(from data: [WinRatePoint]) -> [WinRateRun] {
        guard data.count >= 2 else { return [] }
        var runs: [WinRateRun] = []
        var currentPoints: [WinRatePoint] = [data[0]]
        var currentBelow = data[0].value < 50

        for i in 1..<data.count {
            let pt = data[i]
            let isBelow = pt.value < 50
            if isBelow == currentBelow || pt.value == 50 {
                currentPoints.append(pt)
            } else {
                currentPoints.append(pt)
                runs.append(WinRateRun(points: currentPoints, isBelow50: currentBelow))
                currentPoints = [pt]
                currentBelow = isBelow
            }
        }
        if !currentPoints.isEmpty {
            runs.append(WinRateRun(points: currentPoints, isBelow50: currentBelow))
        }
        return runs
    }

    @ViewBuilder
    private func winRateChart(data: [WinRatePoint], maxX: Double) -> some View {
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
            // Background zones: green above 50%, red below
            RectangleMark(yStart: .value("y", 50), yEnd: .value("y", 100))
                .foregroundStyle(.green.opacity(0.06))
            RectangleMark(yStart: .value("y", 0), yEnd: .value("y", 50))
                .foregroundStyle(.red.opacity(0.06))
            // Line segments
            ForEach(0..<max(data.count - 1, 0), id: \.self) { i in
                let startVal = data[i].value
                let endVal = data[i + 1].value
                let isBelow = (startVal < 50 || endVal < 50) && !(startVal == 50 && endVal >= 50)
                let color: Color = isBelow ? .red : .green
                LineMark(
                    x: .value("Trade", data[i].x),
                    y: .value("Win %", data[i].value),
                    series: .value("seg", i)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                LineMark(
                    x: .value("Trade", data[i + 1].x),
                    y: .value("Win %", data[i + 1].value),
                    series: .value("seg", i)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
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
        .chartXScale(domain: 1...maxX)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel("Trade #")
        .frame(height: 210)
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
            let maxWin = longestWin?.length ?? 1
            let maxLoss = longestLoss?.length ?? 1
            let yBound = max(maxWin, maxLoss) + 1
            let streakCount = streaks.count
            VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Win streak")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Loss streak")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.caption2).foregroundStyle(.blue)
                    Text("Streak length")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                ForEach(streaks, id: \.index) { item in
                    let isHighlight = item.index == longestWin?.index || item.index == longestLoss?.index
                    let opacity: Double = isHighlight ? 1.0 : 0.5
                    BarMark(
                        x: .value("Streak", item.index),
                        y: .value("Length", item.isWin ? item.length : -item.length)
                    )
                    .foregroundStyle(item.isWin ? .green.opacity(opacity) : .red.opacity(opacity))
                    .cornerRadius(3)
                    .annotation(position: item.isWin ? .top : .bottom, spacing: 2) {
                        Text("\(item.length)")
                            .font(.system(size: isHighlight ? 9 : 8, weight: isHighlight ? .bold : .medium))
                            .foregroundStyle(item.isWin ? .green : .red)
                    }
                }
            }
            .chartXScale(domain: -1...(streakCount))
            .chartYScale(domain: (-yBound)...yBound)
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
            .chartXAxis(.hidden)
            .frame(height: 220)
            }
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
