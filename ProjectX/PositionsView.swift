import SwiftUI

struct PositionsView: View {
    @Environment(ProjectXService.self) var service

    @State private var positions:       [Position] = []
    @State private var isLoading                   = false
    @State private var selectedAccount: Account?
    @State private var positionToClose: Position?
    @State private var showPartialClose             = false
    @State private var partialCloseSize             = 1

    var body: some View {
        NavigationStack {
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

                if isLoading {
                    ProgressView("Loading positions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if positions.isEmpty {
                    ContentUnavailableView(
                        "No Open Positions",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("You have no open positions.")
                    )
                } else {
                    // Summary bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total P&L").font(.caption).foregroundStyle(.secondary)
                            Text("N/A — requires realtime feed")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("\(positions.count) position\(positions.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemBackground))

                    List(positions) { position in
                        PositionRow(position: position)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    positionToClose = position
                                } label: {
                                    Label("Close All", systemImage: "xmark.circle.fill")
                                }
                                Button {
                                    positionToClose = position
                                    partialCloseSize = 1
                                    showPartialClose = true
                                } label: {
                                    Label("Partial", systemImage: "minus.circle.fill")
                                }
                                .tint(.orange)
                            }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Positions")
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
            // Close all confirmation
            .confirmationDialog(
                "Close entire position in \(positionToClose?.contractId ?? "")?",
                isPresented: Binding(
                    get: { positionToClose != nil && !showPartialClose },
                    set: { if !$0 { positionToClose = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Close Position", role: .destructive) {
                    Task { await closePosition() }
                }
                Button("Cancel", role: .cancel) { positionToClose = nil }
            }
            // Partial close sheet
            .sheet(isPresented: $showPartialClose) {
                if let position = positionToClose {
                    PartialCloseView(
                        position:   position,
                        closeSize:  $partialCloseSize,
                        onConfirm: {
                            showPartialClose = false
                            Task { await partialClose() }
                        },
                        onCancel: {
                            showPartialClose = false
                            positionToClose  = nil
                        }
                    )
                }
            }
        }
    }

    private func reload() async {
        guard let account = selectedAccount else { return }
        isLoading = true
        positions = await service.searchOpenPositions(accountId: account.id)
        isLoading = false
    }

    private func closePosition() async {
        guard let account = selectedAccount, let position = positionToClose else { return }
        let ok = await service.closePosition(accountId: account.id, contractId: position.contractId)
        positionToClose = nil
        if ok { await reload() }
    }

    private func partialClose() async {
        guard let account = selectedAccount, let position = positionToClose else { return }
        let ok = await service.partialClosePosition(
            accountId:  account.id,
            contractId: position.contractId,
            size:       partialCloseSize
        )
        positionToClose = nil
        if ok { await reload() }
    }
}

// ── Position Row ──────────────────────────────

struct PositionRow: View {
    let position: Position

    var typeColor: Color { position.isLong ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(position.typeLabel)
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(typeColor.opacity(0.15))
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())
                Text(position.contractId).font(.headline)
                Spacer()
                Text("Qty: \(position.size)")
                    .font(.subheadline).fontWeight(.medium)
            }
            HStack(spacing: 16) {
                Label("Avg: \(position.averagePrice, specifier: "%.2f")",
                      systemImage: "dollarsign.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("ID: \(position.id)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Text("Opened: \(formattedTime(position.creationTimestamp))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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

// ── Partial Close Sheet ───────────────────────

struct PartialCloseView: View {
    let position:  Position
    @Binding var closeSize: Int
    let onConfirm: () -> Void
    let onCancel:  () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    HStack {
                        Text(position.contractId).font(.headline)
                        Spacer()
                        Text(position.typeLabel)
                            .foregroundStyle(position.isLong ? .green : .red)
                    }
                    HStack {
                        Text("Total size").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(position.size)")
                    }
                    HStack {
                        Text("Avg price").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(position.averagePrice, specifier: "%.2f")")
                    }
                }
                Section("Close Size") {
                    Stepper("Contracts: \(closeSize)",
                            value: $closeSize,
                            in: 1...position.size)
                }
                Section {
                    Button(role: .destructive) {
                        onConfirm()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Close \(closeSize) of \(position.size) contracts")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Partial Close")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
}
