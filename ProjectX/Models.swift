import Foundation

struct LoginRequest: Codable {
    let userName: String
    let apiKey: String
}

struct LoginResponse: Codable {
    let token: String?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}

struct ValidateResponse: Codable {
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
    let newToken: String?
}

struct Account: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let balance: Double
    let canTrade: Bool
    let isVisible: Bool
    let simulated: Bool?   // nil-safe: older API responses may omit this field
}

struct AccountSearchRequest: Codable {
    let onlyActiveAccounts: Bool
}

struct AccountSearchResponse: Codable {
    let accounts: [Account]?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}


// ── Contract Models ───────────────────────────

struct Contract: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let tickSize: Double
    let tickValue: Double
    let activeContract: Bool
    let symbolId: String
}

struct ContractSearchRequest: Codable {
    let searchText: String
    let live: Bool
}

struct ContractSearchResponse: Codable {
    let contracts: [Contract]?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}

struct ContractByIdRequest: Codable {
    let contractId: String
}

struct ContractByIdResponse: Codable {
    let contract: Contract?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}

struct AvailableContractsRequest: Codable {
    let live: Bool
}

// ── Bar / History Models ──────────────────────

struct Bar: Codable, Identifiable {
    var id: String { t }
    let t: String
    let o: Double
    let h: Double
    let l: Double
    let c: Double
    let v: Int
}

enum BarUnit: Int, CaseIterable, Identifiable {
    case second = 1, minute = 2, hour = 3, day = 4, week = 5, month = 6
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .second: return "Second"
        case .minute: return "Minute"
        case .hour:   return "Hour"
        case .day:    return "Day"
        case .week:   return "Week"
        case .month:  return "Month"
        }
    }
}

struct RetrieveBarsRequest: Codable {
    let contractId: String
    let live: Bool
    let startTime: String
    let endTime: String
    let unit: Int
    let unitNumber: Int
    let limit: Int
    let includePartialBar: Bool
}

struct RetrieveBarsResponse: Codable {
    let bars: [Bar]?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}

// ── Order Models ──────────────────────────────

enum OrderType: Int, CaseIterable, Identifiable {
    case limit = 1, market = 2, stop = 4, trailingStop = 5, joinBid = 6, joinAsk = 7
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .limit:        return "Limit"
        case .market:       return "Market"
        case .stop:         return "Stop"
        case .trailingStop: return "Trailing Stop"
        case .joinBid:      return "Join Bid"
        case .joinAsk:      return "Join Ask"
        }
    }
}

enum OrderSide: Int, CaseIterable, Identifiable {
    case bid = 0, ask = 1
    var id: Int { rawValue }
    var label: String { self == .bid ? "Buy" : "Sell" }
}

enum OrderStatus: Int {
    case open = 1, filled = 2, cancelled = 3, rejected = 4, expired = 5
    var label: String {
        switch self {
        case .open:      return "Open"
        case .filled:    return "Filled"
        case .cancelled: return "Cancelled"
        case .rejected:  return "Rejected"
        case .expired:   return "Expired"
        default:         return "Unknown"
        }
    }
}

struct Order: Codable, Identifiable {
    let id: Int
    let accountId: Int
    let contractId: String
    let symbolId: String?
    let creationTimestamp: String
    let updateTimestamp: String
    let status: Int
    let type: Int
    let side: Int
    let size: Int
    let limitPrice: Double?
    let stopPrice: Double?
    let fillVolume: Int?
    let filledPrice: Double?
    let customTag: String?

    var statusLabel: String { OrderStatus(rawValue: status)?.label ?? "Unknown" }
    var typeLabel:   String { OrderType(rawValue: type)?.label   ?? "Unknown" }
    var sideLabel:   String { OrderSide(rawValue: side)?.label   ?? "Unknown" }
}

struct OrderSearchRequest: Codable {
    let accountId: Int
    let startTimestamp: String
    let endTimestamp: String?
}

struct OpenOrderSearchRequest: Codable {
    let accountId: Int
}

struct OrderSearchResponse: Codable {
    let orders: [Order]?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}

struct BracketOrder: Codable {
    let ticks: Int
    let type: Int
}

struct PlaceOrderRequest: Codable {
    let accountId: Int
    let contractId: String
    let type: Int
    let side: Int
    let size: Int
    let limitPrice: Double?
    let stopPrice: Double?
    let trailPrice: Double?
    let customTag: String?
    let stopLossBracket: BracketOrder?
    let takeProfitBracket: BracketOrder?
}

struct PlaceOrderResponse: Codable {
    let orderId: Int?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}

struct CancelOrderRequest: Codable {
    let accountId: Int
    let orderId: Int
}

struct ModifyOrderRequest: Codable {
    let accountId: Int
    let orderId: Int
    let size: Int?
    let limitPrice: Double?
    let stopPrice: Double?
    let trailPrice: Double?
}

struct BasicResponse: Codable {
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}


// ── Position Models ───────────────────────────

enum PositionType: Int {
    case long  = 1
    case short = 2
    var label: String { self == .long ? "Long" : "Short" }
}

struct Position: Codable, Identifiable {
    let id: Int
    let accountId: Int
    let contractId: String
    let creationTimestamp: String
    let type: Int
    let size: Int
    let averagePrice: Double

    var typeLabel: String { PositionType(rawValue: type)?.label ?? "Unknown" }
    var isLong:    Bool   { type == PositionType.long.rawValue }
}

struct PositionSearchRequest: Codable {
    let accountId: Int
}

struct PositionSearchResponse: Codable {
    let positions: [Position]?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}

struct ClosePositionRequest: Codable {
    let accountId: Int
    let contractId: String
}

struct PartialClosePositionRequest: Codable {
    let accountId: Int
    let contractId: String
    let size: Int
}

// ── Trade Models ──────────────────────────────

struct Trade: Codable, Identifiable {
    let id: Int
    let accountId: Int
    let contractId: String
    let creationTimestamp: String
    let price: Double
    let profitAndLoss: Double?   // null = half-turn trade
    let fees: Double
    let side: Int
    let size: Int
    let voided: Bool
    let orderId: Int

    var sideLabel: String { side == 0 ? "Buy" : "Sell" }
    var isHalfTurn: Bool  { profitAndLoss == nil }
}

struct TradeSearchRequest: Codable {
    let accountId: Int
    let startTimestamp: String
    let endTimestamp: String?
}

struct TradeSearchResponse: Codable {
    let trades: [Trade]?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}


/// Envelope wrapper for user hub messages: {"action": Int, "data": T}
struct GatewayEnvelope<T: Codable>: Codable {
    let action: Int
    let data: T
}

// ── Realtime / SignalR Models ─────────────────

struct Quote: Identifiable, Codable {
    var id: String { symbol }
    let symbol: String
    let symbolName: String?
    let lastPrice: Double
    let bestBid: Double
    let bestAsk: Double
    let change: Double
    let changePercent: Double
    let open: Double
    let high: Double
    let low: Double
    let volume: Double
    let lastUpdated: String?
    let timestamp: String?

    /// Display name with fallback to symbol
    var displayName: String { symbolName ?? symbol }

    /// Merge incoming quote with existing, preferring incoming non-zero values
    static func merged(existing e: Quote, incoming i: Quote) -> Quote {
        Quote(
            symbol: i.symbol,
            symbolName: i.symbolName ?? e.symbolName,
            lastPrice: i.lastPrice != 0 ? i.lastPrice : e.lastPrice,
            bestBid: i.bestBid != 0 ? i.bestBid : e.bestBid,
            bestAsk: i.bestAsk != 0 ? i.bestAsk : e.bestAsk,
            change: i.change != 0 ? i.change : e.change,
            changePercent: i.changePercent != 0 ? i.changePercent : e.changePercent,
            open: i.open != 0 ? i.open : e.open,
            high: i.high != 0 ? i.high : e.high,
            low: i.low != 0 ? i.low : e.low,
            volume: i.volume != 0 ? i.volume : e.volume,
            lastUpdated: i.lastUpdated ?? e.lastUpdated,
            timestamp: i.timestamp ?? e.timestamp
        )
    }

    init(symbol: String, symbolName: String?, lastPrice: Double, bestBid: Double,
         bestAsk: Double, change: Double, changePercent: Double, open: Double,
         high: Double, low: Double, volume: Double, lastUpdated: String?, timestamp: String?) {
        self.symbol = symbol; self.symbolName = symbolName; self.lastPrice = lastPrice
        self.bestBid = bestBid; self.bestAsk = bestAsk; self.change = change
        self.changePercent = changePercent; self.open = open; self.high = high
        self.low = low; self.volume = volume; self.lastUpdated = lastUpdated
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol        = try c.decode(String.self, forKey: .symbol)
        symbolName    = try c.decodeIfPresent(String.self, forKey: .symbolName)
        lastPrice     = try c.decodeIfPresent(Double.self, forKey: .lastPrice) ?? 0
        bestBid       = try c.decodeIfPresent(Double.self, forKey: .bestBid) ?? 0
        bestAsk       = try c.decodeIfPresent(Double.self, forKey: .bestAsk) ?? 0
        change        = try c.decodeIfPresent(Double.self, forKey: .change) ?? 0
        changePercent = try c.decodeIfPresent(Double.self, forKey: .changePercent) ?? 0
        open          = try c.decodeIfPresent(Double.self, forKey: .open) ?? 0
        high          = try c.decodeIfPresent(Double.self, forKey: .high) ?? 0
        low           = try c.decodeIfPresent(Double.self, forKey: .low) ?? 0
        volume        = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0
        lastUpdated   = try c.decodeIfPresent(String.self, forKey: .lastUpdated)
        timestamp     = try c.decodeIfPresent(String.self, forKey: .timestamp)
    }
}

struct MarketTradePayload: Codable {
    let symbolId: String
    let price: Double
    let timestamp: String
    let type: Int
    let volume: Int
}

struct MarketTrade: Identifiable {
    let id = UUID()
    let symbolId: String
    let price: Double
    let timestamp: String
    let type: Int      // TradeLogType: 0=Buy, 1=Sell
    let volume: Int

    var isBuy: Bool { type == 0 }

    init(symbolId: String, price: Double, timestamp: String, type: Int, volume: Int) {
        self.symbolId = symbolId
        self.price = price
        self.timestamp = timestamp
        self.type = type
        self.volume = volume
    }

    init(from payload: MarketTradePayload) {
        self.symbolId = payload.symbolId
        self.price = payload.price
        self.timestamp = payload.timestamp
        self.type = payload.type
        self.volume = payload.volume
    }
}

struct DepthEntry: Codable {
    let price: Double
    let volume: Int
    let currentVolume: Int
    let type: Int
    let timestamp: String
}

struct DOMEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let type: Int      // DomType enum
    let price: Double
    let volume: Int
    let currentVolume: Int
}

enum DomType: Int {
    case unknown = 0, ask = 1, bid = 2
    case bestAsk = 3, bestBid = 4, trade = 5, reset = 6
    case low = 7, high = 8, newBestBid = 9, newBestAsk = 10, fill = 11
}
