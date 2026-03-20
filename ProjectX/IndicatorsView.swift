import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Indicators Tab
//
// Build and manage reusable indicator presets.
// Create RSI, MACD, OBV configs with custom
// parameters — these are referenced by bots.
// ─────────────────────────────────────────────

struct IndicatorsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IndicatorConfig.updatedAt, order: .reverse)
    private var indicators: [IndicatorConfig]

    @State private var showingEditor = false
    @State private var selectedIndicator: IndicatorConfig?

    /// When non-nil, shows a "Done" button (used when presented as a sheet from BacktestView).
    var onDone: (() -> Void)? = nil
    /// When true, skips the NavigationStack wrapper (used when pushed from HomeView).
    var isEmbedded: Bool = false

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
                if indicators.isEmpty {
                    ContentUnavailableView(
                        "No Indicators",
                        systemImage: "waveform.path.ecg",
                        description: Text("Tap + to create your first indicator preset.")
                    )
                } else {
                    List {
                        ForEach(indicators) { indicator in
                            IndicatorRow(indicator: indicator)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndicator = indicator
                                }
                        }
                        .onDelete(perform: deleteIndicators)
                    }
                }
            }
            .navigationTitle("Indicators")
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { onDone() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedIndicator = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                IndicatorEditorView(existing: nil)
            }
            .sheet(item: $selectedIndicator) { indicator in
                IndicatorEditorView(existing: indicator)
            }
    }

    private func deleteIndicators(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(indicators[index])
        }
    }
}

// MARK: - Indicator Row

struct IndicatorRow: View {
    let indicator: IndicatorConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(indicator.name)
                    .font(.headline)
                Spacer()
                Label(indicator.indicatorType.displayName,
                      systemImage: indicator.indicatorType.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.fill.tertiary, in: Capsule())
            }
            Text(indicator.parameters.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Indicator Editor

struct IndicatorEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existing: IndicatorConfig?

    // Form state
    @State private var name: String = ""
    @State private var selectedType: IndicatorType = .rsi
    @State private var showTypePicker = false

    // RSI params
    @State private var rsiPeriod: Int = 14
    @State private var rsiOverbought: Double = 70
    @State private var rsiOversold: Double = 30

    // MACD params
    @State private var macdFast: Int = 12
    @State private var macdSlow: Int = 26
    @State private var macdSignal: Int = 9

    // OBV params
    @State private var obvSmoothing: Int = 20

    // MA params
    @State private var maFast: Int = 10
    @State private var maSlow: Int = 50
    @State private var maUseEMA: Bool = true

    // Timer Signal params
    @State private var timerInterval: Int = 60
    @State private var timerMode: TimerSignalMode = .alternating

    // Claude AI params
    @State private var claudeModel: String = "claude-3-5-haiku-latest"
    @State private var claudeBarCount: Int = 50
    @State private var claudeCustomPrompt: String = ""

    var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                // ── Name ─────────────────────
                Section("Name") {
                    TextField("e.g. RSI Conservative", text: $name)
                }

                // ── Type ─────────────────────
                Section("Indicator Type") {
                    Button { showTypePicker = true } label: {
                        HStack {
                            Label(selectedType.displayName, systemImage: selectedType.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(selectedType.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // ── Parameters ───────────────
                Section("Parameters") {
                    switch selectedType {
                    case .rsi:
                        rsiParametersSection
                    case .macd:
                        macdParametersSection
                    case .obv:
                        obvParametersSection
                    case .ma:
                        maParametersSection
                    case .timerSignal:
                        timerSignalParametersSection
                    case .claudeAI:
                        claudeAIParametersSection
                    }
                }

                // ── Signal Description ───────
                Section("Signal Logic") {
                    Text(currentParameters.signalDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // ── Reset ────────────────────
                Section {
                    Button("Reset to Defaults") {
                        resetToDefaults(for: selectedType)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Indicator" : "New Indicator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadExisting() }
            .sheet(isPresented: $showTypePicker) {
                IndicatorTypePickerSheet(selected: $selectedType)
                    .onChange(of: selectedType) { _, newType in
                        if !isEditing { resetToDefaults(for: newType) }
                    }
            }
        }
    }

    // MARK: RSI Parameters

    @ViewBuilder
    private var rsiParametersSection: some View {
        Stepper("Period: \(rsiPeriod)", value: $rsiPeriod, in: 2...100)
        Stepper("Overbought: \(Int(rsiOverbought))", value: $rsiOverbought, in: 50...100, step: 5)
        Stepper("Oversold: \(Int(rsiOversold))", value: $rsiOversold, in: 0...50, step: 5)
    }

    // MARK: MACD Parameters

    @ViewBuilder
    private var macdParametersSection: some View {
        Stepper("Fast Period: \(macdFast)", value: $macdFast, in: 2...50)
        Stepper("Slow Period: \(macdSlow)", value: $macdSlow, in: 2...100)
        Stepper("Signal Period: \(macdSignal)", value: $macdSignal, in: 2...50)
    }

    // MARK: OBV Parameters

    @ViewBuilder
    private var obvParametersSection: some View {
        Stepper("Smoothing Period: \(obvSmoothing)", value: $obvSmoothing, in: 2...100)
    }

    // MARK: MA Parameters

    @ViewBuilder
    private var maParametersSection: some View {
        Stepper("Fast Period: \(maFast)", value: $maFast, in: 2...200)
        Stepper("Slow Period: \(maSlow)", value: $maSlow, in: 2...500)
        Toggle("Use EMA (vs SMA)", isOn: $maUseEMA)
    }

    // MARK: Timer Signal Parameters

    @ViewBuilder
    private var timerSignalParametersSection: some View {
        Stepper("Interval: \(timerInterval)s", value: $timerInterval, in: 5...3600)
        Picker("Mode", selection: $timerMode) {
            ForEach(TimerSignalMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
    }

    // MARK: Claude AI Parameters

    @ViewBuilder
    private var claudeAIParametersSection: some View {
        Picker("Model", selection: $claudeModel) {
            Text("Haiku 4.5 (Fast, Cheap)").tag("claude-haiku-4-5-20251001")
            Text("Sonnet 4.6 (Smarter)").tag("claude-sonnet-4-6-20250627")
        }
        Stepper("Bars to Send: \(claudeBarCount)", value: $claudeBarCount, in: 10...200, step: 10)

        VStack(alignment: .leading, spacing: 4) {
            Text("Custom Prompt (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $claudeCustomPrompt)
                .frame(minHeight: 80)
                .font(.caption)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                )
            Text("Add extra instructions for Claude's analysis, e.g. \"Focus on volume divergences\" or \"Only signal reversals near round numbers\"")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        // API key status
        HStack {
            Text("API Key")
                .foregroundStyle(.secondary)
            Spacer()
            if ClaudeAIService.shared.hasAPIKey {
                Label("Configured", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Not Set — configure in Preferences", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Current Parameters (for signal description)

    private var currentParameters: IndicatorParameters {
        switch selectedType {
        case .rsi:         .rsi(period: rsiPeriod, overbought: rsiOverbought, oversold: rsiOversold)
        case .macd:        .macd(fastPeriod: macdFast, slowPeriod: macdSlow, signalPeriod: macdSignal)
        case .obv:         .obv(smoothingPeriod: obvSmoothing)
        case .ma:          .ma(fastPeriod: maFast, slowPeriod: maSlow, useEMA: maUseEMA)
        case .timerSignal: .timerSignal(intervalSeconds: timerInterval, mode: timerMode)
        case .claudeAI:    .claudeAI(model: claudeModel, barCount: claudeBarCount, customPrompt: claudeCustomPrompt)
        }
    }

    // MARK: Actions

    private func loadExisting() {
        guard let existing else { return }
        name = existing.name
        selectedType = existing.indicatorType

        switch existing.parameters {
        case .rsi(let period, let overbought, let oversold):
            rsiPeriod = period
            rsiOverbought = overbought
            rsiOversold = oversold
        case .macd(let fast, let slow, let signal):
            macdFast = fast
            macdSlow = slow
            macdSignal = signal
        case .obv(let smoothing):
            obvSmoothing = smoothing
        case .ma(let fast, let slow, let useEMA):
            maFast = fast
            maSlow = slow
            maUseEMA = useEMA
        case .timerSignal(let interval, let mode):
            timerInterval = interval
            timerMode = mode
        case .claudeAI(let model, let barCount, let customPrompt):
            claudeModel = model
            claudeBarCount = barCount
            claudeCustomPrompt = customPrompt
        }
    }

    private func resetToDefaults(for type: IndicatorType) {
        switch type {
        case .rsi:
            rsiPeriod = 14; rsiOverbought = 70; rsiOversold = 30
        case .macd:
            macdFast = 12; macdSlow = 26; macdSignal = 9
        case .obv:
            obvSmoothing = 20
        case .ma:
            maFast = 10; maSlow = 50; maUseEMA = true
        case .timerSignal:
            timerInterval = 60; timerMode = .alternating
        case .claudeAI:
            claudeModel = "claude-3-5-haiku-latest"; claudeBarCount = 50; claudeCustomPrompt = ""
        }
    }

    private func save() {
        let params: IndicatorParameters = switch selectedType {
        case .rsi:         .rsi(period: rsiPeriod, overbought: rsiOverbought, oversold: rsiOversold)
        case .macd:        .macd(fastPeriod: macdFast, slowPeriod: macdSlow, signalPeriod: macdSignal)
        case .obv:         .obv(smoothingPeriod: obvSmoothing)
        case .ma:          .ma(fastPeriod: maFast, slowPeriod: maSlow, useEMA: maUseEMA)
        case .timerSignal: .timerSignal(intervalSeconds: timerInterval, mode: timerMode)
        case .claudeAI:    .claudeAI(model: claudeModel, barCount: claudeBarCount, customPrompt: claudeCustomPrompt)
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if let existing {
            existing.name = trimmedName
            existing.indicatorType = selectedType
            existing.parameters = params
            existing.updatedAt = Date()
        } else {
            let config = IndicatorConfig(name: trimmedName, type: selectedType, parameters: params)
            modelContext.insert(config)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Indicator Type Picker Sheet

struct IndicatorTypePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pref_developerMode") private var developerMode = false
    @Binding var selected: IndicatorType
    @State private var searchText = ""

    private var grouped: [(category: String, types: [IndicatorType])] {
        let available = IndicatorType.allCases.filter { !$0.isDevOnly || developerMode }
        let filtered = searchText.isEmpty
            ? available
            : available.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
              }
        var orderedCategories = [String]()
        for type in filtered {
            if !orderedCategories.contains(type.category) {
                orderedCategories.append(type.category)
            }
        }
        return orderedCategories.map { cat in
            (category: cat, types: filtered.filter { $0.category == cat })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.types) { type in
                            typeRow(for: type)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search indicators")
            .navigationTitle("Select Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func typeRow(for type: IndicatorType) -> some View {
        Button {
            selected = type
            dismiss()
        } label: {
            HStack {
                Label(type.displayName, systemImage: type.systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                if type == selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
