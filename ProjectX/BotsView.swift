import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Bots Tab — Bot Library
//
// List all saved bots. Tap for details.
// "+" opens the bot creation wizard.
// ─────────────────────────────────────────────

private enum BotFilter: String, CaseIterable {
    case active   = "Active"
    case inactive = "Inactive"
    case archived = "Archived"
}

struct BotsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProjectXService.self) var service
    @Environment(BotRunner.self) var botRunner

    @Query(sort: \BotConfig.name)
    private var botsRaw: [BotConfig]

    @Query private var allAssignments: [AccountBotAssignment]

    var isEmbedded: Bool = false

    @State private var filter: BotFilter = .active
    @State private var showWizard = false
    @State private var selectedBot: BotConfig?
    @State private var showStopAllConfirmation = false
    @State private var showNuclearConfirmation = false

    private var filteredBots: [BotConfig] {
        let base: [BotConfig]
        switch filter {
        case .active:   base = botsRaw.filter {  $0.isActive && !$0.isArchived }
        case .inactive: base = botsRaw.filter { !$0.isActive && !$0.isArchived }
        case .archived: base = botsRaw.filter {  $0.isArchived }
        }
        return base.sorted { a, b in
            if filter == .active, a.isActive != b.isActive { return a.isActive }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if botsRaw.isEmpty {
                ContentUnavailableView(
                    "No Bots Yet",
                    systemImage: "gearshape.2.fill",
                    description: Text("Tap + to create your first trading bot.")
                )
            } else {
                List {
                    Section {
                        Picker("Filter", selection: $filter) {
                            ForEach(BotFilter.allCases, id: \.self) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    if filteredBots.isEmpty {
                        Section {
                            Text(emptyMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        }
                    } else {
                        Section {
                            ForEach(filteredBots) { bot in
                                BotRow(bot: bot, runState: botRunner.runStates[bot.id],
                                       accountNames: accountNames(for: bot))
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedBot = bot }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if filter == .archived {
                                            Button {
                                                unarchiveBot(bot)
                                            } label: {
                                                Label("Unarchive", systemImage: "arrow.uturn.backward")
                                            }
                                            .tint(.blue)
                                        } else {
                                            Button(role: .destructive) {
                                                archiveBot(bot)
                                            } label: {
                                                Label("Archive", systemImage: "archivebox")
                                            }
                                        }
                                    }
                            }
                        }
                    }
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

    private var emptyMessage: String {
        switch filter {
        case .active:   return "No active bots. Create one with + or activate an existing bot."
        case .inactive: return "No inactive bots."
        case .archived: return "No archived bots."
        }
    }

    private func archiveBot(_ bot: BotConfig) {
        if botRunner.isRunning(bot) { botRunner.stop(bot: bot) }
        bot.isArchived = true
        bot.isActive = false
        bot.updatedAt = Date()
        try? modelContext.save()
    }

    private func accountNames(for bot: BotConfig) -> [String] {
        let assignedIds = allAssignments.filter { $0.botId == bot.id }.map(\.accountId)
        return service.accounts.filter { assignedIds.contains($0.id) }.map(\.name)
    }

    private func unarchiveBot(_ bot: BotConfig) {
        bot.isArchived = false
        bot.updatedAt = Date()
        try? modelContext.save()
    }
}

// MARK: - Bot Row

struct BotRow: View {
    let bot: BotConfig
    let runState: BotRunState?
    var accountNames: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                bot.isActive.toggle()
                bot.updatedAt = Date()
            } label: {
                BotAvatar(botId: bot.id, size: 40)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: bot.isActive ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 16))
                            .foregroundStyle(bot.isActive ? .green : .orange)
                            .background(Circle().fill(.background).padding(1))
                            .offset(x: 4, y: -4)
                    }
            }
            .buttonStyle(.plain)

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
            if !accountNames.isEmpty {
                Text(accountNames.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
