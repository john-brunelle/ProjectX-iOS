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

    // Market
    var accountId: Int = 0     // DEPRECATED — kept for migration only. Use AccountBotAssignment.
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

    // Legacy — kept so SwiftData doesn't need a destructive migration
    var runningOnAccountId: Int?
    var statusRaw: String = "stopped"

    // Status
    var isActive: Bool = true
    var isArchived: Bool = false

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Lifetime P&L (accumulated across all stopped sessions)
    var lifetimePnL: Double = 0
    var lifetimeTradeCount: Int = 0

    // Operating Hours
    var operatingMode: String = "24/7"   // "24/7", "rth", "custom"
    var opStartHour: Int = 9
    var opStartMinute: Int = 30
    var opEndHour: Int = 16
    var opEndMinute: Int = 0
    var sleepWindows: String = "[{\"sh\":16,\"sm\":0,\"eh\":18,\"em\":0}]"  // Default: Market Close 4PM-6PM

    // Many-to-many: indicators used by this bot
    @Relationship(inverse: \IndicatorConfig.bots)
    var indicators: [IndicatorConfig]

    // MARK: Computed Properties

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

    /// Durable ownership prefix used in order customTags (e.g. "bot-A1B2C3D4").
    /// Matches orders placed by this bot across restarts and cold starts.
    var tagPrefix: String { "bot-\(id.uuidString.prefix(8))" }

    // MARK: Operating Hours Helpers

    var decodedSleepWindows: [SleepWindow] {
        guard let data = sleepWindows.data(using: .utf8),
              let windows = try? JSONDecoder().decode([SleepWindow].self, from: data)
        else { return [] }
        return windows
    }

    func encodeSleepWindows(_ windows: [SleepWindow]) {
        guard let data = try? JSONEncoder().encode(windows),
              let json = String(data: data, encoding: .utf8)
        else { return }
        sleepWindows = json
    }

    var operatingHoursLabel: String {
        if operatingMode == "24/7" { return "24/7" }
        let startStr = SleepWindow.formatTime(hour: opStartHour, minute: opStartMinute)
        let endStr = SleepWindow.formatTime(hour: opEndHour, minute: opEndMinute)
        let prefix: String
        switch operatingMode {
        case "rth": prefix = "RTH"
        case "extended": prefix = "Extended"
        default: prefix = "Custom"
        }
        return "\(prefix) \(startStr) – \(endStr)"
    }

    // MARK: Init

    init(
        id: UUID = UUID(),
        name: String,
        accountId: Int = 0,
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
        self.id = id
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
        self.createdAt = Date()
        self.updatedAt = Date()
        self.indicators = indicators
    }
}

// MARK: - Sleep Window

struct SleepWindow: Codable, Identifiable, Equatable {
    var id = UUID()
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    enum CodingKeys: String, CodingKey {
        case startHour = "sh"
        case startMinute = "sm"
        case endHour = "eh"
        case endMinute = "em"
    }

    init(startHour: Int = 12, startMinute: Int = 0, endHour: Int = 13, endMinute: Int = 0) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.startHour = try c.decode(Int.self, forKey: .startHour)
        self.startMinute = try c.decode(Int.self, forKey: .startMinute)
        self.endHour = try c.decode(Int.self, forKey: .endHour)
        self.endMinute = try c.decode(Int.self, forKey: .endMinute)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startHour, forKey: .startHour)
        try c.encode(startMinute, forKey: .startMinute)
        try c.encode(endHour, forKey: .endHour)
        try c.encode(endMinute, forKey: .endMinute)
    }

    var label: String {
        "\(Self.formatTime(hour: startHour, minute: startMinute)) → \(Self.formatTime(hour: endHour, minute: endMinute))"
    }

    static func formatTime(hour: Int, minute: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return minute == 0 ? "\(h) \(suffix)" : "\(h):\(String(format: "%02d", minute)) \(suffix)"
    }
}
