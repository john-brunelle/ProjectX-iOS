import SwiftUI

// ─────────────────────────────────────────────
// Preferences Tab
//
// App-wide settings: rate limits, risk guards,
// bot defaults, and notification preferences.
// ─────────────────────────────────────────────

struct PreferencesView: View {

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
    @AppStorage("pref_closePositionsOnStop") private var closePositionsOnStop = false
    @AppStorage("pref_cancelOrdersOnStop") private var cancelOrdersOnStop = false

    // MARK: - Rate Limiter
    @AppStorage("pref_enableRateLimiter") private var enableRateLimiter = true

    // MARK: - Developer Mode
    @AppStorage("pref_developerMode") private var developerMode = false
    @State private var versionTapCount = 0

    // MARK: - Notifications
    @AppStorage("pref_notifyOnStopLoss") private var notifyOnStopLoss = false
    @AppStorage("pref_notifyOnTakeProfit") private var notifyOnTakeProfit = false
    @AppStorage("pref_notifyOnOrderFill") private var notifyOnOrderFill = false
    @AppStorage("pref_notifyOnBotError") private var notifyOnBotError = false

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
                    Toggle("Auto-Restore Bots on Launch", isOn: $autoRestoreBots)
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

                // ── Notifications ────────────────────
                Section {
                    Toggle("Stop Loss Hit", isOn: $notifyOnStopLoss)
                    Toggle("Take Profit Hit", isOn: $notifyOnTakeProfit)
                    Toggle("Order Fills", isOn: $notifyOnOrderFill)
                    Toggle("Bot Errors", isOn: $notifyOnBotError)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Control which events trigger local notifications.")
                }
                .onChange(of: notifyOnStopLoss) { _, new in if new { NotificationService.shared.requestPermissionIfNeeded() } }
                .onChange(of: notifyOnTakeProfit) { _, new in if new { NotificationService.shared.requestPermissionIfNeeded() } }
                .onChange(of: notifyOnOrderFill) { _, new in if new { NotificationService.shared.requestPermissionIfNeeded() } }
                .onChange(of: notifyOnBotError) { _, new in if new { NotificationService.shared.requestPermissionIfNeeded() } }

                // ── About ───────────────────────────
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !developerMode {
                            versionTapCount += 1
                            if versionTapCount >= 5 {
                                developerMode = true
                                versionTapCount = 0
                            }
                        }
                    }

                    if developerMode {
                        Toggle("Developer Mode", isOn: $developerMode)
                    }
                } header: {
                    Text("About")
                } footer: {
                    if !developerMode && versionTapCount > 0 {
                        Text("\(5 - versionTapCount) taps remaining")
                    }
                }
            }
            .navigationTitle("Preferences")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
