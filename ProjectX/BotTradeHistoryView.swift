import SwiftUI

// ─────────────────────────────────────────────
// Bot Trade History
//
// Shows all trades placed by a specific bot,
// matched via the bot's customTag prefix on
// orders. Supports date range filtering and
// displays summary stats.
// ─────────────────────────────────────────────

struct BotTradeHistoryView: View {
    @Environment(ProjectXService.self) var service
    @Environment(\.dismiss) var dismiss

    let bot: BotConfig
    let accountId: Int

    @State private var trades: [Trade] = []
    @State private var isLoading = false
    @State private var selectedPeriod: Period = .today

    enum Period: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "7 Days"
        case month = "30 Days"

        var id: String { rawValue }

        var startDate: Date {
            switch self {
            case .today: return RealtimeService.sessionStart()
            case .week:  return Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            }
        }
    }

    // ── Computed stats ────────────────────────

    private var completedTrades: [Trade] {
        trades.filter { !$0.voided && $0.profitAndLoss != nil }
    }

    private var grossPnL: Double {
        completedTrades.compactMap(\.profitAndLoss).reduce(0, +)
    }

    private var totalFees: Double {
        trades.filter { !$0.voided }.map(\.fees).reduce(0, +)
    }

    private var netPnL: Double { grossPnL - totalFees }

    private var winCount: Int {
        completedTrades.filter { ($0.profitAndLoss ?? 0) > 0 }.count
    }

    private var winRate: Double {
        completedTrades.isEmpty ? 0 : Double(winCount) / Double(completedTrades.count) * 100
    }

    // ── Body ─────────────────────────────────

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Period picker
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(Period.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Summary card
                summaryCard
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                // Trade list
                if isLoading {
                    Spacer()
                    ProgressView("Loading trades...")
                    Spacer()
                } else if trades.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Trades",
                        systemImage: "chart.xyaxis.line",
                        description: Text("No trades found for this bot in the selected period.")
                    )
                    Spacer()
                } else {
                    List(trades) { trade in
                        TradeRow(trade: trade)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("\(bot.name) Trades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await loadTrades() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await loadTrades() }
            .onChange(of: selectedPeriod) { _, _ in
                Task { await loadTrades() }
            }
        }
    }

    // ── Summary card ─────────────────────────

    private var summaryCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                statTile("Gross P&L", value: formatPnL(grossPnL), color: grossPnL >= 0 ? .green : .red)
                Divider().frame(height: 36)
                statTile("Fees", value: formatPnL(totalFees), color: .orange)
                Divider().frame(height: 36)
                statTile("Net P&L", value: formatPnL(netPnL), color: netPnL >= 0 ? .green : .red)
            }
            HStack(spacing: 0) {
                statTile("Trades", value: "\(completedTrades.count)", color: .primary)
                Divider().frame(height: 36)
                statTile("Wins", value: "\(winCount)", color: .green)
                Divider().frame(height: 36)
                statTile("Win Rate", value: String(format: "%.0f%%", winRate), color: winRate >= 50 ? .green : .red)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statTile(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // ── Fetch ────────────────────────────────

    private func loadTrades() async {
        isLoading = true
        let start = selectedPeriod.startDate
        let botPrefix = bot.tagPrefix

        let allOrders = await service.searchOrders(
            accountId: accountId, startTimestamp: start)
        let botOrderIds = Set(allOrders
            .filter { $0.customTag?.hasPrefix(botPrefix) == true }
            .map(\.id))

        let allTrades = await service.searchTrades(
            accountId: accountId, startTimestamp: start)
        trades = allTrades
            .filter { botOrderIds.contains($0.orderId) && !$0.voided && $0.profitAndLoss != nil }
            .sorted { $0.creationTimestamp > $1.creationTimestamp }

        isLoading = false
    }

    // ── Helpers ──────────────────────────────

    private func formatPnL(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.positivePrefix = "+"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}
