import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Bot Detail View
//
// Inline-editing form for a saved bot.
// All fields editable when bot is stopped.
// Lock banner + disabled fields when running.
// Start/Stop, Live Status, Activity Log unchanged.
// ─────────────────────────────────────────────

struct BotDetailView: View {
    @Environment(ProjectXService.self) var service
    @Environment(BotRunner.self) var botRunner
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let bot: BotConfig

    // ── Edit state (loaded from bot on appear) ──
    @State private var name = ""
    @State private var selectedAccount: Account?
    @State private var contractId = ""
    @State private var contractName = ""
    @State private var barUnit: BarUnit = .minute
    @State private var barUnitNumber = 5
    @State private var useStopLoss = false
    @State private var stopLossTicks = 10
    @State private var useTakeProfit = false
    @State private var takeProfitTicks = 20
    @State private var quantity = 1
    @State private var tradeDirection: TradeDirectionFilter = .both
    @State private var selectedIndicatorIDs: Set<UUID> = []

    // ── Contract search sheet ──
    @State private var showContractSearch = false
    @State private var contracts: [Contract] = []
    @State private var contractSearch = ""
    @State private var isLoadingContracts = false

    // ── Indicator management ──
    @Query(sort: \IndicatorConfig.updatedAt, order: .reverse)
    private var allIndicators: [IndicatorConfig]
    @State private var showIndicatorPicker = false
    @State private var editingIndicator: IndicatorConfig?

    // ── Backtest state ──
    @State private var daysBack = 30
    @State private var barLimit = 5000
    @State private var isBacktesting = false
    @State private var backtestResult: BacktestResult?
    @State private var backtestError: String?
    @State private var backtestBarCount = 0

    // ── Other UI state ──
    @State private var showDeleteConfirmation = false

    private var runState: BotRunState? { botRunner.runStates[bot.id] }
    private var isRunning: Bool { botRunner.isRunning(bot) }

    private var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespaces) != bot.name
        || selectedAccount?.id != bot.accountId
        || contractId != bot.contractId
        || barUnit.rawValue != bot.barUnit
        || barUnitNumber != bot.barUnitNumber
        || useStopLoss != (bot.stopLossTicks != nil)
        || stopLossTicks != (bot.stopLossTicks ?? 10)
        || useTakeProfit != (bot.takeProfitTicks != nil)
        || takeProfitTicks != (bot.takeProfitTicks ?? 20)
        || quantity != bot.quantity
        || tradeDirection != bot.tradeDirection
        || selectedIndicatorIDs != Set(bot.indicators.map { $0.id })
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSections
                configSections
                riskSections
                indicatorSections
                backtestSections
                infoAndActionSections
            }
            .navigationTitle(bot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showContractSearch) {
                ContractSearchSheet(
                    contracts: $contracts,
                    contractSearch: $contractSearch,
                    isLoading: $isLoadingContracts,
                    onSelect: { contract in
                        contractId = contract.id
                        contractName = contract.name
                        showContractSearch = false
                    },
                    onLoad: {
                        guard contracts.isEmpty else { return }
                        isLoadingContracts = true
                        contracts = await service.availableContracts(live: false)
                        isLoadingContracts = false
                    }
                )
            }
            .sheet(isPresented: $showIndicatorPicker) {
                IndicatorPickerSheet(
                    allIndicators: allIndicators,
                    selectedIDs: $selectedIndicatorIDs
                )
            }
            .sheet(item: $editingIndicator) { indicator in
                IndicatorEditorView(existing: indicator)
            }
            .confirmationDialog("Delete Bot?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if isRunning { botRunner.stop(bot: bot) }
                    modelContext.delete(bot)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(bot.name)\". This action cannot be undone.")
            }
            .onAppear { loadFromBot() }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
                .disabled(!hasChanges || isRunning)
                .opacity(hasChanges && !isRunning ? 1 : 0)
        }
    }

    // MARK: - Status Sections (Lock Banner, Start/Stop, Live Status, Activity Log)

    @ViewBuilder
    private var statusSections: some View {
        // ── Running Lock Banner ──────────────
        if isRunning {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bot is Running")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("Stop the bot to make changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }

        // ── Start / Stop ─────────────────────
        Section {
            if isRunning {
                Button(role: .destructive) {
                    botRunner.stop(bot: bot)
                } label: {
                    Label("Stop Bot", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
            } else {
                Button {
                    botRunner.start(bot: bot)
                } label: {
                    Label("Start Bot", systemImage: "play.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .disabled(bot.indicators.isEmpty)
            }
        } footer: {
            if bot.indicators.isEmpty {
                Text("Add at least one indicator before starting.")
                    .foregroundStyle(.orange)
            }
        }

        // ── Performance ──────────────────────
        performanceSection

        // ── Live Status ──────────────────────
        if let state = runState {
            Section("Live Status") {
                HStack {
                    Text("Status").foregroundStyle(.secondary)
                    Spacer()
                    Label(bot.status.displayName, systemImage: bot.status.systemImage)
                        .foregroundStyle(statusColor)
                }
                HStack {
                    Text("Last Signal").foregroundStyle(.secondary)
                    Spacer()
                    Text(signalLabel(state.lastSignal))
                        .fontWeight(.semibold)
                        .foregroundStyle(signalColor(state.lastSignal))
                }
                if let barTime = state.lastBarTime {
                    HStack {
                        Text("Last Bar").foregroundStyle(.secondary)
                        Spacer()
                        Text(barTime).font(.caption).monospaced()
                    }
                }
                if let pollTime = state.lastPollTime {
                    HStack {
                        Text("Last Poll").foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 0) {
                            Text(pollTime, style: .relative)
                            Text(" ago")
                        }
                        .font(.caption)
                    }
                }
            }
        }

        // ── Activity Log ─────────────────────
        if let state = runState, !state.log.isEmpty {
            Section("Activity Log") {
                ForEach(state.log.prefix(50)) { entry in
                    BotLogRow(entry: entry)
                }
            }
        }
    }

    // MARK: - Configuration Sections (Name, Account, Contract, Bar Size)

    @ViewBuilder
    private var configSections: some View {
        Section("Configuration") {
            TextField("Bot Name", text: $name)
                .disabled(isRunning)

            if service.accounts.isEmpty {
                Text("No accounts loaded")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Account", selection: $selectedAccount) {
                    ForEach(service.accounts) { acct in
                        Text("\(acct.name) (\(acct.id))").tag(acct as Account?)
                    }
                }
                .disabled(isRunning)
            }

            HStack {
                Text("Contract").foregroundStyle(.secondary)
                Spacer()
                Text(contractName.isEmpty ? bot.contractName : contractName)
                    .foregroundStyle(isRunning ? .secondary : .primary)
            }

            if !isRunning {
                Button("Change Contract…") {
                    showContractSearch = true
                }
                .font(.callout)
            }
        }

        Section("Bar Size") {
            Picker("Bar Unit", selection: $barUnit) {
                ForEach(BarUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .disabled(isRunning)

            Stepper("Unit Number: \(barUnitNumber)", value: $barUnitNumber, in: 1...60)
                .disabled(isRunning)
        }
    }

    // MARK: - Risk Management Sections

    @ViewBuilder
    private var riskSections: some View {
        Section("Position Size") {
            Stepper("Quantity: \(quantity)", value: $quantity, in: 1...100)
                .disabled(isRunning)
        }

        Section("Stop Loss") {
            Toggle("Enable Stop Loss", isOn: $useStopLoss)
                .disabled(isRunning)
            if useStopLoss {
                Stepper("Ticks: \(stopLossTicks)", value: $stopLossTicks, in: 1...500)
                    .disabled(isRunning)
            }
        }

        Section("Take Profit") {
            Toggle("Enable Take Profit", isOn: $useTakeProfit)
                .disabled(isRunning)
            if useTakeProfit {
                Stepper("Ticks: \(takeProfitTicks)", value: $takeProfitTicks, in: 1...500)
                    .disabled(isRunning)
            }
        }

        Section("Trade Direction") {
            Picker("Direction", selection: $tradeDirection) {
                ForEach(TradeDirectionFilter.allCases) { dir in
                    Text(dir.displayName).tag(dir)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isRunning)
        }
    }

    // MARK: - Indicator Sections

    @ViewBuilder
    private var indicatorSections: some View {
        Section("Indicators (\(selectedIndicatorIDs.count))") {
            if selectedIndicatorsList.isEmpty {
                Text("No indicators selected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedIndicatorsList) { indicator in
                    HStack {
                        IndicatorRow(indicator: indicator)
                        Spacer()
                        if !isRunning {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isRunning else { return }
                        editingIndicator = indicator
                    }
                    .swipeActions(edge: .trailing) {
                        if !isRunning {
                            Button(role: .destructive) {
                                selectedIndicatorIDs.remove(indicator.id)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            Button {
                                editingIndicator = indicator
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }

            if !isRunning {
                Button {
                    showIndicatorPicker = true
                } label: {
                    Label("Add / Remove Indicators", systemImage: "plus.circle")
                }
            }
        }
    }

    private var selectedIndicatorsList: [IndicatorConfig] {
        allIndicators.filter { selectedIndicatorIDs.contains($0.id) }
    }

    // MARK: - Info & Action Sections

    @ViewBuilder
    private var infoAndActionSections: some View {
        Section("Info") {
            detailRow("Created", bot.createdAt.formatted(date: .abbreviated, time: .shortened))
            detailRow("Updated", bot.updatedAt.formatted(date: .abbreviated, time: .shortened))
        }

        Section {
            Button {
                duplicateBot()
            } label: {
                Label("Duplicate Bot", systemImage: "doc.on.doc")
            }
            .disabled(isRunning)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Bot", systemImage: "trash")
            }
            .disabled(isRunning)
        } header: {
            Text("Actions")
        } footer: {
            if isRunning {
                Text("Stop the bot before editing or deleting.")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Performance Section

    @ViewBuilder
    private var performanceSection: some View {
        Section("Performance") {
            HStack(spacing: 0) {
                pnlTile(
                    label: isRunning ? "Session P&L" : "Last Session",
                    value: runState?.sessionPnL ?? 0,
                    trades: runState?.sessionTradeCount ?? 0,
                    showNA: !isRunning && runState == nil
                )
                Divider()
                pnlTile(
                    label: "All Time",
                    value: bot.lifetimePnL,
                    trades: bot.lifetimeTradeCount,
                    showNA: false
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private func pnlTile(label: String, value: Double, trades: Int, showNA: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if showNA {
                Text("—")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary)
            } else {
                Text(formatPnL(value))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(value >= 0 ? .green : .red)
            }
            Text("\(trades) trade\(trades == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatPnL(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.positivePrefix = "+"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    // MARK: - Backtest Sections

    @ViewBuilder
    private var backtestSections: some View {
        if !isRunning {
            Section("Backtest Settings") {
                Stepper("Days Back: \(daysBack)", value: $daysBack, in: 1...365)
                Stepper("Bar Limit: \(barLimit)", value: $barLimit, in: 100...20000, step: 100)
            }

            Section {
                Button {
                    Task { await runBacktest() }
                } label: {
                    HStack {
                        Spacer()
                        if isBacktesting {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Running Backtest…")
                        } else {
                            Label("Run Backtest", systemImage: "play.fill")
                        }
                        Spacer()
                    }
                    .font(.headline)
                }
                .disabled(selectedIndicatorsList.isEmpty || isBacktesting)

                if backtestResult != nil {
                    Button(role: .destructive) {
                        backtestResult = nil
                        backtestError = nil
                        backtestBarCount = 0
                    } label: {
                        HStack {
                            Spacer()
                            Label("Clear Results", systemImage: "xmark.circle")
                            Spacer()
                        }
                    }
                }
            } footer: {
                if selectedIndicatorsList.isEmpty {
                    Text("Add at least one indicator to run a backtest.")
                        .foregroundStyle(.orange)
                }
            }

            if let error = backtestError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if let result = backtestResult {
                backtestResultSections(result)
            }
        }
    }

    @ViewBuilder
    private func backtestResultSections(_ result: BacktestResult) -> some View {
        Section {
            Text("Analyzed \(backtestBarCount) bars — \(result.trades.count) trades found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Backtest Summary") {
            let stats = result.statistics
            backtestStatRow("Total P&L",
                            value: formatCurrency(stats.totalPnL),
                            color: stats.totalPnL >= 0 ? .green : .red)
            backtestStatRow("Total Trades", value: "\(stats.totalTrades)")
            backtestStatRow("Win Rate",
                            value: formatPercent(stats.winRate),
                            color: stats.winRate >= 0.5 ? .green : .red)
            backtestStatRow("Longs",
                            value: "\(stats.longTrades) — \(formatPercent(stats.longWinRate)) win",
                            color: stats.longWinRate >= 0.5 ? .green : .red)
            backtestStatRow("Shorts",
                            value: "\(stats.shortTrades) — \(formatPercent(stats.shortWinRate)) win",
                            color: stats.shortWinRate >= 0.5 ? .green : .red)
            backtestStatRow("Profit Factor", value: formatDecimal(stats.profitFactor))
            backtestStatRow("Max Drawdown",
                            value: formatCurrency(stats.maxDrawdown),
                            color: .red)
            backtestStatRow("Sharpe Ratio", value: formatDecimal(stats.sharpeRatio))
            backtestStatRow("Avg Win", value: formatCurrency(stats.averageWin), color: .green)
            backtestStatRow("Avg Loss", value: formatCurrency(stats.averageLoss), color: .red)
            backtestStatRow("Largest Win", value: formatCurrency(stats.largestWin), color: .green)
            backtestStatRow("Largest Loss", value: formatCurrency(stats.largestLoss), color: .red)
        }

        Section("Backtest Trades (\(result.trades.count))") {
            ForEach(result.trades) { trade in
                BacktestTradeRow(trade: trade)
            }
        }
    }

    // MARK: - Run Backtest

    private func runBacktest() async {
        guard !selectedIndicatorsList.isEmpty else { return }
        isBacktesting = true
        backtestResult = nil
        backtestError = nil

        guard let contract = await service.contractById(contractId) else {
            backtestError = "Could not load contract details."
            isBacktesting = false
            return
        }

        let bars = await service.retrieveBarsForConfig(
            contractId: contractId,
            barUnit: barUnit,
            barUnitNumber: barUnitNumber,
            daysBack: daysBack,
            limit: barLimit
        )
        backtestBarCount = bars.count

        guard !bars.isEmpty else {
            backtestError = "No bars returned for the selected configuration."
            isBacktesting = false
            return
        }

        let parameters = BacktestParameters(
            bars: bars,
            indicatorConfigs: selectedIndicatorsList,
            quantity: quantity,
            stopLossTicks: useStopLoss ? stopLossTicks : nil,
            takeProfitTicks: useTakeProfit ? takeProfitTicks : nil,
            tickSize: contract.tickSize,
            tickValue: contract.tickValue,
            tradeDirection: tradeDirection
        )

        backtestResult = BacktestEngine.run(parameters: parameters)
        isBacktesting = false
    }

    // MARK: - Backtest Formatting Helpers

    private func backtestStatRow(_ label: String, value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color ?? .primary)
        }
    }

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

    // MARK: - Load / Save

    private func loadFromBot() {
        name = bot.name
        contractId = bot.contractId
        contractName = bot.contractName
        barUnit = bot.barUnitEnum ?? .minute
        barUnitNumber = bot.barUnitNumber
        useStopLoss = bot.stopLossTicks != nil
        stopLossTicks = bot.stopLossTicks ?? 10
        useTakeProfit = bot.takeProfitTicks != nil
        takeProfitTicks = bot.takeProfitTicks ?? 20
        quantity = bot.quantity
        tradeDirection = bot.tradeDirection
        selectedIndicatorIDs = Set(bot.indicators.map { $0.id })
        selectedAccount = service.accounts.first { $0.id == bot.accountId }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        bot.name = trimmedName
        bot.accountId = selectedAccount?.id ?? bot.accountId
        bot.contractId = contractId
        bot.contractName = contractName
        bot.barUnit = barUnit.rawValue
        bot.barUnitNumber = barUnitNumber
        bot.stopLossTicks = useStopLoss ? stopLossTicks : nil
        bot.takeProfitTicks = useTakeProfit ? takeProfitTicks : nil
        bot.quantity = quantity
        bot.tradeDirection = tradeDirection
        bot.indicators = allIndicators.filter { selectedIndicatorIDs.contains($0.id) }
        bot.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Indicator Helpers

    private func removeIndicator(at offsets: IndexSet) {
        let visible = allIndicators.filter { selectedIndicatorIDs.contains($0.id) }
        for index in offsets {
            selectedIndicatorIDs.remove(visible[index].id)
        }
    }

    // MARK: - Duplicate

    private func duplicateBot() {
        let copy = BotConfig(
            name: bot.name + " (Copy)",
            accountId: bot.accountId,
            contractId: bot.contractId,
            contractName: bot.contractName,
            barUnit: bot.barUnitEnum ?? .minute,
            barUnitNumber: bot.barUnitNumber,
            stopLossTicks: bot.stopLossTicks,
            takeProfitTicks: bot.takeProfitTicks,
            quantity: bot.quantity,
            tradeDirection: bot.tradeDirection,
            indicators: bot.indicators
        )
        modelContext.insert(copy)
        dismiss()
    }

    // MARK: - Display Helpers

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
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

// MARK: - Contract Search Sheet

private struct ContractSearchSheet: View {
    @Binding var contracts: [Contract]
    @Binding var contractSearch: String
    @Binding var isLoading: Bool
    let onSelect: (Contract) -> Void
    let onLoad: () async -> Void

    @Environment(\.dismiss) private var dismiss

    private var filtered: [Contract] {
        guard !contractSearch.isEmpty else { return contracts }
        return contracts.filter {
            $0.name.localizedCaseInsensitiveContains(contractSearch) ||
            $0.description.localizedCaseInsensitiveContains(contractSearch) ||
            $0.symbolId.localizedCaseInsensitiveContains(contractSearch)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search contracts", text: $contractSearch)
                            .textFieldStyle(.plain)
                        if !contractSearch.isEmpty {
                            Button { contractSearch = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if isLoading {
                    Section {
                        ProgressView("Loading contracts…")
                    }
                } else if contracts.isEmpty {
                    Section {
                        Text("No contracts found").foregroundStyle(.secondary)
                    }
                } else if filtered.isEmpty {
                    Section {
                        Text("No contracts match \"\(contractSearch)\"").foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(filtered) { contract in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contract.name).font(.body)
                                Text(contract.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(contract) }
                        }
                    }
                }
            }
            .navigationTitle("Change Contract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await onLoad() }
        }
    }
}

// MARK: - Indicator Picker Sheet

private struct IndicatorPickerSheet: View {
    let allIndicators: [IndicatorConfig]
    @Binding var selectedIDs: Set<UUID>

    @State private var showNewIndicator = false
    @State private var editingIndicator: IndicatorConfig?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if allIndicators.isEmpty {
                    Section {
                        Text("No indicators created yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Select Indicators") {
                        ForEach(allIndicators) { indicator in
                            HStack {
                                IndicatorRow(indicator: indicator)
                                Spacer()
                                Image(systemName: selectedIDs.contains(indicator.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(indicator.id) ? .green : .gray)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIDs.contains(indicator.id) {
                                    selectedIDs.remove(indicator.id)
                                } else {
                                    selectedIDs.insert(indicator.id)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Edit") { editingIndicator = indicator }.tint(.blue)
                            }
                        }
                    }
                    Section {
                        Text("\(selectedIDs.count) indicator\(selectedIDs.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        showNewIndicator = true
                    } label: {
                        Label("New Indicator", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Indicators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showNewIndicator) {
                IndicatorEditorView(existing: nil)
            }
            .sheet(item: $editingIndicator) { indicator in
                IndicatorEditorView(existing: indicator)
            }
        }
    }
}

// MARK: - Backtest Trade Row

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

// MARK: - Bot Log Row

struct BotLogRow: View {
    let entry: BotLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.caption)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.caption)
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var iconName: String {
        switch entry.type {
        case .signal: "waveform.path.ecg"
        case .order:  "cart.fill"
        case .error:  "exclamationmark.triangle.fill"
        case .info:   "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch entry.type {
        case .signal: .blue
        case .order:  .green
        case .error:  .red
        case .info:   .secondary
        }
    }
}
