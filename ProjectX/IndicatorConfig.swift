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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rsi:  "RSI"
        case .macd: "MACD"
        case .obv:  "OBV"
        }
    }

    var systemImage: String {
        switch self {
        case .rsi:  "chart.line.uptrend.xyaxis"
        case .macd: "point.3.connected.trianglepath.dotted"
        case .obv:  "chart.bar.xaxis"
        }
    }

    var defaultParameters: IndicatorParameters {
        switch self {
        case .rsi:  .defaultRSI()
        case .macd: .defaultMACD()
        case .obv:  .defaultOBV()
        }
    }
}

// MARK: - Indicator Parameters

enum IndicatorParameters: Codable, Equatable {
    case rsi(period: Int, overbought: Double, oversold: Double)
    case macd(fastPeriod: Int, slowPeriod: Int, signalPeriod: Int)
    case obv(smoothingPeriod: Int)

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

    // MARK: Summary

    var summary: String {
        switch self {
        case .rsi(let period, let overbought, let oversold):
            "Period: \(period), OB: \(Int(overbought)), OS: \(Int(oversold))"
        case .macd(let fast, let slow, let signal):
            "Fast: \(fast), Slow: \(slow), Signal: \(signal)"
        case .obv(let smoothing):
            "Smoothing: \(smoothing)"
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
    var bots: [BotConfig]?

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
    }
}
