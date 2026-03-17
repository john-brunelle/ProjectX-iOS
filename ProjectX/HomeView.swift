import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Home Dashboard — Overview Tab
//
// Single-screen snapshot of all key app data:
// market status, account, positions, orders,
// trades, bots, and live quote. Each card
// pushes its destination onto the NavigationStack
// so the back button returns to Home naturally.
// ─────────────────────────────────────────────

enum HomeDestination: Hashable {
    case accounts
    case positions
    case orders
    case trades
    case bots
    case live
    case indicators
}

struct HomeView: View {
    @Environment(ProjectXService.self) var service
    @Environment(RealtimeService.self) var realtime
    @Environment(BotRunner.self) var botRunner

    @Query(sort: \BotConfig.updatedAt, order: .reverse)
    private var bots: [BotConfig]

    @State private var path = NavigationPath()
    @State private var showStopAllConfirmation = false
    @State private var showNuclearConfirmation = false
    @State private var showStopActions = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    // ── Row 1: Market & Connection ──
                    statusRow

                    // ── Account ─────────────────────
                    accountCard

                    // ── Today's P&L ─────────────────
                    todayPnLCard

                    // ── Bots ────────────────────────
                    botsCard

                    // ── Positions ───────────────────
                    positionsCard

                    // ── Open Orders ─────────────────
                    openOrdersCard

                    // ── Quick Quote ─────────────────
                    quoteCard
                }
                .padding()
            }
            .refreshable {
                await realtime.refreshHomeData()
            }
            .task {
                while !Task.isCancelled {
                    await realtime.refreshHomeData()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await realtime.refreshHomeData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .accounts:   AccountsTab(isEmbedded: true)
                case .positions:  PositionsView(isEmbedded: true)
                case .orders:     OrdersView(isEmbedded: true)
                case .trades:     TradesView(isEmbedded: true)
                case .bots:       BotsView(isEmbedded: true)
                case .live:       LiveDashboardView(isEmbedded: true)
                case .indicators: IndicatorsView(isEmbedded: true)
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
    }

    // ═══════════════════════════════════════════
    // MARK: - Card Builder
    // ═══════════════════════════════════════════

    @ViewBuilder
    private func card<Content: View>(
        _ title: String,
        systemImage: String,
        destination: HomeDestination,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            content()
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { path.append(destination) }
    }

    // ═══════════════════════════════════════════
    // MARK: - Status Row (Market + Connection)
    // ═══════════════════════════════════════════

    private var statusRow: some View {
        HStack(spacing: 12) {
            // Market status
            HStack(spacing: 6) {
                Circle()
                    .fill(isMarketOpen ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(isMarketOpen ? "Market Open" : "Market Closed")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.fill.tertiary, in: Capsule())

            Spacer()

            // Connection indicators
            HStack(spacing: 8) {
                connectionDot("User", connected: realtime.isUserConnected)
                connectionDot("Market", connected: realtime.isMarketConnected)
            }
        }
    }

    private func connectionDot(_ label: String, connected: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connected ? .green : .gray)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Account Card
    // ═══════════════════════════════════════════

    private var accountCard: some View {
        card("Account", systemImage: "person.crop.rectangle", destination: .accounts) {
            if let account = service.activeAccount {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name)
                            .font(.headline)
                        HStack(spacing: 8) {
                            Label(
                                account.canTrade ? "Can Trade" : "No Trading",
                                systemImage: account.canTrade ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(account.canTrade ? .green : .red)
                        }
                    }
                    Spacer()
                    Text(account.balance, format: .currency(code: "USD"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(account.balance >= 0 ? .green : .red)
                }
            } else {
                Text("No account loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Positions Card
    // ═══════════════════════════════════════════

    private var positionsCard: some View {
        card("Positions", systemImage: "chart.bar.fill", destination: .positions) {
            if realtime.livePositions.isEmpty {
                Text("No open positions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(realtime.livePositions) { pos in
                        HStack {
                            Text(pos.typeLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(pos.isLong ? .green : .red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (pos.isLong ? Color.green : Color.red).opacity(0.15),
                                    in: Capsule()
                                )
                            Text(pos.contractId)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(pos.size) @ \(String(format: "%.2f", pos.averagePrice))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Today's P&L Card
    // ═══════════════════════════════════════════

    /// Completed trades: non-voided, non-half-turn (has a P&L value).
    /// Matches TradesView's definition so the numbers stay in sync.
    private var completedTrades: [Trade] {
        realtime.liveTrades.filter { !$0.voided && $0.profitAndLoss != nil }
    }

    private var todayGrossPnL: Double {
        completedTrades.compactMap(\.profitAndLoss).reduce(0, +)
    }

    private var todayFees: Double {
        realtime.liveTrades.map(\.fees).reduce(0, +)
    }

    /// Net P&L = Gross P&L − Fees (matches broker/backend figure)
    private var todayNetPnL: Double {
        todayGrossPnL - todayFees
    }

    private var todayPnLCard: some View {
        card("Today's P&L", systemImage: "dollarsign.circle", destination: .trades) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(todayNetPnL, format: .currency(code: "USD"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(todayNetPnL >= 0 ? .green : .red)
                    HStack(spacing: 12) {
                        Text("Gross: \(todayGrossPnL, format: .currency(code: "USD"))")
                        Text("Fees: \(todayFees, format: .currency(code: "USD"))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(completedTrades.count) fills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Open Orders Card
    // ═══════════════════════════════════════════

    private var openOrders: [Order] {
        realtime.liveOrders.filter { $0.status == 1 }
    }

    private var openOrdersCard: some View {
        card("Open Orders", systemImage: "list.bullet.rectangle", destination: .orders) {
            if openOrders.isEmpty {
                Text("No open orders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(openOrders.prefix(5)) { order in
                        HStack {
                            Text(order.sideLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(order.side == 0 ? .green : .red)
                            Text(order.typeLabel)
                                .font(.caption)
                            Text(order.contractId)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(order.size)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if openOrders.count > 5 {
                        Text("+\(openOrders.count - 5) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Bots Card
    // ═══════════════════════════════════════════

    private var botsCard: some View {
        card("Bots", systemImage: "gearshape.2.fill", destination: .bots) {
            if bots.isEmpty {
                Text("No bots configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(bots.filter(\.isActive).sorted { a, _ in botRunner.isRunning(a) }.prefix(5)) { bot in
                        let running = botRunner.isRunning(bot)
                        let state = botRunner.runStates[bot.id]
                        let conflictBot = running ? nil : botRunner.runningBotName(
                            on: bot.contractId, accountId: bot.accountId, excluding: bot.id)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // Pulsing dot when running
                                Circle()
                                    .fill(running ? .green : .gray.opacity(0.4))
                                    .frame(width: 8, height: 8)

                                Text(bot.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(bot.contractName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if running, let state {
                                    Text(state.lastSignal == .buy ? "BUY" :
                                         state.lastSignal == .sell ? "SELL" : "—")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(
                                            state.lastSignal == .buy ? .green :
                                            state.lastSignal == .sell ? .red : .secondary
                                        )
                                }

                                Spacer()

                                // Start / Stop button
                                Button {
                                    if running {
                                        botRunner.stop(bot: bot)
                                    } else {
                                        botRunner.start(bot: bot)
                                    }
                                } label: {
                                    Image(systemName: running ? "stop.circle.fill" : "play.circle.fill")
                                        .foregroundStyle(running ? .red : (conflictBot != nil ? .gray : .green))
                                }
                                .buttonStyle(.plain)
                                .disabled(conflictBot != nil)
                            }

                            // Conflict hint
                            if let conflictBot {
                                Text("\"\(conflictBot)\" is already running on this contract")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            // P&L line
                            HStack(spacing: 10) {
                                // Session (only while running)
                                if running, let state {
                                    HStack(spacing: 3) {
                                        Text("Session:")
                                            .foregroundStyle(.secondary)
                                        Text(formatPnL(state.sessionPnL))
                                            .foregroundStyle(state.sessionPnL >= 0 ? .green : .red)
                                            .fontWeight(.semibold)
                                        Text("(\(state.sessionTradeCount))")
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                // Lifetime
                                HStack(spacing: 3) {
                                    Text(running ? "Lifetime:" : "All Time:")
                                        .foregroundStyle(.secondary)
                                    Text(formatPnL(bot.lifetimePnL))
                                        .foregroundStyle(bot.lifetimePnL >= 0 ? .green : .red)
                                        .fontWeight(.semibold)
                                    Text("(\(bot.lifetimeTradeCount))")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .font(.caption2)
                        }
                    }
                    let activeBots = bots.filter(\.isActive)
                    if activeBots.count > 5 {
                        Text("+\(activeBots.count - 5) more bots")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    // Disclosure header — always visible
                    HStack {
                        Text("Stop Actions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showStopActions ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: showStopActions)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { showStopActions.toggle() }
                    }

                    if showStopActions {
                        VStack(spacing: 8) {
                            // Stop bots only
                            Button(role: .destructive) {
                                showStopAllConfirmation = true
                            } label: {
                                Label(
                                    "Stop All Bots (\(botRunner.runningCount) Running)",
                                    systemImage: "stop.circle.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(botRunner.runningCount > 0 ? .red : .secondary)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(botRunner.runningCount == 0)

                            // Nuclear stop — bots + orders + positions
                            Button(role: .destructive) {
                                showNuclearConfirmation = true
                            } label: {
                                Label(
                                    "Nuclear Stop — Bots, Orders & Positions",
                                    systemImage: "exclamationmark.octagon.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(botRunner.runningCount > 0 ? .orange : .secondary)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(botRunner.runningCount == 0)
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Quick Quote Card
    // ═══════════════════════════════════════════

    private var quoteCard: some View {
        card("Quick Quote", systemImage: "dot.radiowaves.left.and.right", destination: .live) {
            if let q = realtime.currentQuote {
                VStack(spacing: 6) {
                    HStack {
                        Text(q.symbolName)
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(String(format: "%.2f", q.lastPrice))
                            .font(.title3.weight(.bold))
                    }
                    HStack {
                        Text("Bid: \(String(format: "%.2f", q.bestBid))")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Ask: \(String(format: "%.2f", q.bestAsk))")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: q.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                            Text("\(String(format: "%.2f", q.change)) (\(String(format: "%.2f", q.changePercent))%)")
                                .font(.caption2)
                        }
                        .foregroundStyle(q.change >= 0 ? .green : .red)
                    }
                    HStack {
                        Text("O: \(String(format: "%.2f", q.open))  H: \(String(format: "%.2f", q.high))  L: \(String(format: "%.2f", q.low))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Vol: \(Int(q.volume))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No market data — connect to a contract in the Live tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Helpers
    // ═══════════════════════════════════════════

    private func formatPnL(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.positivePrefix = "+"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    // ═══════════════════════════════════════════
    // MARK: - Market Hours Heuristic
    // ═══════════════════════════════════════════

    /// CME Globex futures hours: Sunday 5:00 PM – Friday 4:00 PM CT,
    /// with a daily maintenance break 4:00 PM – 5:00 PM CT (Mon–Thu).
    private var isMarketOpen: Bool {
        let ct = TimeZone(identifier: "America/Chicago")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ct
        let now = Date()

        let weekday = cal.component(.weekday, from: now) // 1=Sun, 7=Sat
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let time = hour * 60 + minute // minutes since midnight

        // Saturday: always closed
        if weekday == 7 { return false }

        // Sunday: open after 5 PM CT (17:00 = 1020 min)
        if weekday == 1 { return time >= 1020 }

        // Friday: open until 4 PM CT (16:00 = 960 min)
        if weekday == 6 { return time < 960 }

        // Mon–Thu: open except daily break 4:00 PM – 5:00 PM CT
        return time < 960 || time >= 1020
    }
}
