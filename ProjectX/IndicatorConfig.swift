import Foundation
import SwiftData

// ─────────────────────────────────────────────
// Indicator Configuration — SwiftData Model
//
// Persisted indicator presets that can be
// reused across multiple bots.
// ─────────────────────────────────────────────

// MARK: - Indicator Type

enum IndicatorType: String, Codable, CaseIterable, Identifiable {
    case rsi
    case macd
    case obv
    case ma

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rsi:  "RSI"
        case .macd: "MACD"
        case .obv:  "OBV"
        case .ma:   "MA"
        }
    }

    var systemImage: String {
        switch self {
        case .rsi:  "chart.line.uptrend.xyaxis"
        case .macd: "point.3.connected.trianglepath.dotted"
        case .obv:  "chart.bar.xaxis"
        case .ma:   "line.diagonal"
        }
    }

    var defaultParameters: IndicatorParameters {
        switch self {
        case .rsi:  .defaultRSI()
        case .macd: .defaultMACD()
        case .obv:  .defaultOBV()
        case .ma:   .defaultMA()
        }
    }
}

// MARK: - Indicator Parameters

enum IndicatorParameters: Codable, Equatable {
    case rsi(period: Int, overbought: Double, oversold: Double)
    case macd(fastPeriod: Int, slowPeriod: Int, signalPeriod: Int)
    case obv(smoothingPeriod: Int)
    case ma(fastPeriod: Int, slowPeriod: Int, useEMA: Bool)

    // MARK: Defaults

    static func defaultRSI() -> IndicatorParameters {
        .rsi(period: 14, overbought: 70, oversold: 30)
    }

    static func defaultMACD() -> IndicatorParameters {
        .macd(fastPeriod: 12, slowPeriod: 26, signalPeriod: 9)
    }

    static func defaultOBV() -> IndicatorParameters {
        .obv(smoothingPeriod: 20)
    }

    static func defaultMA() -> IndicatorParameters {
        .ma(fastPeriod: 10, slowPeriod: 50, useEMA: true)
    }

    // MARK: Summary

    var summary: String {
        switch self {
        case .rsi(let period, let overbought, let oversold):
            "Period: \(period), OB: \(Int(overbought)), OS: \(Int(oversold))"
        case .macd(let fast, let slow, let signal):
            "Fast: \(fast), Slow: \(slow), Signal: \(signal)"
        case .obv(let smoothing):
            "Smoothing: \(smoothing)"
        case .ma(let fast, let slow, let useEMA):
            "\(useEMA ? "EMA" : "SMA") Fast: \(fast), Slow: \(slow)"
        }
    }

    /// Dynamic description of buy/sell signal logic based on current settings.
    var signalDescription: String {
        switch self {
        case .rsi(let period, let overbought, let oversold):
            return "BUY when \(period)-period RSI crosses below \(Int(oversold)) (oversold). " +
            "SELL when RSI crosses above \(Int(overbought)) (overbought)."
        case .macd(let fast, let slow, let signal):
            return "BUY when MACD line (\(fast)/\(slow)) crosses above the \(signal)-period signal line. " +
            "SELL when MACD line crosses below the signal line."
        case .obv(let smoothing):
            return "BUY when OBV crosses above its \(smoothing)-period moving average. " +
            "SELL when OBV crosses below its moving average."
        case .ma(let fast, let slow, let useEMA):
            let type = useEMA ? "EMA" : "SMA"
            return "BUY when \(fast)-period \(type) crosses above \(slow)-period \(type). " +
            "SELL when fast \(type) crosses below slow \(type)."
        }
    }
}

// MARK: - SwiftData Model

@Model
final class IndicatorConfig {
    var id: UUID
    var name: String
    var indicatorTypeRaw: String
    var parametersData: Data
    var createdAt: Date
    var updatedAt: Date

    // Many-to-many inverse (bots that use this indicator)
    var bots: [BotConfig] = []

    // MARK: Computed Properties

    var indicatorType: IndicatorType {
        get { IndicatorType(rawValue: indicatorTypeRaw) ?? .rsi }
        set { indicatorTypeRaw = newValue.rawValue }
    }

    var parameters: IndicatorParameters {
        get {
            (try? JSONDecoder().decode(IndicatorParameters.self, from: parametersData))
                ?? indicatorType.defaultParameters
        }
        set {
            parametersData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: Init

    init(name: String, type: IndicatorType, parameters: IndicatorParameters) {
        self.id = UUID()
        self.name = name
        self.indicatorTypeRaw = type.rawValue
        self.parametersData = (try? JSONEncoder().encode(parameters)) ?? Data()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.bots = []
    }
}

