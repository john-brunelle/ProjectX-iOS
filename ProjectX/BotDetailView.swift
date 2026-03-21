import SwiftUI
import SwiftData
import Charts

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
    @Environment(RealtimeService.self) var realtime
    @Environment(BotRunner.self) var botRunner
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let bot: BotConfig

    @Query private var allAssignments: [AccountBotAssignment]
    @Query private var allProfiles: [AccountProfile]

    // ── Edit state (loaded from bot on appear) ──
    @State private var name = ""
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

    // ── ATR tool state ──
    @State private var showATR = false
    @State private var atrValue: Double?
    @State private var atrTicks: Double?
    @State private var isCalculatingATR = false
    @State private var atrBarCount = 50
    @State private var showATRInfo = false
    @State private var atrMultiplier: Double = 1.5
    @State private var atrTPMultiplier: Double = 2.0

    // ── Bar size expand/collapse ──
    @State private var showBarSizeDetail = false

    // ── Other UI state ──
    @State private var showArchiveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showClearLogConfirmation = false
    @State private var showResetPnLConfirmation = false
    @State private var showTradeHistory = false
    @State private var showBacktestCharts = false
    @State private var resetPnLTarget: ResetPnLTarget = .session

    private enum ResetPnLTarget { case session, lifetime, all }
    @State private var showAccountPicker = false

    private var isRunning: Bool { botRunner.isRunningAnywhere(bot) }
    private var runningAccountIds: [Int] { botRunner.runningAccountIds(for: bot) }

    private var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespaces) != bot.name
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
            .sheet(isPresented: $showTradeHistory) {
                BotTradeHistoryView(bot: bot, accountId: service.activeAccount?.id ?? 0)
                    .environment(service)
            }
            .sheet(isPresented: $showBacktestCharts) {
                if let result = backtestResult {
                    BacktestChartsView(result: result)
                }
            }
            .confirmationDialog(resetPnLDialogTitle, isPresented: $showResetPnLConfirmation) {
                Button("Reset", role: .destructive) {
                    resetPnL()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(resetPnLDialogMessage)
            }
            .confirmationDialog("Archive Bot?", isPresented: $showArchiveConfirmation) {
                Button("Archive", role: .destructive) {
                    if isRunning { botRunner.stopAllInstances(of: bot) }
                    bot.isArchived = true
                    bot.isActive = false
                    bot.updatedAt = Date()
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Archive \"\(bot.name)\"? It will be hidden from the dashboard but kept in your bot library.")
            }
            .confirmationDialog("Permanently Delete Bot?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    botRunner.stopAllInstances(of: bot)
                    for assignment in allAssignments where assignment.botId == bot.id {
                        modelContext.delete(assignment)
                    }
                    for (key, _) in botRunner.runStates where key.botId == bot.id {
                        botRunner.clearLog(for: key.botId, accountId: key.accountId)
                    }
                    modelContext.delete(bot)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove \"\(bot.name)\" and all its data. This cannot be undone.")
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
        // ── Hero + Active Toggle ────────────
        Section {
            VStack(spacing: 14) {
                Button {
                    bot.isActive.toggle()
                    bot.updatedAt = Date()
                } label: {
                    BotAvatar(botId: bot.id, size: 80)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: bot.isActive ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 22))
                                .foregroundStyle(bot.isActive ? .green : .orange)
                                .background(Circle().fill(.background).padding(1))
                                .offset(x: 4, y: -4)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                VStack(spacing: 4) {
                    TextField("Bot Name", text: $name)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .disabled(isRunning)
                    Text(bot.contractName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
        } footer: {
            if !bot.isActive {
                Text("Inactive bots cannot be started and are hidden from the Home dashboard.")
                    .foregroundStyle(.orange)
            }
        }

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

        // ── Running Instances ────────────────
        if !runningAccountIds.isEmpty {
            Section("Running On") {
                ForEach(runningAccountIds, id: \.self) { accountId in
                    if let account = service.accounts.first(where: { $0.id == accountId }) {
                        let state = botRunner.runState(for: bot, accountId: accountId)
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                                .modifier(PulsingModifier())
                            Text(displayName(for: account))
                                .font(.body.weight(.medium))
                            if let state {
                                Text(signalLabel(state.lastSignal))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(signalColor(state.lastSignal))
                            }
                            Spacer()
                            Button(role: .destructive) {
                                botRunner.stop(bot: bot, accountId: accountId)
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if runningAccountIds.count > 1 {
                    Button(role: .destructive) {
                        botRunner.stopAllInstances(of: bot)
                    } label: {
                        Label("Stop All Instances", systemImage: "stop.circle.fill")
                            .font(.subheadline)
                    }
                }
            }
        }

        // ── Start ─────────────────────
        Section {
            let assignedAccountIds = allAssignments.filter { $0.botId == bot.id }.map(\.accountId)
            let stoppedAccountIds = assignedAccountIds.filter { !runningAccountIds.contains($0) }
            let canStart = bot.isActive && !bot.indicators.isEmpty && !stoppedAccountIds.isEmpty
            Button {
                if stoppedAccountIds.count == 1 {
                    botRunner.start(bot: bot, accountId: stoppedAccountIds[0])
                } else {
                    showAccountPicker = true
                }
            } label: {
                Label("Start Bot", systemImage: "play.circle.fill")
                    .font(.headline)
                    .foregroundStyle(canStart ? .green : .gray)
            }
            .disabled(!canStart)
        } footer: {
            let assignedAccountIds = allAssignments.filter { $0.botId == bot.id }.map(\.accountId)
            let stoppedAccountIds = assignedAccountIds.filter { !runningAccountIds.contains($0) }
            if !bot.isActive {
                Text("Activate this bot before starting.")
                    .foregroundStyle(.orange)
            } else if bot.indicators.isEmpty {
                Text("Add at least one indicator before starting.")
                    .foregroundStyle(.orange)
            } else if assignedAccountIds.isEmpty {
                Text("Assign this bot to an account before starting.")
                    .foregroundStyle(.orange)
            } else if stoppedAccountIds.isEmpty && !runningAccountIds.isEmpty {
                Text("Already running on all assigned accounts.")
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Start on which account?", isPresented: $showAccountPicker) {
            let assignedAccountIds = allAssignments.filter { $0.botId == bot.id }.map(\.accountId)
            let stoppedAccountIds = assignedAccountIds.filter { !runningAccountIds.contains($0) }
            ForEach(service.accounts.filter { stoppedAccountIds.contains($0.id) }) { account in
                Button(displayName(for: account)) {
                    botRunner.start(bot: bot, accountId: account.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }

        // ── Performance ──────────────────────
        performanceSection

        // ── Live Status (per account) ────────
        ForEach(runningAccountIds, id: \.self) { accountId in
            if let state = botRunner.runState(for: bot, accountId: accountId) {
                let accountName = service.accounts.first(where: { $0.id == accountId }).map { displayName(for: $0) } ?? "Account \(accountId)"
                Section("Live Status — \(accountName)") {
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
                    let pnl = livePnL(accountId: accountId)
                    if pnl.realized != 0 || pnl.tradeCount > 0 || pnl.unrealized != 0 {
                        let totalSession = pnl.realized + pnl.unrealized
                        HStack {
                            Text("Today's P&L").foregroundStyle(.secondary)
                            Spacer()
                            Text(formatPnL(totalSession))
                                .fontWeight(.semibold)
                                .foregroundStyle(totalSession >= 0 ? .green : .red)
                            if pnl.unrealized != 0 {
                                Text("(\(formatPnL(pnl.unrealized)) open)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Text("(\(pnl.tradeCount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        // ── Activity Log (combined across all instances) ──
        activityLogSection
    }

    // MARK: - Configuration Sections (Name, Account, Contract, Bar Size)

    @ViewBuilder
    private var configSections: some View {
        Section("Contract") {
            Stepper("Quantity: \(quantity)", value: $quantity, in: 1...100)
                .disabled(isRunning)

            HStack {
                Text("Contract").foregroundStyle(.secondary)
                Spacer()
                Text(contractName.isEmpty ? bot.contractName : contractName)
                    .foregroundStyle(isRunning ? .secondary : .primary)
                if !isRunning {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isRunning else { return }
                showContractSearch = true
            }

            HStack {
                Text("Bar Size").foregroundStyle(.secondary)
                Spacer()
                Text("\(barUnitNumber) \(barUnit.label)")
                    .foregroundStyle(isRunning ? .secondary : .primary)
                Image(systemName: showBarSizeDetail ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { showBarSizeDetail.toggle() }
            }

            if showBarSizeDetail {
                Picker("Bar Unit", selection: $barUnit) {
                    ForEach(BarUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)

                Stepper("Value: \(barUnitNumber)", value: $barUnitNumber, in: 1...60)
                    .disabled(isRunning)
            }
        }
    }

    // MARK: - Risk Management Sections

    @ViewBuilder
    private var riskSections: some View {
        Section {
            // ── ATR Tool ──────────────────────────
            VStack(spacing: 0) {
                // ATR header row — always visible
                HStack {
                    Image(systemName: "function")
                        .foregroundStyle(.blue)
                    Text("ATR Tool")
                        .font(.subheadline.weight(.semibold))
                    Button {
                        showATRInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if let atrTicks {
                        let tick = botRunner.contractTickInfo[bot.contractId]
                        let tickValue = tick?.tickValue ?? 0
                        if tickValue > 0 {
                            Text("\(String(format: "%.1f", atrTicks)) ticks (\(String(format: "$%.2f", atrTicks * tickValue)))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.12), in: Capsule())
                        } else {
                            Text("\(String(format: "%.1f", atrTicks)) ticks")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.12), in: Capsule())
                        }
                    }
                    Image(systemName: showATR ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { showATR.toggle() }
                }

                // ATR detail — expandable
                if showATR {
                    Divider().padding(.vertical, 8)

                    VStack(spacing: 10) {
                        HStack {
                            Stepper("Bars: \(atrBarCount)", value: $atrBarCount, in: 20...200, step: 10)
                            Button {
                                Task { await calculateATR() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }

                        if isCalculatingATR {
                            HStack {
                                ProgressView()
                                Text("Calculating...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let atrTicks {
                            // TP multiplier
                            let tpTicks = Int(round(atrTPMultiplier * atrTicks))
                            Stepper("TP Multiplier: \(String(format: "%.1f", atrTPMultiplier))x → \(tpTicks)t",
                                    value: $atrTPMultiplier, in: 0.5...5.0, step: 0.5)

                            // SL multiplier
                            let slTicks = Int(round(atrMultiplier * atrTicks))
                            Stepper("SL Multiplier: \(String(format: "%.1f", atrMultiplier))x → \(slTicks)t",
                                    value: $atrMultiplier, in: 0.5...5.0, step: 0.5)

                            // Single apply button
                            Button {
                                useTakeProfit = true
                                takeProfitTicks = max(1, tpTicks)
                                useStopLoss = true
                                stopLossTicks = max(1, slTicks)
                            } label: {
                                Label("Apply to TP & SL", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            .disabled(isRunning)
                        } else {
                            Button {
                                Task { await calculateATR() }
                            } label: {
                                Label("Calculate ATR", systemImage: "play.fill")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .alert("Average True Range (ATR)", isPresented: $showATRInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("ATR measures market volatility by averaging the true range of price bars over 14 periods. The true range is the greatest of: current high minus low, absolute value of high minus previous close, or absolute value of low minus previous close.\n\nUse ATR to help set stop loss and take profit levels. A common approach is setting stops at 1-2x ATR from your entry price.")
            }

            // ── Take Profit ───────────────────────
            if isRunning {
                HStack {
                    Text("Take Profit").foregroundStyle(.secondary)
                    Spacer()
                    Text(useTakeProfit ? "\(takeProfitTicks) ticks" : "Off")
                        .foregroundStyle(useTakeProfit ? .primary : .secondary)
                }
            } else {
                Toggle("Take Profit", isOn: $useTakeProfit)
                if useTakeProfit {
                    Stepper("TP Ticks: \(takeProfitTicks)", value: $takeProfitTicks, in: 1...500)
                }
            }

            // ── Stop Loss ─────────────────────────
            if isRunning {
                HStack {
                    Text("Stop Loss").foregroundStyle(.secondary)
                    Spacer()
                    Text(useStopLoss ? "\(stopLossTicks) ticks" : "Off")
                        .foregroundStyle(useStopLoss ? .primary : .secondary)
                }
            } else {
                Toggle("Stop Loss", isOn: $useStopLoss)
                if useStopLoss {
                    Stepper("SL Ticks: \(stopLossTicks)", value: $stopLossTicks, in: 1...500)
                }
            }

            // ── Trade Direction ───────────────────
            Picker("Direction", selection: $tradeDirection) {
                ForEach(TradeDirectionFilter.allCases) { dir in
                    Text(dir.displayName).tag(dir)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isRunning)
        } header: {
            Text("Risk Management")
        }
    }

    // MARK: - Indicator Sections

    @ViewBuilder
    private var indicatorSections: some View {
        Section {
            if selectedIndicatorsList.isEmpty {
                if !isRunning {
                    Button {
                        showIndicatorPicker = true
                    } label: {
                        Label("Add Indicators", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .padding(.vertical, 4)
                } else {
                    Text("No indicators selected")
                        .foregroundStyle(.secondary)
                }
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
        } header: {
            HStack {
                Text("Indicators (\(selectedIndicatorIDs.count))")
                Spacer()
                if !selectedIndicatorsList.isEmpty && !isRunning {
                    Button {
                        showIndicatorPicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
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
                bot.isActive.toggle()
                bot.updatedAt = Date()
            } label: {
                Label(bot.isActive ? "Deactivate Bot" : "Activate Bot",
                      systemImage: bot.isActive ? "circle.dashed" : "checkmark.circle.fill")
            }
            .disabled(isRunning)

            Button {
                duplicateBot()
            } label: {
                Label("Duplicate Bot", systemImage: "doc.on.doc")
            }
            .disabled(isRunning)

            if bot.isArchived {
                Button {
                    bot.isArchived = false
                    bot.updatedAt = Date()
                    try? modelContext.save()
                } label: {
                    Label("Unarchive Bot", systemImage: "arrow.uturn.backward")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Bot", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    showArchiveConfirmation = true
                } label: {
                    Label("Archive Bot", systemImage: "archivebox")
                }
                .disabled(isRunning)
            }
        } header: {
            Text("Actions")
        } footer: {
            if isRunning {
                Text("Stop the bot before editing or archiving.")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Live P&L Helper

    /// Computes realized + unrealized P&L using SignalR live data when available,
    /// falling back to BotRunState values from the poll cycle.
    private func livePnL(accountId: Int) -> (realized: Double, unrealized: Double, tradeCount: Int) {
        let state = botRunner.runState(for: bot, accountId: accountId)

        let unrealized: Double = {
            if let quote = realtime.contractQuotes[bot.contractId],
               let pos = realtime.livePositions.first(where: {
                   $0.accountId == accountId && $0.contractId == bot.contractId
               }),
               let tick = botRunner.contractTickInfo[bot.contractId] {
                let diff = quote.lastPrice - pos.averagePrice
                let dir: Double = pos.isLong ? 1 : -1
                return (diff / tick.tickSize) * tick.tickValue * dir
            }
            return state?.unrealizedPnL ?? 0
        }()

        let realized: Double = {
            if realtime.isUserConnected {
                let botPrefix = bot.tagPrefix
                let tagIds = Set(realtime.liveOrders
                    .filter { $0.accountId == accountId && ($0.customTag?.hasPrefix(botPrefix) == true) }
                    .map(\.id))
                let allIds = tagIds.union(state?.placedOrderIds ?? [])
                let matched = realtime.liveTrades.filter {
                    allIds.contains($0.orderId) && !$0.voided && $0.profitAndLoss != nil
                }
                return matched.compactMap(\.profitAndLoss).reduce(0, +)
            }
            return state?.todayPnL ?? 0
        }()

        return (realized, unrealized, state?.todayTradeCount ?? 0)
    }

    // MARK: - Reset P&L

    private var resetPnLDialogTitle: String {
        switch resetPnLTarget {
        case .session:  return "Reset Today's Stats?"
        case .lifetime: return "Reset Lifetime Stats?"
        case .all:      return "Reset All Stats?"
        }
    }

    private var resetPnLDialogMessage: String {
        switch resetPnLTarget {
        case .session:
            return "This will zero out the current session's P&L and trade count. This cannot be undone."
        case .lifetime:
            return "This will zero out all-time P&L and trade count. Today's stats are kept. This cannot be undone."
        case .all:
            return "This will zero out both session and lifetime P&L and trade counts. This cannot be undone."
        }
    }

    private func resetPnL() {
        switch resetPnLTarget {
        case .session:
            for acctId in runningAccountIds {
                botRunner.resetTodayPnL(for: bot, accountId: acctId)
            }
        case .lifetime:
            bot.lifetimePnL = 0
            bot.lifetimeTradeCount = 0
            bot.updatedAt = Date()
            try? modelContext.save()
        case .all:
            for acctId in runningAccountIds {
                botRunner.resetTodayPnL(for: bot, accountId: acctId)
            }
            bot.lifetimePnL = 0
            bot.lifetimeTradeCount = 0
            bot.updatedAt = Date()
            try? modelContext.save()
        }
    }

    // MARK: - Performance Section

    @ViewBuilder
    private var performanceSection: some View {
        Section("Performance") {
            let aggregated = runningAccountIds.reduce((0.0, 0.0, 0)) { acc, acctId in
                let pnl = livePnL(accountId: acctId)
                return (acc.0 + pnl.realized, acc.1 + pnl.unrealized, acc.2 + pnl.tradeCount)
            }
            let aggregatedPnL = aggregated.0 + aggregated.1
            let aggregatedTrades = aggregated.2
            let aggregatedUnrealized = aggregated.1
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    pnlTile(
                        label: isRunning ? "Today's P&L" : "Last Session",
                        value: aggregatedPnL,
                        trades: aggregatedTrades,
                        showNA: !isRunning
                    )
                    Divider()
                    pnlTile(
                        label: "All Time",
                        value: bot.lifetimePnL,
                        trades: bot.lifetimeTradeCount,
                        showNA: false
                    )
                }
                if isRunning && aggregatedUnrealized != 0 {
                    HStack {
                        Text("Open P&L")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatPnL(aggregatedUnrealized))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                // Trade History
                Divider()
                Button {
                    showTradeHistory = true
                } label: {
                    HStack {
                        Spacer()
                        Label("View Trade History", systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                        Spacer()
                    }
                }

                // Reset menu
                if !isRunning || aggregatedPnL != 0 || bot.lifetimePnL != 0 {
                    Divider()
                    Menu {
                        if isRunning {
                            Button(role: .destructive) {
                                resetPnLTarget = .session
                                showResetPnLConfirmation = true
                            } label: {
                                Label("Reset Today", systemImage: "arrow.counterclockwise")
                            }
                        }
                        Button(role: .destructive) {
                            resetPnLTarget = .lifetime
                            showResetPnLConfirmation = true
                        } label: {
                            Label("Reset Lifetime", systemImage: "arrow.counterclockwise.circle")
                        }
                        Button(role: .destructive) {
                            resetPnLTarget = .all
                            showResetPnLConfirmation = true
                        } label: {
                            Label("Reset All Stats", systemImage: "trash.circle")
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Reset Stats", systemImage: "arrow.counterclockwise")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red.opacity(0.8))
                            Spacer()
                        }
                    }
                }
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

    private var isAIOnly: Bool {
        let hasClaude = bot.indicators.contains { $0.indicatorType == .claudeAI }
        let hasSync = bot.indicators.contains { $0.indicatorType != .claudeAI }
        return hasClaude && !hasSync
    }

    @ViewBuilder
    private var backtestSections: some View {
        if !isRunning && !isAIOnly {
            Section {
                Stepper("Days Back: \(daysBack)", value: $daysBack, in: 1...365)
                Stepper("Bar Limit: \(barLimit)", value: $barLimit, in: 100...20000, step: 100)

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
                            Label(backtestResult != nil ? "Re-run Backtest" : "Run Backtest",
                                  systemImage: "play.fill")
                        }
                        Spacer()
                    }
                    .font(.headline)
                }
                .disabled(selectedIndicatorsList.isEmpty || isBacktesting)
            } header: {
                HStack {
                    Text("Backtest")
                    Spacer()
                    if backtestResult != nil {
                        Button {
                            backtestResult = nil
                            backtestError = nil
                            backtestBarCount = 0
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.red)
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
        Section("Backtest Report") {
            Text("Analyzed \(backtestBarCount) bars — \(result.trades.count) trades found")
                .font(.caption)
                .foregroundStyle(.secondary)
            backtestStatRow("Total P&L",
                            value: formatCurrency(result.statistics.totalPnL),
                            color: result.statistics.totalPnL >= 0 ? .green : .red)
            backtestStatRow("Total Trades", value: "\(result.statistics.totalTrades)")
            backtestStatRow("Win Rate",
                            value: formatPercent(result.statistics.winRate),
                            color: result.statistics.winRate >= 0.5 ? .green : .red)
            backtestStatRow("Longs",
                            value: "\(result.statistics.longTrades) — \(formatPercent(result.statistics.longWinRate)) win",
                            color: result.statistics.longWinRate >= 0.5 ? .green : .red)
            backtestStatRow("Shorts",
                            value: "\(result.statistics.shortTrades) — \(formatPercent(result.statistics.shortWinRate)) win",
                            color: result.statistics.shortWinRate >= 0.5 ? .green : .red)
            backtestStatRow("Profit Factor", value: formatDecimal(result.statistics.profitFactor))
            backtestStatRow("Max Drawdown",
                            value: formatCurrency(result.statistics.maxDrawdown),
                            color: .red)
            backtestStatRow("Sharpe Ratio", value: formatDecimal(result.statistics.sharpeRatio))
            backtestStatRow("Avg Win", value: formatCurrency(result.statistics.averageWin), color: .green)
            backtestStatRow("Avg Loss", value: formatCurrency(result.statistics.averageLoss), color: .red)
            backtestStatRow("Largest Win", value: formatCurrency(result.statistics.largestWin), color: .green)
            backtestStatRow("Largest Loss", value: formatCurrency(result.statistics.largestLoss), color: .red)
            backtestStatRow("Avg Duration", value: formatDuration(result.statistics.averageTradeDuration))
        }

        // ── Equity Curve Chart ──────────────
        if !result.equityCurve.isEmpty {
            Section("Equity Curve") {
                Button {
                    showBacktestCharts = true
                } label: {
                    Label("View All Charts", systemImage: "chart.xyaxis.line")
                        .font(.caption.weight(.medium))
                }
                Chart {
                    // Start at zero
                    LineMark(x: .value("Trade", 0), y: .value("P&L", 0))
                        .foregroundStyle(.green)
                    ForEach(Array(result.equityCurve.enumerated()), id: \.offset) { index, value in
                        LineMark(
                            x: .value("Trade", index + 1),
                            y: .value("P&L", value)
                        )
                        .foregroundStyle(value >= 0 ? .green : .red)
                        AreaMark(
                            x: .value("Trade", index + 1),
                            y: .value("P&L", value)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [value >= 0 ? .green.opacity(0.3) : .red.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v, format: .currency(code: "USD").precision(.fractionLength(0)))
                            }
                        }
                    }
                }
                .chartXAxisLabel("Trade #")
                .frame(height: 200)
            }
        }

        Section("Backtest Trades (\(result.trades.count))") {
            ForEach(result.trades) { trade in
                BacktestTradeRow(trade: trade)
            }
        }
    }

    // MARK: - ATR Calculation

    private func calculateATR() async {
        isCalculatingATR = true
        defer { isCalculatingATR = false }

        let bars = await ProjectXService.shared.retrieveBars(
            contractId: bot.contractId,
            live: false,
            startTime: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            endTime: Date(),
            unit: bot.barUnitEnum ?? .minute,
            unitNumber: bot.barUnitNumber,
            limit: atrBarCount,
            includePartialBar: false
        )

        guard bars.count >= 15 else {
            atrValue = nil
            atrTicks = nil
            return
        }

        // ATR(14): average of 14-period true ranges
        let period = 14
        var trueRanges: [Double] = []
        for i in 1..<bars.count {
            let high = bars[i].h
            let low = bars[i].l
            let prevClose = bars[i - 1].c
            let tr = max(high - low, abs(high - prevClose), abs(low - prevClose))
            trueRanges.append(tr)
        }

        // Wilder's smoothed ATR
        guard trueRanges.count >= period else { return }
        var atr = trueRanges.prefix(period).reduce(0, +) / Double(period)
        for i in period..<trueRanges.count {
            atr = (atr * Double(period - 1) + trueRanges[i]) / Double(period)
        }

        atrValue = atr

        // Try cached tick info first, otherwise fetch contract details
        var tickSize = botRunner.contractTickInfo[bot.contractId]?.tickSize
        if tickSize == nil || tickSize == 0 {
            if let contract = await service.contractById(bot.contractId) {
                tickSize = contract.tickSize
            }
        }

        if let tickSize, tickSize > 0 {
            atrTicks = atr / tickSize
        } else {
            // Fallback: show ATR without tick conversion
            atrTicks = atr
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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let secs = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let mins = totalMinutes % 60
        let hours = totalMinutes / 60
        if hours == 0 {
            return "\(mins)m \(secs)s"
        }
        if hours < 24 {
            return "\(hours)h \(mins)m \(secs)s"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return "\(days)d \(remainingHours)h \(mins)m \(secs)s"
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
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        bot.name = trimmedName
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

    // MARK: - Helpers

    private func displayName(for account: Account) -> String {
        let profile = allProfiles.first { $0.accountId == account.id }
        let alias = profile?.alias.trimmingCharacters(in: .whitespaces) ?? ""
        return alias.isEmpty ? account.name : alias
    }

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

    // MARK: - Activity Log Section

    @ViewBuilder
    private var activityLogSection: some View {
        let allLogs: [BotLogEntry] = botRunner.logsForBot(botId: bot.id)

        if !allLogs.isEmpty {
            Section {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(allLogs) { entry in
                            BotLogRow(entry: entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            } header: {
                HStack {
                    Text("Activity Log")
                    Spacer()
                    if !runningAccountIds.isEmpty {
                        Button(role: .destructive) {
                            showClearLogConfirmation = true
                        } label: {
                            Text("Clear")
                                .font(.caption)
                        }
                    }
                }
            }
            .confirmationDialog("Clear Activity Log?", isPresented: $showClearLogConfirmation) {
                Button("Clear Log", role: .destructive) {
                    for accountId in runningAccountIds {
                        botRunner.clearLog(for: bot.id, accountId: accountId)
                    }
                    // Also clear logs for stopped instances
                    for (key, _) in botRunner.runStates where key.botId == bot.id {
                        botRunner.clearLog(for: key.botId, accountId: key.accountId)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
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
                Text(formatTimestamp(trade.entryTimestamp))
                Text("→")
                Text(formatTimestamp(trade.exitTimestamp))
                if let duration = tradeDuration {
                    Text("(\(formatDuration(duration)) · \(trade.barCount) bar\(trade.barCount == 1 ? "" : "s"))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func formatPrice(_ price: Double) -> String {
        String(format: "%.2f", price)
    }

    private var tradeDuration: TimeInterval? {
        guard let entry = BacktestEngine.parseTimestamp(trade.entryTimestamp),
              let exit = BacktestEngine.parseTimestamp(trade.exitTimestamp) else { return nil }
        return exit.timeIntervalSince(entry)
    }

    private func formatTimestamp(_ raw: String) -> String {
        if let date = BacktestEngine.parseTimestamp(raw) {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return raw
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let secs = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let mins = totalMinutes % 60
        let hours = totalMinutes / 60
        if hours == 0 {
            return "\(mins)m \(secs)s"
        }
        if hours < 24 {
            return "\(hours)h \(mins)m \(secs)s"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return "\(days)d \(remainingHours)h \(mins)m \(secs)s"
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
                    .textSelection(.enabled)
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
