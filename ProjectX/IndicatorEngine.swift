import Foundation

// ─────────────────────────────────────────────
// Indicator Calculation Engine
//
// Pure logic — no SwiftUI, no @Observable.
// Takes [Bar] + config → Signal.
//
// Used by both live bot runner and backtester.
// Thread-safe: all static methods, no mutable state.
// ─────────────────────────────────────────────

// MARK: - Signal

enum Signal: Equatable {
    case buy
    case sell
    case neutral
}

// MARK: - Indicator Result

struct IndicatorResult {
    let signal: Signal
    let indicatorType: IndicatorType
    let values: [String: Double]   // diagnostics, e.g. ["rsi": 28.5]
}

// MARK: - Engine

struct IndicatorEngine {

    // MARK: Public API

    /// Evaluate a single indicator against a bar array.
    /// Bars should be sorted oldest-first (index 0 = oldest).
    static func evaluate(bars: [Bar], config: IndicatorConfig) -> IndicatorResult {
        let params = config.parameters
        switch params {
        case .rsi(let period, let overbought, let oversold):
            return calculateRSI(bars: bars, period: period, overbought: overbought, oversold: oversold)
        case .macd(let fast, let slow, let signal):
            return calculateMACD(bars: bars, fastPeriod: fast, slowPeriod: slow, signalPeriod: signal)
        case .obv(let smoothing):
            return calculateOBV(bars: bars, smoothingPeriod: smoothing)
        case .ma(let fast, let slow, let useEMA):
            return calculateMA(bars: bars, fastPeriod: fast, slowPeriod: slow, useEMA: useEMA)
        }
    }

    /// Evaluate multiple indicators with AND logic.
    /// Returns `.buy` only if ALL non-neutral results are `.buy`.
    /// Returns `.sell` only if ALL non-neutral results are `.sell`.
    /// Returns `.neutral` if mixed or all neutral.
    static func evaluateAll(bars: [Bar], configs: [IndicatorConfig]) -> Signal {
        guard !configs.isEmpty else { return .neutral }

        let results = configs.map { evaluate(bars: bars, config: $0) }
        let nonNeutral = results.filter { $0.signal != .neutral }

        guard !nonNeutral.isEmpty else { return .neutral }

        let allBuy  = nonNeutral.allSatisfy { $0.signal == .buy }
        let allSell = nonNeutral.allSatisfy { $0.signal == .sell }

        if allBuy  { return .buy }
        if allSell { return .sell }
        return .neutral
    }

    // MARK: - RSI Calculator

    private static func calculateRSI(
        bars: [Bar],
        period: Int,
        overbought: Double,
        oversold: Double
    ) -> IndicatorResult {
        // Need at least period + 2 bars (period+1 for initial RSI, +1 for crossing detection)
        guard bars.count >= period + 2 else {
            return IndicatorResult(signal: .neutral, indicatorType: .rsi, values: [:])
        }

        let closes = bars.map { $0.c }

        // Calculate price changes
        var gains: [Double] = []
        var losses: [Double] = []
        for i in 1..<closes.count {
            let change = closes[i] - closes[i - 1]
            gains.append(max(change, 0))
            losses.append(max(-change, 0))
        }

        // Calculate RSI series using EMA (Wilder's smoothing)
        var rsiValues: [Double] = []

        // Seed with SMA for the first `period` values
        let initialAvgGain = gains.prefix(period).reduce(0, +) / Double(period)
        let initialAvgLoss = losses.prefix(period).reduce(0, +) / Double(period)

        var avgGain = initialAvgGain
        var avgLoss = initialAvgLoss

        func rsiFromAvg(_ gain: Double, _ loss: Double) -> Double {
            if loss == 0 { return 100 }
            let rs = gain / loss
            return 100 - (100 / (1 + rs))
        }

        rsiValues.append(rsiFromAvg(avgGain, avgLoss))

        // Continue with Wilder's smoothing
        for i in period..<gains.count {
            avgGain = (avgGain * Double(period - 1) + gains[i]) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + losses[i]) / Double(period)
            rsiValues.append(rsiFromAvg(avgGain, avgLoss))
        }

        guard rsiValues.count >= 2 else {
            return IndicatorResult(signal: .neutral, indicatorType: .rsi, values: [:])
        }

        let current  = rsiValues[rsiValues.count - 1]
        let previous = rsiValues[rsiValues.count - 2]

        // Crossing detection
        var signal: Signal = .neutral
        if previous >= oversold && current < oversold {
            signal = .buy   // RSI crossed below oversold
        } else if previous <= overbought && current > overbought {
            signal = .sell  // RSI crossed above overbought
        }

        return IndicatorResult(
            signal: signal,
            indicatorType: .rsi,
            values: ["rsi": current, "previousRsi": previous]
        )
    }

    // MARK: - MACD Calculator

    private static func calculateMACD(
        bars: [Bar],
        fastPeriod: Int,
        slowPeriod: Int,
        signalPeriod: Int
    ) -> IndicatorResult {
        // Need enough bars for slow EMA + signal EMA + 1 for crossing
        let minBars = slowPeriod + signalPeriod + 1
        guard bars.count >= minBars else {
            return IndicatorResult(signal: .neutral, indicatorType: .macd, values: [:])
        }

        let closes = bars.map { $0.c }

        // Calculate fast and slow EMAs
        let fastEMA = ema(values: closes, period: fastPeriod)
        let slowEMA = ema(values: closes, period: slowPeriod)

        // MACD line = fast EMA - slow EMA (aligned from the end)
        // Both arrays may be different lengths; align from the end
        let macdCount = min(fastEMA.count, slowEMA.count)
        let fastSlice = fastEMA.suffix(macdCount)
        let slowSlice = slowEMA.suffix(macdCount)

        var macdLine: [Double] = []
        for (f, s) in zip(fastSlice, slowSlice) {
            macdLine.append(f - s)
        }

        guard macdLine.count >= signalPeriod + 1 else {
            return IndicatorResult(signal: .neutral, indicatorType: .macd, values: [:])
        }

        // Signal line = EMA of MACD line
        let signalLine = ema(values: macdLine, period: signalPeriod)

        guard signalLine.count >= 2 else {
            return IndicatorResult(signal: .neutral, indicatorType: .macd, values: [:])
        }

        // Align MACD and signal from the end
        let currentMACD    = macdLine[macdLine.count - 1]
        let previousMACD   = macdLine[macdLine.count - 2]
        let currentSignal  = signalLine[signalLine.count - 1]
        let previousSignal = signalLine[signalLine.count - 2]

        // Crossing detection
        var signal: Signal = .neutral
        if previousMACD <= previousSignal && currentMACD > currentSignal {
            signal = .buy   // MACD crossed above signal line
        } else if previousMACD >= previousSignal && currentMACD < currentSignal {
            signal = .sell  // MACD crossed below signal line
        }

        let histogram = currentMACD - currentSignal

        return IndicatorResult(
            signal: signal,
            indicatorType: .macd,
            values: [
                "macd": currentMACD,
                "signal": currentSignal,
                "histogram": histogram
            ]
        )
    }

    // MARK: - OBV Calculator

    private static func calculateOBV(
        bars: [Bar],
        smoothingPeriod: Int
    ) -> IndicatorResult {
        // Need smoothing + 2 bars (smoothing for MA, +1 for OBV start, +1 for crossing)
        guard bars.count >= smoothingPeriod + 2 else {
            return IndicatorResult(signal: .neutral, indicatorType: .obv, values: [:])
        }

        // Calculate cumulative OBV
        var obvValues: [Double] = [0]
        for i in 1..<bars.count {
            let prev = obvValues[i - 1]
            if bars[i].c > bars[i - 1].c {
                obvValues.append(prev + Double(bars[i].v))
            } else if bars[i].c < bars[i - 1].c {
                obvValues.append(prev - Double(bars[i].v))
            } else {
                obvValues.append(prev)
            }
        }

        // SMA of OBV
        let obvMA = sma(values: obvValues, period: smoothingPeriod)

        guard obvMA.count >= 2 else {
            return IndicatorResult(signal: .neutral, indicatorType: .obv, values: [:])
        }

        // Align OBV and MA from the end
        let currentOBV    = obvValues[obvValues.count - 1]
        let previousOBV   = obvValues[obvValues.count - 2]
        let currentMA     = obvMA[obvMA.count - 1]
        let previousMA    = obvMA[obvMA.count - 2]

        // Crossing detection
        var signal: Signal = .neutral
        if previousOBV <= previousMA && currentOBV > currentMA {
            signal = .buy   // OBV crossed above its MA
        } else if previousOBV >= previousMA && currentOBV < currentMA {
            signal = .sell  // OBV crossed below its MA
        }

        return IndicatorResult(
            signal: signal,
            indicatorType: .obv,
            values: ["obv": currentOBV, "obvMA": currentMA]
        )
    }

    // MARK: - Moving Average Calculator

    private static func calculateMA(
        bars: [Bar],
        fastPeriod: Int,
        slowPeriod: Int,
        useEMA: Bool
    ) -> IndicatorResult {
        // Need enough bars for slow MA + 1 for crossing detection
        let minBars = slowPeriod + 2
        guard bars.count >= minBars else {
            return IndicatorResult(signal: .neutral, indicatorType: .ma, values: [:])
        }

        let closes = bars.map { $0.c }

        // Calculate fast and slow moving averages
        let fastMA: [Double]
        let slowMA: [Double]

        if useEMA {
            fastMA = ema(values: closes, period: fastPeriod)
            slowMA = ema(values: closes, period: slowPeriod)
        } else {
            fastMA = sma(values: closes, period: fastPeriod)
            slowMA = sma(values: closes, period: slowPeriod)
        }

        guard fastMA.count >= 2 && slowMA.count >= 2 else {
            return IndicatorResult(signal: .neutral, indicatorType: .ma, values: [:])
        }

        // Align from the end
        let currentFast  = fastMA[fastMA.count - 1]
        let previousFast = fastMA[fastMA.count - 2]
        let currentSlow  = slowMA[slowMA.count - 1]
        let previousSlow = slowMA[slowMA.count - 2]

        // Crossing detection
        var signal: Signal = .neutral
        if previousFast <= previousSlow && currentFast > currentSlow {
            signal = .buy   // Fast MA crossed above slow MA (golden cross)
        } else if previousFast >= previousSlow && currentFast < currentSlow {
            signal = .sell  // Fast MA crossed below slow MA (death cross)
        }

        return IndicatorResult(
            signal: signal,
            indicatorType: .ma,
            values: [
                "fastMA": currentFast,
                "slowMA": currentSlow
            ]
        )
    }

    // MARK: - Helpers

    /// Exponential Moving Average. Returns array of EMA values (shorter than input by period-1).
    static func ema(values: [Double], period: Int) -> [Double] {
        guard values.count >= period else { return [] }

        let multiplier = 2.0 / Double(period + 1)

        // Seed with SMA of first `period` values
        let seed = values.prefix(period).reduce(0, +) / Double(period)
        var result: [Double] = [seed]

        for i in period..<values.count {
            let prev = result.last!
            let current = (values[i] - prev) * multiplier + prev
            result.append(current)
        }

        return result
    }

    /// Simple Moving Average. Returns array of SMA values (shorter than input by period-1).
    static func sma(values: [Double], period: Int) -> [Double] {
        guard values.count >= period else { return [] }

        var result: [Double] = []
        for i in (period - 1)..<values.count {
            let window = values[(i - period + 1)...i]
            result.append(window.reduce(0, +) / Double(period))
        }

        return result
    }
}
