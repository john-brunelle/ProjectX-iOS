import SwiftUI

// ─────────────────────────────────────────────
// Controls Tab
//
// Bot/trading settings: rate limits, risk guards,
// bot defaults, and stop behavior.
// ─────────────────────────────────────────────

struct ControlsView: View {

    // MARK: - Risk Guards
    @AppStorage("pref_maxOpenPositions") private var maxOpenPositions = 5
    @AppStorage("pref_maxDailyLoss") private var maxDailyLoss = 500.0
    @AppStorage("pref_enableDailyLossLimit") private var enableDailyLossLimit = false

    // MARK: - Bot Defaults
    @AppStorage("pref_defaultStopLossTicks") private var defaultStopLossTicks = 10
    @AppStorage("pref_defaultTakeProfitTicks") private var defaultTakeProfitTicks = 20
    @AppStorage("pref_defaultQuantity") private var defaultQuantity = 1
    @AppStorage("pref_autoRestoreBots") private var autoRestoreBots = true

    // MARK: - Bot Stop Behavior
    @AppStorage("pref_closePositionsOnStop") private var closePositionsOnStop = true
    @AppStorage("pref_cancelOrdersOnStop") private var cancelOrdersOnStop = true

    // MARK: - Rate Limiter
    @AppStorage("pref_enableRateLimiter") private var enableRateLimiter = true


    var body: some View {
        NavigationStack {
            List {
                // ── Rate Limits ──────────────────────
                Section {
                    HStack {
                        Text("Bars Feed")
                        Spacer()
                        Text("50 requests / 30 sec")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("All Other Endpoints")
                        Spacer()
                        Text("200 requests / 60 sec")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Enable Rate Limiter", isOn: $enableRateLimiter)
                } header: {
                    Text("Rate Limits")
                } footer: {
                    Text("Exceeding these limits will result in errors from the API. These limits are subject to change. The rate limiter throttles outgoing requests to stay within these limits.")
                }

                // ── Risk Guards ──────────────────────
                Section {
                    Stepper("Max Open Positions: \(maxOpenPositions)",
                            value: $maxOpenPositions, in: 1...50)
                    Toggle("Enable Daily Loss Limit", isOn: $enableDailyLossLimit)
                    if enableDailyLossLimit {
                        HStack {
                            Text("Max Daily Loss")
                            Spacer()
                            TextField("Amount", value: $maxDailyLoss, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                    }
                } header: {
                    Text("Risk Guards")
                } footer: {
                    Text("Safety limits to prevent excessive exposure. Bots will not open new positions beyond these limits.")
                }

                // ── Bot Defaults ─────────────────────
                Section {
                    Stepper("Stop Loss: \(defaultStopLossTicks) ticks",
                            value: $defaultStopLossTicks, in: 1...500)
                    Stepper("Take Profit: \(defaultTakeProfitTicks) ticks",
                            value: $defaultTakeProfitTicks, in: 1...500)
                    Stepper("Quantity: \(defaultQuantity)",
                            value: $defaultQuantity, in: 1...100)
                } header: {
                    Text("Bot Defaults")
                } footer: {
                    Text("Default values used when creating new bots. Auto-restore resumes running bots after an app restart.")
                }

                // ── Bot Stop Behavior ──────────────────
                Section {
                    Toggle("Close Positions on Bot Stop", isOn: $closePositionsOnStop)
                    Toggle("Cancel Orders on Bot Stop", isOn: $cancelOrdersOnStop)
                } header: {
                    Text("Bot Stop Behavior")
                } footer: {
                    Text("When enabled, stopping a bot will automatically close any open positions and/or cancel pending orders on that contract.")
                }

                // ── Claude AI ──────────────────────────
                ClaudeAISettingsSection()

            }
            .navigationTitle("Controls")
        }
    }

}

// ── Claude AI Settings Section ────────────────

struct ClaudeAISettingsSection: View {
    @AppStorage("pref_claude_ai_enabled") private var claudeEnabled = true
    @AppStorage("pref_claude_daily_spend_limit") private var dailySpendLimit = 10.0

    @State private var apiKeyInput: String = ""
    @State private var hasKey: Bool = false

    private let service = ClaudeAIService.shared

    var body: some View {
        Section {
            Toggle("Enable Claude AI", isOn: $claudeEnabled)

            // API Key
            if hasKey {
                HStack {
                    Label("API Key", systemImage: "key.fill")
                    Spacer()
                    Text("••••••••")
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        service.deleteAPIKey()
                        hasKey = false
                        apiKeyInput = ""
                    } label: {
                        Text("Remove")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Anthropic API Key", text: $apiKeyInput)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !apiKeyInput.isEmpty {
                        Button("Save API Key") {
                            service.saveAPIKey(apiKeyInput.trimmingCharacters(in: .whitespaces))
                            hasKey = true
                            apiKeyInput = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            // Daily spend limit
            HStack {
                Text("Daily Spend Limit")
                Spacer()
                TextField("Limit", value: $dailySpendLimit, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }

            // Today's usage
            HStack {
                Text("Today's Estimated Spend")
                    .foregroundStyle(.secondary)
                Spacer()
                let spend = service.estimatedDailySpend
                Text(spend, format: .currency(code: "USD"))
                    .foregroundStyle(spend >= dailySpendLimit ? .red : .secondary)
            }

            HStack {
                Text("Tokens Today")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Text("In: \(service.todayInputTokens.formatted())  Out: \(service.todayOutputTokens.formatted())")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if service.estimatedDailySpend > 0 {
                Button("Reset Daily Usage") {
                    service.resetDailySpend()
                }
                .font(.caption)
            }
        } header: {
            Text("Claude AI")
        } footer: {
            Text("Claude AI indicators send bar data to Anthropic's API for AI-powered signal analysis. Requires an API key from console.anthropic.com. Costs vary by model — Haiku ~$0.002/call, Sonnet ~$0.009/call.")
        }
        .onAppear {
            hasKey = service.hasAPIKey
        }
    }
}
