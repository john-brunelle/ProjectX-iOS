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

    @Query private var allProfiles: [AccountProfile]
    @Query private var allAssignments: [AccountBotAssignment]

    @Environment(\.modelContext) private var modelContext

    @State private var path = NavigationPath()
    @State private var showStopAllConfirmation = false
    @State private var showNuclearConfirmation = false
    @State private var showStopActions = false
    @State private var showAddBotSheet = false
    @State private var editingBots = false
    @State private var draggingBotId: UUID?
    @State private var conflictHintBotId: UUID?
    @State private var selectedBot: BotConfig?

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
            .toolbar {
                if botRunner.runningCount > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showNuclearConfirmation = true
                        } label: {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("The Hub")
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
            "Stop Bots on This Account?",
            isPresented: $showStopAllConfirmation,
            titleVisibility: .visible
        ) {
            if let accountId = service.activeAccount?.id {
                let count = botRunner.runningCount(accountId: accountId)
                Button("Stop \(count) Bot\(count == 1 ? "" : "s") on This Account", role: .destructive) {
                    botRunner.stopAll(accountId: accountId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop all bots running on this account. Bots on other accounts are unaffected. Open positions will remain open.")
        }
        .confirmationDialog(
            "Stop Everything?",
            isPresented: $showNuclearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop All Bots, Cancel Orders & Close Positions", role: .destructive) {
                Task { await botRunner.nuclearStop() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop every bot, cancel every open order, and close every open position across all accounts. This cannot be undone.")
        }
        .onChange(of: botRunner.runningCount) { _, new in
            if new == 0 {
                showStopActions = false
            }
        }
        .sheet(isPresented: $showAddBotSheet) {
            if let accountId = service.activeAccount?.id {
                BotAssignmentSheet(accountId: accountId)
            }
        }
        .sheet(item: $selectedBot) { bot in
            BotDetailView(bot: bot)
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
            .contentShape(Rectangle())
            .onTapGesture { path.append(destination) }
            content()
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func card<Content: View, Trailing: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                trailing()
            }
            content()
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
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
                let alias = allProfiles.first { $0.accountId == account.id }?.alias ?? ""
                let displayName = {
                    let trimmed = alias.trimmingCharacters(in: .whitespaces)
                    return trimmed.isEmpty ? account.name : trimmed
                }()

                HStack(spacing: 12) {
                    AccountAvatar(accountId: account.id, size: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName)
                                .font(.headline)
                                .lineLimit(1)
                            if !alias.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(account.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

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
                            Text(service.contractName(for: pos.contractId))
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
                            Text(service.contractName(for: order.contractId))
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

    /// Bot IDs assigned to the currently active account.
    private var activeAccountBotIds: Set<UUID> {
        guard let accountId = service.activeAccount?.id else { return [] }
        return Set(allAssignments.filter { $0.accountId == accountId }.map(\.botId))
    }

    /// Bots assigned to the active account, sorted by their assignment sort order.
    private var sortedAccountBots: [BotConfig] {
        let accountId = service.activeAccount?.id ?? 0
        let assignments = allAssignments.filter { $0.accountId == accountId }
        let orderMap = Dictionary(uniqueKeysWithValues: assignments.map { ($0.botId, $0.sortOrder) })
        return bots
            .filter { activeAccountBotIds.contains($0.id) && !$0.isArchived && $0.isActive }
            .sorted { (orderMap[$0.id] ?? 0) < (orderMap[$1.id] ?? 0) }
    }

    private var botsCard: some View {
        card("Bots", systemImage: "gearshape.2.fill") {
            HStack(spacing: 6) {
                Button {
                    withAnimation { editingBots.toggle() }
                } label: {
                    Image(systemName: editingBots ? "checkmark.circle.fill" : "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(editingBots ? .green : .red)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .opacity(bots.contains(where: { activeAccountBotIds.contains($0.id) && !$0.isArchived }) ? 1 : 0.3)

                Button {
                    showAddBotSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        } content: {
            let accountBots = bots.filter { activeAccountBotIds.contains($0.id) && !$0.isArchived }
            if !accountBots.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sortedAccountBots.prefix(5)) { bot in
                        let activeAccountId = service.activeAccount?.id ?? 0
                        let running = botRunner.isRunning(bot, accountId: activeAccountId)
                        let state = botRunner.runState(for: bot, accountId: activeAccountId)
                        let conflictBot = running ? nil : botRunner.runningBotName(
                            on: bot.contractId, accountId: activeAccountId, excluding: bot.id)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                BotAvatar(botId: bot.id, size: 24)
                                    .overlay(alignment: .topLeading) {
                                        if running {
                                            Circle()
                                                .fill(.green)
                                                .frame(width: 8, height: 8)
                                                .background(Circle().fill(.background).padding(-1))
                                                .offset(x: -3, y: -3)
                                        }
                                    }

                                Text(bot.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(bot.contractName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                // Start / Stop button
                                if conflictBot != nil {
                                    Button {
                                        withAnimation {
                                            conflictHintBotId = conflictHintBotId == bot.id ? nil : bot.id
                                        }
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(.gray)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        if running {
                                            botRunner.stop(bot: bot, accountId: activeAccountId)
                                        } else {
                                            botRunner.start(bot: bot, accountId: activeAccountId)
                                        }
                                    } label: {
                                        Image(systemName: running ? "stop.circle.fill" : "play.circle.fill")
                                            .foregroundStyle(running ? .red : .green)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Live price + position info (only when position is open)
                            if running,
                               let quote = realtime.contractQuotes[bot.contractId],
                               let pos = realtime.livePositions.first(where: {
                                   $0.accountId == activeAccountId && $0.contractId == bot.contractId
                               }) {
                                let tick = botRunner.contractTickInfo[bot.contractId]

                                HStack(spacing: 4) {
                                    Text(pos.isLong ? "LONG" : "SHORT")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background((pos.isLong ? Color.green : Color.red).opacity(0.15))
                                        .foregroundStyle(pos.isLong ? .green : .red)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    Text("@")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(String(format: "%.2f", pos.averagePrice))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.tertiary)
                                    Text(String(format: "%.2f", quote.lastPrice))
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(quote.change >= 0 ? .green : .red)
                                    if let tick, tick.tickSize > 0 {
                                        let diff = quote.lastPrice - pos.averagePrice
                                        let dir: Double = pos.isLong ? 1 : -1
                                        let pnl = (diff / tick.tickSize) * tick.tickValue * dir
                                        Text("uP&L")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.tertiary)
                                        Text(formatPnL(pnl))
                                            .font(.caption2.weight(.bold).monospacedDigit())
                                            .foregroundStyle(pnl >= 0 ? .green : .red)
                                    }
                                    Spacer()
                                }
                            }

                            // Conflict hint — shown on tap of disabled start button
                            if conflictHintBotId == bot.id, let conflictBot {
                                Text("\"\(conflictBot)\" is already running on this contract")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                    .task(id: conflictHintBotId) {
                                        try? await Task.sleep(for: .seconds(3))
                                        withAnimation { conflictHintBotId = nil }
                                    }
                            }

                            // P&L line
                            HStack(spacing: 10) {
                                // Session — always visible
                                HStack(spacing: 3) {
                                    let todayValues: (realized: Double, unrealized: Double, trades: Int) = {
                                        // Unrealized: only when running with live data
                                        let unrealized: Double = {
                                            guard running else { return 0 }
                                            if let quote = realtime.contractQuotes[bot.contractId],
                                               let pos = realtime.livePositions.first(where: {
                                                   $0.accountId == activeAccountId && $0.contractId == bot.contractId
                                               }),
                                               let tick = botRunner.contractTickInfo[bot.contractId] {
                                                let priceDiff = quote.lastPrice - pos.averagePrice
                                                let direction: Double = pos.isLong ? 1 : -1
                                                return (priceDiff / tick.tickSize) * tick.tickValue * direction
                                            }
                                            return state?.unrealizedPnL ?? 0
                                        }()

                                        // Realized: tag-matched + accumulated order IDs (survives REST refresh)
                                        let realized: Double = {
                                            if realtime.isUserConnected {
                                                let botPrefix = bot.tagPrefix
                                                let tagIds = Set(realtime.liveOrders
                                                    .filter { $0.accountId == activeAccountId && ($0.customTag?.hasPrefix(botPrefix) == true) }
                                                    .map(\.id))
                                                let allIds = tagIds.union(state?.placedOrderIds ?? [])
                                                let matched = realtime.liveTrades.filter {
                                                    allIds.contains($0.orderId) && !$0.voided && $0.profitAndLoss != nil
                                                }
                                                return matched.compactMap(\.profitAndLoss).reduce(0, +)
                                            }
                                            return state?.todayPnL ?? 0
                                        }()

                                        let trades = state?.todayTradeCount ?? 0
                                        return (realized, unrealized, trades)
                                    }()
                                    let totalSession = todayValues.realized + todayValues.unrealized

                                    Text("Today:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatPnL(totalSession))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(totalSession >= 0 ? .green : .red)
                                    Text("(\(todayValues.trades))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }

                                // Lifetime
                                HStack(spacing: 3) {
                                    Text(running ? "Lifetime:" : "All Time:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatPnL(bot.lifetimePnL))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(bot.lifetimePnL >= 0 ? .green : .red)
                                    Text("(\(bot.lifetimeTradeCount))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            // Poll status (only while running)
                            if running, let state {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 6, height: 6)
                                        .modifier(PulsingModifier())

                                    Text(state.lastSignal == .buy ? "BUY" :
                                         state.lastSignal == .sell ? "SELL" : "NEUTRAL")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(
                                            state.lastSignal == .buy ? .green :
                                            state.lastSignal == .sell ? .red : .secondary
                                        )

                                    if let pollTime = state.lastPollTime {
                                        Text("Polled \(pollTime, style: .relative) ago")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(running ? Color.green.opacity(0.05) : Color.clear)
                                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        )
                        .overlay(alignment: .topLeading) {
                            if editingBots {
                                Button {
                                    withAnimation { unassignBot(bot) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.white, .red)
                                        .font(.body)
                                }
                                .buttonStyle(.plain)
                                .offset(x: -8, y: -8)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if !editingBots { selectedBot = bot } }
                        .opacity(draggingBotId == bot.id ? 0.5 : 1)
                        .draggable(bot.id.uuidString) {
                            // Drag preview
                            Text(bot.name)
                                .padding(8)
                                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedIdString = items.first,
                                  let draggedId = UUID(uuidString: draggedIdString),
                                  draggedId != bot.id else { return false }
                            reorderBot(draggedId: draggedId, targetId: bot.id)
                            return true
                        } isTargeted: { targeted in
                            // Optional: could highlight drop target
                        }
                    }

                    let activeBots = accountBots.filter(\.isActive)
                    if activeBots.count > 5 {
                        Text("+\(activeBots.count - 5) more bots")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if botRunner.runningCount > 0 {
                        Divider()

                        // Emergency stop
                        Button(role: .destructive) {
                            showNuclearConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 8))
                                Text("Stop All")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red.opacity(0.6))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
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

    private func moveBots(from source: IndexSet, to destination: Int) {
        let accountId = service.activeAccount?.id ?? 0
        var ordered = sortedAccountBots.prefix(5).map(\.id)
        ordered.move(fromOffsets: source, toOffset: destination)

        // Update sort order on each assignment
        for (index, botId) in ordered.enumerated() {
            if let assignment = allAssignments.first(where: { $0.botId == botId && $0.accountId == accountId }) {
                assignment.sortOrder = index
            }
        }
        // Also update any bots beyond the visible 5
        let allSorted = sortedAccountBots
        if allSorted.count > 5 {
            for i in 5..<allSorted.count {
                if let assignment = allAssignments.first(where: { $0.botId == allSorted[i].id && $0.accountId == accountId }) {
                    assignment.sortOrder = i
                }
            }
        }
        try? modelContext.save()
    }

    private func reorderBot(draggedId: UUID, targetId: UUID) {
        let accountId = service.activeAccount?.id ?? 0
        var ordered = sortedAccountBots.prefix(5).map(\.id)
        guard let fromIndex = ordered.firstIndex(of: draggedId),
              let toIndex = ordered.firstIndex(of: targetId) else { return }
        ordered.remove(at: fromIndex)
        ordered.insert(draggedId, at: toIndex)

        for (index, botId) in ordered.enumerated() {
            if let assignment = allAssignments.first(where: { $0.botId == botId && $0.accountId == accountId }) {
                assignment.sortOrder = index
            }
        }
        try? modelContext.save()
    }

    private func unassignBot(_ bot: BotConfig) {
        let activeAccountId = service.activeAccount?.id ?? 0
        if botRunner.isRunning(bot, accountId: activeAccountId) {
            botRunner.stop(bot: bot, accountId: activeAccountId)
        }
        if let assignment = allAssignments.first(where: { $0.botId == bot.id && $0.accountId == activeAccountId }) {
            modelContext.delete(assignment)
            try? modelContext.save()
        }
    }

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
