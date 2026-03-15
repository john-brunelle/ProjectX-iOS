import SwiftUI

struct TradesView: View {
    @Environment(ProjectXService.self) var service

    @State private var trades:          [Trade]  = []
    @State private var isLoading                 = false
    @State private var selectedAccount: Account?
    @State private var daysBack                  = 1

    // Summary stats
    var completedTrades: [Trade] { trades.filter { !$0.isHalfTurn && !$0.voided } }
    var totalPnL:        Double  { completedTrades.compactMap { $0.profitAndLoss }.reduce(0, +) }
    var totalFees:       Double  { trades.map { $0.fees }.reduce(0, +) }
    var winCount:        Int     { completedTrades.filter { ($0.profitAndLoss ?? 0) > 0 }.count }
    var lossCount:       Int     { completedTrades.filter { ($0.profitAndLoss ?? 0) < 0 }.count }
    var winRate:         Double  {
        guard completedTrades.count > 0 else { return 0 }
        return Double(winCount) / Double(completedTrades.count) * 100
    }

    var isEmbedded: Bool = false

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
                // Account picker
                if service.accounts.count > 1 {
                    Picker("Account", selection: $selectedAccount) {
                        ForEach(service.accounts) { acct in
                            Text(acct.name).tag(Optional(acct))
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .onChange(of: selectedAccount) { _, _ in
                        Task { await reload() }
                    }
                }

                // Days back picker
                Picker("Period", selection: $daysBack) {
                    Text("Today").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onChange(of: daysBack) { _, _ in
                    Task { await reload() }
                }

                // Stats bar — always visible, shows zeros when no data
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        StatCard(title: "Net P&L",
                                 value: String(format: "$%.2f", totalPnL),
                                 color: totalPnL >= 0 ? .green : .red)
                        StatCard(title: "Win Rate",
                                 value: String(format: "%.0f%%", winRate),
                                 color: winRate >= 50 ? .green : .orange)
                        StatCard(title: "Wins / Losses",
                                 value: "\(winCount) / \(lossCount)",
                                 color: .blue)
                        StatCard(title: "Total Fees",
                                 value: String(format: "$%.2f", totalFees),
                                 color: .secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(uiColor: .secondarySystemBackground))

                if isLoading {
                    ProgressView("Loading trades...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if trades.isEmpty {
                    ContentUnavailableView(
                        "No Trades",
                        systemImage: "chart.xyaxis.line",
                        description: Text("No trades found in this period.")
                    )
                } else {
                    List(trades) { trade in
                        TradeRow(trade: trade)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Trades")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await reload() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                selectedAccount = service.accounts.first
                await reload()
            }
    }

    private func reload() async {
        guard let account = selectedAccount else { return }
        isLoading = true
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        trades = await service.searchTrades(
            accountId:      account.id,
            startTimestamp: start,
            endTimestamp:   Date()
        )
        isLoading = false
    }
}

// ── Stat Card ─────────────────────────────────

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        )
    }
}

// ── Trade Row ─────────────────────────────────

struct TradeRow: View {
    let trade: Trade

    var sideColor: Color { trade.side == 0 ? .green : .red }
    var pnlColor:  Color {
        guard let pnl = trade.profitAndLoss else { return .secondary }
        return pnl >= 0 ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trade.sideLabel)
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(sideColor.opacity(0.15))
                    .foregroundStyle(sideColor)
                    .clipShape(Capsule())
                Text(trade.contractId).font(.headline)
                Spacer()
                if let pnl = trade.profitAndLoss {
                    Text(String(format: "%+.2f", pnl))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(pnlColor)
                } else {
                    Text("Half-turn")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Label("\(trade.price, specifier: "%.2f")", systemImage: "dollarsign.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Qty: \(trade.size)", systemImage: "number")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Fee: $\(trade.fees, specifier: "%.2f")", systemImage: "minus.circle")
                    .font(.caption).foregroundStyle(.secondary)
                if trade.voided {
                    Text("VOIDED")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.red)
                }
            }
            Text(formattedTime(trade.creationTimestamp))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(trade.voided ? 0.5 : 1.0)
    }

    private func formattedTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            return df.string(from: d)
        }
        return iso
    }
}
