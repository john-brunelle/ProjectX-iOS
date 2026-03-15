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

    @Query(sort: \BotConfig.updatedAt, order: .reverse)
    private var bots: [BotConfig]

    @State private var showWizard = false
    @State private var selectedBot: BotConfig?

    var body: some View {
        NavigationStack {
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
            }
            .sheet(isPresented: $showWizard) {
                BotWizardView(existing: nil)
            }
            .sheet(item: $selectedBot) { bot in
                BotDetailView(bot: bot)
            }
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
