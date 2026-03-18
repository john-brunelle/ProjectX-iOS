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
                } header: {
                    Text("Rate Limits")
                } footer: {
                    Text("Exceeding these limits will result in errors from the API. These limits are subject to change.")
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
            }
            .navigationTitle("Preferences")
        }
    }
}
