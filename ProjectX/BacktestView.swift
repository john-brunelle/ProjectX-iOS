import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Backtest Tab — Historical Simulation
//
// Select a bot, configure date range, run
// backtest, view P&L statistics and trade list.
// ─────────────────────────────────────────────

// MARK: - View Model

@MainActor
@Observable
class BacktestViewModel {
    var selectedBot: BotConfig?
    var daysBack: Int = 30
    var barLimit: Int = 5000

    var isLoading = false
    var result: BacktestResult?
    var errorMessage: String?
    var fetchedBarCount: Int = 0

    func runBacktest(service: ProjectXService) async {
        guard let bot = selectedBot else { return }
        guard !bot.indicators.isEmpty else {
            errorMessage = "Bot has no indicators configured."
            return
        }

        isLoading = true
        result = nil
        errorMessage = nil

        // Fetch contract for tick size / tick value
        guard let contract = await service.contractById(bot.contractId) else {
            errorMessage = "Could not load contract details."
            isLoading = false
            return
        }

        // Fetch historical bars
        let bars = await service.retrieveBarsForBot(bot, daysBack: daysBack, limit: barLimit)
        fetchedBarCount = bars.count

        guard !bars.isEmpty else {
            errorMessage = "No bars returned for the selected configuration."
            isLoading = false
            return
        }

        // Build parameters and run engine
        let parameters = BacktestParameters(
            bars: bars,
            indicatorConfigs: bot.indicators,
            quantity: bot.quantity,
            stopLossTicks: bot.stopLossTicks,
            takeProfitTicks: bot.takeProfitTicks,
            tickSize: contract.tickSize,
            tickValue: contract.tickValue,
            tradeDirection: bot.tradeDirection
        )

        result = BacktestEngine.run(parameters: parameters)
        isLoading = false
    }
}

// MARK: - Backtest View

struct BacktestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProjectXService.self) var service

    @Query(sort: \BotConfig.updatedAt, order: .reverse)
    private var bots: [BotConfig]

    @State private var vm = BacktestViewModel()
    @State private var showEditWizard = false
    @State private var showIndicatorLibrary = false

    var body: some View {
        NavigationStack {
            Form {
                // ── Bot Selection ────────────
                Section("Select Bot") {
                    if bots.isEmpty {
                        Text("No bots available. Create one in the Bots tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Bot", selection: $vm.selectedBot) {
                            Text("Choose a bot").tag(nil as BotConfig?)
                            ForEach(bots) { bot in
                                Text("\(bot.name) — \(bot.contractName)")
                                    .tag(bot as BotConfig?)
                            }
                        }
                    }
                }

                // ── Bot Info (when selected) ─
                if let bot = vm.selectedBot {
                    Section("Bot Configuration") {
                        LabeledContent("Contract", value: bot.contractName)
                        LabeledContent("Bar Size", value: bot.barSizeLabel)
                        LabeledContent("Quantity", value: "\(bot.quantity)")
                        LabeledContent("Indicators", value: "\(bot.indicators.count)")
                        LabeledContent("Stop Loss",
                                       value: bot.stopLossTicks.map { "\($0) ticks" } ?? "None")
                        LabeledContent("Take Profit",
                                       value: bot.takeProfitTicks.map { "\($0) ticks" } ?? "None")
                        LabeledContent("Direction", value: bot.tradeDirection.displayName)

                        Button {
                            showEditWizard = true
                        } label: {
                            Label("Edit Bot", systemImage: "pencil")
                        }

                        Button {
                            showIndicatorLibrary = true
                        } label: {
                            Label("Edit Indicators", systemImage: "waveform.path.ecg")
                        }
                    }
                }

                // ── Configuration ────────────
                Section("Backtest Settings") {
                    Stepper("Days Back: \(vm.daysBack)", value: $vm.daysBack, in: 1...365)
                    Stepper("Bar Limit: \(vm.barLimit)", value: $vm.barLimit, in: 100...20000, step: 100)
                }

                // ── Run ──────────────────────
                Section {
                    Button {
                        Task { await vm.runBacktest(service: service) }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Running Backtest...")
                            } else {
                                Label("Run Backtest", systemImage: "play.fill")
                            }
                            Spacer()
                        }
                        .font(.headline)
                    }
                    .disabled(vm.selectedBot == nil || vm.isLoading)

                    if vm.result != nil {
                        Button(role: .destructive) {
                            vm.result = nil
                            vm.errorMessage = nil
                            vm.fetchedBarCount = 0
                        } label: {
                            HStack {
                                Spacer()
                                Label("Clear Results", systemImage: "xmark.circle")
                                Spacer()
                            }
                        }
                    }
                }

                // ── Error ────────────────────
                if let error = vm.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                // ── Results ──────────────────
                if let result = vm.result {
                    Section {
                        Text("Analyzed \(vm.fetchedBarCount) bars — \(result.trades.count) trades found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    statisticsSection(result.statistics)
                    tradeListSection(result.trades)
                }
            }
            .navigationTitle("Backtest")
            .sheet(isPresented: $showEditWizard) {
                if let bot = vm.selectedBot {
                    BotWizardView(existing: bot)
                }
            }
            .sheet(isPresented: $showIndicatorLibrary) {
                IndicatorsView(onDone: { showIndicatorLibrary = false })
            }
        }
    }

    // MARK: - Statistics Section

    private func statisticsSection(_ stats: BacktestStatistics) -> some View {
        Section("Summary") {
            statRow("Total P&L",
                    value: formatCurrency(stats.totalPnL),
                    color: stats.totalPnL >= 0 ? .green : .red)
            statRow("Total Trades", value: "\(stats.totalTrades)")
            statRow("Win Rate", value: formatPercent(stats.winRate),
                    color: stats.winRate >= 0.5 ? .green : .red)
            statRow("Longs", value: "\(stats.longTrades) — \(formatPercent(stats.longWinRate)) win",
                    color: stats.longWinRate >= 0.5 ? .green : .red)
            statRow("Shorts", value: "\(stats.shortTrades) — \(formatPercent(stats.shortWinRate)) win",
                    color: stats.shortWinRate >= 0.5 ? .green : .red)
            statRow("Profit Factor", value: formatDecimal(stats.profitFactor))
            statRow("Max Drawdown",
                    value: formatCurrency(stats.maxDrawdown),
                    color: .red)
            statRow("Sharpe Ratio", value: formatDecimal(stats.sharpeRatio))
            statRow("Avg Win", value: formatCurrency(stats.averageWin), color: .green)
            statRow("Avg Loss", value: formatCurrency(stats.averageLoss), color: .red)
            statRow("Largest Win", value: formatCurrency(stats.largestWin), color: .green)
            statRow("Largest Loss", value: formatCurrency(stats.largestLoss), color: .red)
        }
    }

    private func statRow(_ label: String, value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color ?? .primary)
        }
    }

    // MARK: - Trade List Section

    private func tradeListSection(_ trades: [BacktestTrade]) -> some View {
        Section("Trades (\(trades.count))") {
            ForEach(trades) { trade in
                BacktestTradeRow(trade: trade)
            }
        }
    }

    // MARK: - Formatters

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    private func formatDecimal(_ value: Double) -> String {
        if value.isInfinite { return "∞" }
        return String(format: "%.2f", value)
    }
}

// MARK: - Trade Row

struct BacktestTradeRow: View {
    let trade: BacktestTrade

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trade.direction == .long ? "LONG" : "SHORT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(trade.direction == .long ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (trade.direction == .long ? Color.green : Color.red).opacity(0.15),
                        in: Capsule()
                    )

                Text(trade.exitReason.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(trade.pnlDollars, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(trade.pnlDollars >= 0 ? .green : .red)
            }

            HStack(spacing: 8) {
                Label(formatPrice(trade.entryPrice), systemImage: "arrow.right.circle")
                    .font(.caption2)
                Label(formatPrice(trade.exitPrice), systemImage: "arrow.left.circle")
                    .font(.caption2)
                Text("(\(String(format: "%.1f", trade.pnlTicks)) ticks)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(trade.entryTimestamp)
                Text("→")
                Text(trade.exitTimestamp)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func formatPrice(_ price: Double) -> String {
        String(format: "%.2f", price)
    }
}
