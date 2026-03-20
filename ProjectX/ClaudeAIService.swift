import Foundation
import os

// ─────────────────────────────────────────────
// Claude AI Service — Anthropic Messages API
//
// Sends raw OHLCV bar data to Claude and returns
// a trading signal (buy / sell / neutral) via
// tool_use for guaranteed structured responses.
//
// Cost tracking accumulates daily token usage
// and enforces a configurable spend limit.
// ─────────────────────────────────────────────

@MainActor
@Observable
class ClaudeAIService {
    static let shared = ClaudeAIService()

    // MARK: - Configuration

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let keychainKey = "px_anthropic_apikey"

    // MARK: - Cost Tracking

    private(set) var todayInputTokens: Int {
        get { UserDefaults.standard.integer(forKey: "claude_daily_input_tokens") }
        set { UserDefaults.standard.set(newValue, forKey: "claude_daily_input_tokens") }
    }

    private(set) var todayOutputTokens: Int {
        get { UserDefaults.standard.integer(forKey: "claude_daily_output_tokens") }
        set { UserDefaults.standard.set(newValue, forKey: "claude_daily_output_tokens") }
    }

    private var lastResetDate: String {
        get { UserDefaults.standard.string(forKey: "claude_daily_reset_date") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "claude_daily_reset_date") }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "pref_claude_ai_enabled")
    }

    var dailySpendLimit: Double {
        let limit = UserDefaults.standard.double(forKey: "pref_claude_daily_spend_limit")
        return limit > 0 ? limit : 10.0
    }

    /// Estimated daily spend in USD based on accumulated tokens.
    var estimatedDailySpend: Double {
        // Haiku 4.5 pricing: $0.80/M input, $4/M output
        // Sonnet 4 pricing: $3/M input, $15/M output
        // Use Haiku rates as conservative estimate (actual model may differ)
        let inputCost = Double(todayInputTokens) * 0.80 / 1_000_000
        let outputCost = Double(todayOutputTokens) * 4.0 / 1_000_000
        return inputCost + outputCost
    }

    var hasAPIKey: Bool {
        KeychainHelper.load(for: keychainKey) != nil
    }

    private init() {}

    // MARK: - Public API

    struct EvalResult {
        let signal: Signal
        let confidence: Double
        let reason: String
    }

    /// Evaluate bars using Claude AI. Returns a signal with confidence and reasoning.
    /// Safe to call even without an API key — returns neutral with an error reason.
    func evaluate(
        bars: [Bar],
        contractName: String,
        contractId: String,
        barSize: String,
        model: String,
        barCount: Int,
        tickSize: Double?,
        tickValue: Double?,
        customPrompt: String
    ) async -> EvalResult {
        // Pre-flight checks
        guard isEnabled else {
            return EvalResult(signal: .neutral, confidence: 0, reason: "Claude AI disabled in settings")
        }

        guard let apiKey = KeychainHelper.load(for: keychainKey), !apiKey.isEmpty else {
            return EvalResult(signal: .neutral, confidence: 0, reason: "No Anthropic API key configured")
        }

        // Reset daily counters if new day
        resetDailyCountersIfNeeded()

        // Budget check
        guard estimatedDailySpend < dailySpendLimit else {
            return EvalResult(signal: .neutral, confidence: 0,
                              reason: "Daily spend limit reached ($\(String(format: "%.2f", estimatedDailySpend)) / $\(String(format: "%.2f", dailySpendLimit)))")
        }

        // Build request
        let recentBars = Array(bars.suffix(barCount))
        guard !recentBars.isEmpty else {
            return EvalResult(signal: .neutral, confidence: 0, reason: "No bar data available")
        }

        do {
            let body = buildRequestBody(
                bars: recentBars,
                contractName: contractName,
                contractId: contractId,
                barSize: barSize,
                model: model,
                tickSize: tickSize,
                tickValue: tickValue,
                customPrompt: customPrompt
            )

            var request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
            let httpBody = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            request.httpBody = httpBody

            if let jsonString = String(data: httpBody, encoding: .utf8) {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectX", category: "ClaudeAI")
                    .notice("─── Claude API Request ───\n\(jsonString)")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return EvalResult(signal: .neutral, confidence: 0, reason: "Invalid HTTP response")
            }

            switch httpResponse.statusCode {
            case 200:
                return parseResponse(data)
            case 401:
                return EvalResult(signal: .neutral, confidence: 0, reason: "Invalid Anthropic API key (401)")
            case 429:
                return EvalResult(signal: .neutral, confidence: 0, reason: "Anthropic rate limit hit (429)")
            case 529:
                return EvalResult(signal: .neutral, confidence: 0, reason: "Anthropic API overloaded (529)")
            default:
                let body = String(data: data, encoding: .utf8) ?? ""
                return EvalResult(signal: .neutral, confidence: 0,
                                  reason: "API error \(httpResponse.statusCode): \(body.prefix(100))")
            }
        } catch let error as URLError where error.code == .timedOut {
            return EvalResult(signal: .neutral, confidence: 0, reason: "API request timed out (30s)")
        } catch {
            return EvalResult(signal: .neutral, confidence: 0, reason: "Request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - API Key Management

    func saveAPIKey(_ key: String) {
        KeychainHelper.save(key, for: keychainKey)
    }

    func deleteAPIKey() {
        KeychainHelper.delete(for: keychainKey)
    }

    func resetDailySpend() {
        todayInputTokens = 0
        todayOutputTokens = 0
    }

    // MARK: - Request Building

    private func buildRequestBody(
        bars: [Bar],
        contractName: String,
        contractId: String,
        barSize: String,
        model: String,
        tickSize: Double?,
        tickValue: Double?,
        customPrompt: String
    ) -> [String: Any] {
        // System prompt
        var systemPrompt = """
        You are a futures trading signal analyzer. Analyze the OHLCV bar data provided and call the trading_signal tool with your determination.

        Rules:
        - "buy" = high-probability long entry setup
        - "sell" = high-probability short entry setup
        - "neutral" = no clear signal or conflicting signals
        - Be conservative — when in doubt, return "neutral"
        - Do not hallucinate patterns. If data is insufficient, return "neutral"
        - Consider price action, volume patterns, support/resistance, momentum, and trend
        """

        if !customPrompt.isEmpty {
            systemPrompt += "\n\nAdditional instructions:\n\(customPrompt)"
        }

        // Compact bar JSON — round prices to 2dp, trim timestamps
        let barData = bars.map { bar -> [String: Any] in
            var entry: [String: Any] = [
                "t": bar.t.count > 19 ? String(bar.t.prefix(19)) : bar.t,
                "o": round(bar.o * 100) / 100,
                "h": round(bar.h * 100) / 100,
                "l": round(bar.l * 100) / 100,
                "c": round(bar.c * 100) / 100,
                "v": bar.v
            ]
            return entry
        }

        // User message with contract details
        var contractInfo = "Contract: \(contractName) (\(contractId))"
        if let ts = tickSize, let tv = tickValue {
            contractInfo += "\nTick size: \(ts), Tick value: $\(String(format: "%.2f", tv))"
        }
        let userMessage = """
        \(contractInfo)
        Timeframe: \(barSize) bars
        Last \(bars.count) bars (oldest → newest):
        """

        // Tool definition
        let tool: [String: Any] = [
            "name": "trading_signal",
            "description": "Return a trading signal based on the bar data analysis",
            "input_schema": [
                "type": "object",
                "properties": [
                    "signal": [
                        "type": "string",
                        "enum": ["buy", "sell", "neutral"],
                        "description": "The trading signal"
                    ],
                    "confidence": [
                        "type": "number",
                        "minimum": 0,
                        "maximum": 1,
                        "description": "Confidence level from 0.0 to 1.0"
                    ],
                    "reason": [
                        "type": "string",
                        "description": "Brief one-sentence explanation for the signal"
                    ]
                ],
                "required": ["signal", "confidence", "reason"]
            ] as [String: Any]
        ]

        // Build the bar data string for the user message
        let barJSON: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: barData, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            barJSON = jsonString
        } else {
            barJSON = "[]"
        }

        return [
            "model": model,
            "max_tokens": 256,
            "system": systemPrompt,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": "trading_signal"],
            "messages": [
                [
                    "role": "user",
                    "content": "\(userMessage)\n\(barJSON)"
                ]
            ]
        ] as [String: Any]
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) -> EvalResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return EvalResult(signal: .neutral, confidence: 0, reason: "Failed to parse API response")
        }

        // Track token usage
        if let usage = json["usage"] as? [String: Any] {
            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let outputTokens = usage["output_tokens"] as? Int ?? 0
            todayInputTokens += inputTokens
            todayOutputTokens += outputTokens
        }

        // Extract tool_use content block
        guard let content = json["content"] as? [[String: Any]] else {
            return EvalResult(signal: .neutral, confidence: 0, reason: "No content in API response")
        }

        guard let toolBlock = content.first(where: { ($0["type"] as? String) == "tool_use" }),
              let input = toolBlock["input"] as? [String: Any] else {
            return EvalResult(signal: .neutral, confidence: 0, reason: "No tool_use block in response")
        }

        // Parse tool input
        let signalStr = (input["signal"] as? String) ?? "neutral"
        let confidence = (input["confidence"] as? Double) ?? 0
        let reason = (input["reason"] as? String) ?? "No reason provided"

        let signal: Signal
        switch signalStr.lowercased() {
        case "buy":  signal = .buy
        case "sell": signal = .sell
        default:     signal = .neutral
        }

        return EvalResult(signal: signal, confidence: confidence, reason: reason)
    }

    // MARK: - Daily Reset

    private func resetDailyCountersIfNeeded() {
        let today = dateString(Date())
        if lastResetDate != today {
            todayInputTokens = 0
            todayOutputTokens = 0
            lastResetDate = today
        }
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
