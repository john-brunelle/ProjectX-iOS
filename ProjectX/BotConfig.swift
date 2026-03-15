import Foundation
import SwiftData

// ─────────────────────────────────────────────
// Bot Configuration — SwiftData Model
//
// Persisted bot setups that reference indicator
// presets. Phase 1: model only. Phase 2: wizard UI.
// ─────────────────────────────────────────────

// MARK: - Bot Status

enum BotStatus: String, Codable, CaseIterable, Identifiable {
    case stopped
    case running
    case paused
    case error

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stopped: "Stopped"
        case .running: "Running"
        case .paused:  "Paused"
        case .error:   "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .stopped: "stop.circle.fill"
        case .running: "play.circle.fill"
        case .paused:  "pause.circle.fill"
        case .error:   "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Trade Direction Filter

enum TradeDirectionFilter: String, Codable, CaseIterable, Identifiable {
    case both
    case longOnly
    case shortOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .both:      "Longs & Shorts"
        case .longOnly:  "Longs Only"
        case .shortOnly: "Shorts Only"
        }
    }
}

// MARK: - SwiftData Model

@Model
final class BotConfig {
    var id: UUID
    var name: String

    // Market & Account
    var accountId: Int
    var contractId: String
    var contractName: String   // denormalized for display

    // Bar Configuration
    var barUnit: Int           // raw value of BarUnit (1=sec, 2=min, 3=hr, 4=day, 5=wk, 6=mo)
    var barUnitNumber: Int     // e.g. 5 for "5-minute bars"

    // Risk Management
    var stopLossTicks: Int?
    var takeProfitTicks: Int?
    var quantity: Int          // fixed contract quantity per trade
    var tradeDirectionRaw: String  // TradeDirectionFilter raw value

    // Status
    var statusRaw: String

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Lifetime P&L (accumulated across all stopped sessions)
    var lifetimePnL: Double = 0
    var lifetimeTradeCount: Int = 0

    // Many-to-many: indicators used by this bot
    @Relationship(inverse: \IndicatorConfig.bots)
    var indicators: [IndicatorConfig]

    // MARK: Computed Properties

    var status: BotStatus {
        get { BotStatus(rawValue: statusRaw) ?? .stopped }
        set { statusRaw = newValue.rawValue }
    }

    var tradeDirection: TradeDirectionFilter {
        get { TradeDirectionFilter(rawValue: tradeDirectionRaw) ?? .both }
        set { tradeDirectionRaw = newValue.rawValue }
    }

    var barUnitEnum: BarUnit? {
        BarUnit(rawValue: barUnit)
    }

    var barSizeLabel: String {
        let unitLabel = barUnitEnum?.label ?? "Unknown"
        return barUnitNumber == 1 ? unitLabel : "\(barUnitNumber) \(unitLabel)"
    }

    // MARK: Init

    init(
        name: String,
        accountId: Int,
        contractId: String,
        contractName: String,
        barUnit: BarUnit = .minute,
        barUnitNumber: Int = 5,
        stopLossTicks: Int? = nil,
        takeProfitTicks: Int? = nil,
        quantity: Int = 1,
        tradeDirection: TradeDirectionFilter = .both,
        indicators: [IndicatorConfig] = []
    ) {
        self.id = UUID()
        self.name = name
        self.accountId = accountId
        self.contractId = contractId
        self.contractName = contractName
        self.barUnit = barUnit.rawValue
        self.barUnitNumber = barUnitNumber
        self.stopLossTicks = stopLossTicks
        self.takeProfitTicks = takeProfitTicks
        self.quantity = quantity
        self.tradeDirectionRaw = tradeDirection.rawValue
        self.statusRaw = BotStatus.stopped.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.indicators = indicators
    }
}
