import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Bot Wizard — Multi-Step Bot Creator/Editor
//
// 5 steps: Basics → Indicators → Bar Size →
//          Risk Management → Review & Save
// ─────────────────────────────────────────────

struct BotWizardView: View {
    @Environment(ProjectXService.self) var service
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existing: BotConfig?

    // Step tracking
    @State private var currentStep = 0
    private let stepCount = 5
    private let stepLabels = ["Basics", "Indicators", "Bars", "Risk", "Review"]

    // Step 1: Basics
    @State private var botName = ""
    @State private var selectedAccount: Account?
    @State private var selectedContract: Contract?
    @State private var contracts: [Contract] = []
    @State private var contractSearch = ""
    @State private var isLoadingContracts = false

    // Step 2: Indicators
    @Query(sort: \IndicatorConfig.updatedAt, order: .reverse)
    private var allIndicators: [IndicatorConfig]
    @State private var selectedIndicatorIDs: Set<UUID> = []
    @State private var editingIndicator: IndicatorConfig?
    @State private var showNewIndicator = false

    // Step 3: Bar Size
    @State private var barUnit: BarUnit = .minute
    @State private var barUnitNumber = 5

    // Step 4: Risk Management
    @State private var useStopLoss = false
    @State private var stopLossTicks = 10
    @State private var useTakeProfit = false
    @State private var takeProfitTicks = 20
    @State private var quantity = 1
    @State private var tradeDirection: TradeDirectionFilter = .both

    // Step 5: Review
    @State private var testBarCount: Int?
    @State private var isTestingBars = false

    var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Progress Indicator ───────
                stepProgressView
                    .padding(.vertical, 12)

                Divider()

                // ── Step Content ─────────────
                Group {
                    switch currentStep {
                    case 0: step1Basics
                    case 1: step2Indicators
                    case 2: step3BarSize
                    case 3: step4RiskManagement
                    case 4: step5Review
                    default: EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)

                Divider()

                // ── Navigation Buttons ───────
                stepNavigationButtons
                    .padding()
            }
            .navigationTitle(isEditing ? "Edit Bot" : "New Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadExisting() }
        }
    }

    // MARK: - Progress View

    private var stepProgressView: some View {
        HStack(spacing: 0) {
            ForEach(0..<stepCount, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
                VStack(spacing: 4) {
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text(stepLabels[index])
                        .font(.caption2)
                        .foregroundStyle(index <= currentStep ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 1: Basics

    private var step1Basics: some View {
        List {
            Section("Bot Name") {
                TextField("e.g. Scalper NQ", text: $botName)
            }

            Section("Account") {
                if service.accounts.isEmpty {
                    Text("No accounts available")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select an account").tag(nil as Account?)
                        ForEach(service.accounts) { account in
                            Text("\(account.name) (\(account.id))")
                                .tag(account as Account?)
                        }
                    }
                }
            }

            Section("Contract") {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search contracts", text: $contractSearch)
                        .textFieldStyle(.plain)
                    if !contractSearch.isEmpty {
                        Button {
                            contractSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isLoadingContracts {
                    ProgressView("Loading contracts...")
                } else if contracts.isEmpty {
                    Text("No contracts found")
                        .foregroundStyle(.secondary)
                } else if filteredContracts.isEmpty {
                    Text("No contracts match \"\(contractSearch)\"")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredContracts) { contract in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contract.name).font(.body)
                                Text(contract.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedContract?.id == contract.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedContract = contract }
                    }
                }
            }
        }
        .task { await loadContracts() }
    }

    private var filteredContracts: [Contract] {
        guard !contractSearch.isEmpty else { return contracts }
        return contracts.filter {
            $0.name.localizedCaseInsensitiveContains(contractSearch) ||
            $0.description.localizedCaseInsensitiveContains(contractSearch) ||
            $0.symbolId.localizedCaseInsensitiveContains(contractSearch)
        }
    }

    private func loadContracts() async {
        guard contracts.isEmpty else { return }
        isLoadingContracts = true
        contracts = await service.availableContracts(live: false)
        isLoadingContracts = false
    }

    // MARK: - Step 2: Indicators

    private var step2Indicators: some View {
        List {
            if allIndicators.isEmpty {
                Section {
                    Text("No indicators created yet. Create one below.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Select Indicators") {
                    ForEach(allIndicators) { indicator in
                        HStack {
                            IndicatorRow(indicator: indicator)
                            Spacer()
                            if selectedIndicatorIDs.contains(indicator.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.gray)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedIndicatorIDs.contains(indicator.id) {
                                selectedIndicatorIDs.remove(indicator.id)
                            } else {
                                selectedIndicatorIDs.insert(indicator.id)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Edit") { editingIndicator = indicator }
                                .tint(.blue)
                        }
                    }
                }

                Section {
                    Text("\(selectedIndicatorIDs.count) indicator\(selectedIndicatorIDs.count == 1 ? "" : "s") selected")
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
        .sheet(item: $editingIndicator) { indicator in
            IndicatorEditorView(existing: indicator)
        }
        .sheet(isPresented: $showNewIndicator) {
            IndicatorEditorView(existing: nil)
        }
    }

    // MARK: - Step 3: Bar Size

    private var step3BarSize: some View {
        Form {
            Section("Bar Configuration") {
                Picker("Bar Unit", selection: $barUnit) {
                    ForEach(BarUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                Stepper("Time Value: \(barUnitNumber)", value: $barUnitNumber, in: 1...60)
            }

            Section {
                let label = barUnitNumber == 1 ? barUnit.label : "\(barUnitNumber) \(barUnit.label)"
                Text("The bot will analyze **\(label)**     bars to evaluate indicator signals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 4: Risk Management

    private var step4RiskManagement: some View {
        Form {
            Section("Position Size") {
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...100)
            }

            Section("Stop Loss") {
                Toggle("Enable Stop Loss", isOn: $useStopLoss)
                if useStopLoss {
                    Stepper("Ticks: \(stopLossTicks)", value: $stopLossTicks, in: 1...500)
                }
            }

            Section("Take Profit") {
                Toggle("Enable Take Profit", isOn: $useTakeProfit)
                if useTakeProfit {
                    Stepper("Ticks: \(takeProfitTicks)", value: $takeProfitTicks, in: 1...500)
                }
            }

            Section("Trade Direction") {
                Picker("Direction", selection: $tradeDirection) {
                    ForEach(TradeDirectionFilter.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Step 5: Review

    private var step5Review: some View {
        Form {
            Section("Bot") {
                reviewRow("Name", botName)
            }

            Section("Account") {
                if let account = selectedAccount {
                    reviewRow("Account", "\(account.name) (ID: \(account.id))")
                }
            }

            Section("Contract") {
                if let contract = selectedContract {
                    reviewRow("Contract", contract.name)
                    reviewRow("Symbol", contract.symbolId)
                    reviewRow("Tick Size", String(format: "%.4f", contract.tickSize))
                }
            }

            Section("Indicators (\(selectedIndicatorIDs.count))") {
                let selected = allIndicators.filter { selectedIndicatorIDs.contains($0.id) }
                ForEach(selected) { indicator in
                    IndicatorRow(indicator: indicator)
                }
            }

            Section("Bar Size") {
                let label = barUnitNumber == 1 ? barUnit.label : "\(barUnitNumber) \(barUnit.label)"
                reviewRow("Bar Size", label)
            }

            Section("Risk Management") {
                reviewRow("Quantity", "\(quantity)")
                reviewRow("Stop Loss", useStopLoss ? "\(stopLossTicks) ticks" : "None")
                reviewRow("Take Profit", useTakeProfit ? "\(takeProfitTicks) ticks" : "None")
                reviewRow("Direction", tradeDirection.displayName)
            }

            Section("Data Check") {
                if isTestingBars {
                    ProgressView("Checking bar availability...")
                } else if let count = testBarCount {
                    Label("\(count) bars available", systemImage: count > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(count > 0 ? .green : .red)
                } else {
                    Button("Test Bar Availability") {
                        Task { await testBars() }
                    }
                }
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func testBars() async {
        guard let contract = selectedContract else { return }
        isTestingBars = true
        let bars = await service.retrieveBarsForConfig(
            contractId: contract.id,
            barUnit: barUnit,
            barUnitNumber: barUnitNumber
        )
        testBarCount = bars.count
        isTestingBars = false
    }

    // MARK: - Navigation Buttons

    private var stepNavigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
            }

            Spacer()

            if currentStep < stepCount - 1 {
                Button("Next") {
                    withAnimation { currentStep += 1 }
                }
                .disabled(!canProceed)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case 0:
            return !botName.trimmingCharacters(in: .whitespaces).isEmpty
                && selectedAccount != nil
                && selectedContract != nil
        case 1:
            return !selectedIndicatorIDs.isEmpty
        default:
            return true
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = botName.trimmingCharacters(in: .whitespaces)
        let selectedConfigs = allIndicators.filter { selectedIndicatorIDs.contains($0.id) }

        if let existing {
            existing.name = trimmedName
            existing.accountId = selectedAccount?.id ?? existing.accountId
            existing.contractId = selectedContract?.id ?? existing.contractId
            existing.contractName = selectedContract?.name ?? existing.contractName
            existing.barUnit = barUnit.rawValue
            existing.barUnitNumber = barUnitNumber
            existing.stopLossTicks = useStopLoss ? stopLossTicks : nil
            existing.takeProfitTicks = useTakeProfit ? takeProfitTicks : nil
            existing.quantity = quantity
            existing.tradeDirection = tradeDirection
            existing.indicators = selectedConfigs
            existing.updatedAt = Date()
        } else {
            let bot = BotConfig(
                name: trimmedName,
                accountId: selectedAccount!.id,
                contractId: selectedContract!.id,
                contractName: selectedContract!.name,
                barUnit: barUnit,
                barUnitNumber: barUnitNumber,
                stopLossTicks: useStopLoss ? stopLossTicks : nil,
                takeProfitTicks: useTakeProfit ? takeProfitTicks : nil,
                quantity: quantity,
                tradeDirection: tradeDirection,
                indicators: selectedConfigs
            )
            modelContext.insert(bot)
        }

        dismiss()
    }

    // MARK: - Load Existing

    private func loadExisting() {
        guard let existing else {
            selectedAccount = service.activeAccount  // new bot: pre-select the active account
            return
        }
        botName = existing.name
        selectedAccount = service.accounts.first { $0.id == existing.accountId }
        barUnit = existing.barUnitEnum ?? .minute
        barUnitNumber = existing.barUnitNumber
        useStopLoss = existing.stopLossTicks != nil
        stopLossTicks = existing.stopLossTicks ?? 10
        useTakeProfit = existing.takeProfitTicks != nil
        takeProfitTicks = existing.takeProfitTicks ?? 20
        quantity = existing.quantity
        tradeDirection = existing.tradeDirection
        selectedIndicatorIDs = Set(existing.indicators.map { $0.id })

        // Load contract asynchronously
        Task {
            if let contract = await service.contractById(existing.contractId) {
                selectedContract = contract
            }
        }
    }
}
