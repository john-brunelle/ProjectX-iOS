import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Bots Tab — Bot Library
//
// List all saved bots. Tap for details.
// "+" opens the bot creation wizard.
// ─────────────────────────────────────────────

struct BotsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProjectXService.self) var service
    @Environment(BotRunner.self) var botRunner

    @Query(sort: \BotConfig.name)
    private var botsRaw: [BotConfig]

    private var bots: [BotConfig] {
        botsRaw.sorted { a, b in
            if a.isActive != b.isActive { return a.isActive }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    var isEmbedded: Bool = false

    @State private var showWizard = false
    @State private var selectedBot: BotConfig?
    @State private var showStopAllConfirmation = false
    @State private var showNuclearConfirmation = false

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
                if bots.isEmpty {
                    ContentUnavailableView(
                        "No Bots Yet",
                        systemImage: "gearshape.2.fill",
                        description: Text("Tap + to create your first trading bot.")
                    )
                } else {
                    List {
                        ForEach(bots) { bot in
                            BotRow(bot: bot, runState: botRunner.runStates[bot.id])
                                .contentShape(Rectangle())
                                .onTapGesture { selectedBot = bot }
                        }
                        .onDelete(perform: deleteBots)
                    }
                }
            }
            .navigationTitle("Bots")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showWizard = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                if botRunner.runningCount > 0 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Button(role: .destructive) {
                                showStopAllConfirmation = true
                            } label: {
                                Label("Stop All Bots", systemImage: "stop.circle.fill")
                            }
                            Button(role: .destructive) {
                                showNuclearConfirmation = true
                            } label: {
                                Label("Nuclear Stop — Bots, Orders & Positions", systemImage: "exclamationmark.octagon.fill")
                            }
                        } label: {
                            Label("Emergency", systemImage: "stop.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Stop All Bots?",
                isPresented: $showStopAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop All \(botRunner.runningCount) Bot\(botRunner.runningCount == 1 ? "" : "s")", role: .destructive) {
                    botRunner.stopAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will immediately stop all running bots. Any open positions will remain open.")
            }
            .confirmationDialog(
                "Nuclear Stop?",
                isPresented: $showNuclearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop Bots, Cancel Orders & Close Positions", role: .destructive) {
                    Task { await botRunner.nuclearStop() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will stop all bots, cancel every open order, and close every open position. This cannot be undone.")
            }
            .sheet(isPresented: $showWizard) {
                BotWizardView(existing: nil)
            }
            .sheet(item: $selectedBot) { bot in
                BotDetailView(bot: bot)
            }
    }

    private func deleteBots(at offsets: IndexSet) {
        for index in offsets {
            let bot = bots[index]
            // Stop running bots before deleting
            if botRunner.isRunning(bot) {
                botRunner.stop(bot: bot)
            }
            modelContext.delete(bot)
        }
    }
}

// MARK: - Bot Row

struct BotRow: View {
    let bot: BotConfig
    let runState: BotRunState?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bot.name)
                    .font(.headline)
                Spacer()
                Button {
                    bot.isActive.toggle()
                    bot.updatedAt = Date()
                } label: {
                    Image(systemName: bot.isActive ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(bot.isActive ? .green : .orange)
                }
                .buttonStyle(.plain)
                Label(bot.status.displayName, systemImage: bot.status.systemImage)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.fill.tertiary, in: Capsule())
            }
            HStack(spacing: 12) {
                Label(bot.contractName, systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(bot.barSizeLabel, systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(bot.indicators.count)", systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // P&L summary row
            HStack(spacing: 4) {
                Image(systemName: bot.lifetimePnL >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                Text(formatPnL(bot.lifetimePnL))
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("(\(bot.lifetimeTradeCount) trade\(bot.lifetimeTradeCount == 1 ? "" : "s"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if bot.status == .running, let state = runState, state.sessionPnL != 0 {
                    Text("· \(formatPnL(state.sessionPnL)) session")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(bot.lifetimePnL >= 0 ? Color.green : Color.red)

            // Live status when running
            if bot.status == .running, let state = runState {
                HStack(spacing: 12) {
                    // Pulsing dot
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .modifier(PulsingModifier())

                    // Last signal
                    Text(signalLabel(state.lastSignal))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(signalColor(state.lastSignal))

                    // Last poll time
                    if let pollTime = state.lastPollTime {
                        Text("Polled \(pollTime, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(bot.isActive ? 1.0 : 0.6)
    }

    private func formatPnL(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.positivePrefix = "+"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private var statusColor: Color {
        switch bot.status {
        case .running: .green
        case .paused:  .orange
        case .error:   .red
        case .stopped: .secondary
        }
    }

    private func signalLabel(_ signal: Signal) -> String {
        switch signal {
        case .buy:     "BUY"
        case .sell:    "SELL"
        case .neutral: "NEUTRAL"
        }
    }

    private func signalColor(_ signal: Signal) -> Color {
        switch signal {
        case .buy:     .green
        case .sell:    .red
        case .neutral: .secondary
        }
    }
}

// MARK: - Pulsing Animation

struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
