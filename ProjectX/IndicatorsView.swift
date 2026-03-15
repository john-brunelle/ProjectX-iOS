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

    var body: some View {
        NavigationStack {
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
                    Picker("Type", selection: $selectedType) {
                        ForEach(IndicatorType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { _, newType in
                        if !isEditing {
                            resetToDefaults(for: newType)
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
                    }
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
        }
    }

    private func save() {
        let params: IndicatorParameters = switch selectedType {
        case .rsi:  .rsi(period: rsiPeriod, overbought: rsiOverbought, oversold: rsiOversold)
        case .macd: .macd(fastPeriod: macdFast, slowPeriod: macdSlow, signalPeriod: macdSignal)
        case .obv:  .obv(smoothingPeriod: obvSmoothing)
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

        dismiss()
    }
}
