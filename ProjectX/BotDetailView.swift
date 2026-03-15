import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Bot Detail View
//
// Detail sheet for a saved bot.
// Actions: Start/Stop, Edit, Duplicate, Delete.
// Live status display and activity log.
// ─────────────────────────────────────────────

struct BotDetailView: View {
    @Environment(ProjectXService.self) var service
    @Environment(BotRunner.self) var botRunner
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let bot: BotConfig

    @State private var showEditWizard = false
    @State private var showDeleteConfirmation = false

    private var runState: BotRunState? {
        botRunner.runStates[bot.id]
    }

    private var isRunning: Bool {
        botRunner.isRunning(bot)
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Start / Stop ────────────
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

                // ── Live Status ─────────────
                if let state = runState {
                    Section("Live Status") {
                        // Status badge
                        HStack {
                            Text("Status")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label(bot.status.displayName, systemImage: bot.status.systemImage)
                                .foregroundStyle(statusColor)
                        }

                        // Last signal
                        HStack {
                            Text("Last Signal")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(signalLabel(state.lastSignal))
                                .fontWeight(.semibold)
                                .foregroundStyle(signalColor(state.lastSignal))
                        }

                        // Last bar time
                        if let barTime = state.lastBarTime {
                            HStack {
                                Text("Last Bar")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(barTime)
                                    .font(.caption)
                                    .monospaced()
                            }
                        }

                        // Last poll time
                        if let pollTime = state.lastPollTime {
                            HStack {
                                Text("Last Poll")
                                    .foregroundStyle(.secondary)
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

                // ── Activity Log ────────────
                if let state = runState, !state.log.isEmpty {
                    Section("Activity Log") {
                        ForEach(state.log.prefix(50)) { entry in
                            BotLogRow(entry: entry)
                        }
                    }
                }

                // ── Configuration ────────────
                Section("Configuration") {
                    detailRow("Name", bot.name)
                    detailRow("Account ID", "\(bot.accountId)")
                    detailRow("Contract", bot.contractName)
                    detailRow("Bar Size", bot.barSizeLabel)
                    detailRow("Quantity", "\(bot.quantity)")
                }

                // ── Risk Management ──────────
                Section("Risk Management") {
                    detailRow("Stop Loss",
                              bot.stopLossTicks.map { "\($0) ticks" } ?? "None")
                    detailRow("Take Profit",
                              bot.takeProfitTicks.map { "\($0) ticks" } ?? "None")
                }

                // ── Indicators ───────────────
                Section("Indicators (\(bot.indicators.count))") {
                    if bot.indicators.isEmpty {
                        Text("No indicators configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bot.indicators) { indicator in
                            IndicatorRow(indicator: indicator)
                        }
                    }
                }

                // ── Timestamps ───────────────
                Section("Info") {
                    detailRow("Created", bot.createdAt.formatted(date: .abbreviated, time: .shortened))
                    detailRow("Updated", bot.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                // ── Actions ──────────────────
                Section {
                    Button {
                        showEditWizard = true
                    } label: {
                        Label("Edit Bot", systemImage: "pencil")
                    }
                    .disabled(isRunning)

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
            .navigationTitle(bot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditWizard) {
                BotWizardView(existing: bot)
            }
            .confirmationDialog("Delete Bot?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(bot)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(bot.name)\". This action cannot be undone.")
            }
        }
    }

    // MARK: - Helpers

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
            indicators: bot.indicators  // share references
        )
        modelContext.insert(copy)
        dismiss()
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
