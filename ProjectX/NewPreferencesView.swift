import SwiftUI

// ─────────────────────────────────────────────
// Preferences Tab
//
// App appearance, notifications, theming,
// and general non-trading settings.
// ─────────────────────────────────────────────

struct PreferencesView: View {

    @Environment(ThemeManager.self) var themeManager

    // MARK: - Orientation Lock
    @AppStorage("pref_orientationLock") private var orientationLock = "auto"

    // MARK: - Notifications
    @AppStorage("pref_notifyOnStopLoss") private var notifyOnStopLoss = false
    @AppStorage("pref_notifyOnTakeProfit") private var notifyOnTakeProfit = false
    @AppStorage("pref_notifyOnOrderFill") private var notifyOnOrderFill = false
    @AppStorage("pref_notifyOnBotError") private var notifyOnBotError = false

    // MARK: - Developer Mode
    @AppStorage("pref_developerMode") private var developerMode = false
    @State private var versionTapCount = 0

    var body: some View {
        NavigationStack {
            List {
                // ── Appearance ──────────────────────
                Section {
                    NavigationLink {
                        ThemesView()
                    } label: {
                        Label("Themes", systemImage: "paintbrush.fill")
                    }
                    Picker("Orientation", selection: $orientationLock) {
                        Label("Auto", systemImage: "arrow.triangle.2.circlepath")
                            .tag("auto")
                        Label("Portrait", systemImage: "iphone")
                            .tag("portrait")
                        Label("Landscape", systemImage: "iphone.landscape")
                            .tag("landscape")
                    }
                    .onChange(of: orientationLock) { _, _ in
                        OrientationManager.apply(orientationLock)
                    }
                } header: {
                    Text("Appearance")
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

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
