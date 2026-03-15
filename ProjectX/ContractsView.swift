import SwiftUI

struct ContractsView: View {
    @Environment(ProjectXService.self) var service

    @State private var contracts:        [Contract] = []
    @State private var searchText        = ""
    @State private var isLoading         = false
    @State private var useLive           = false
    @State private var selectedContract: Contract?

    var filtered: [Contract] {
        guard !searchText.isEmpty else { return contracts }
        return contracts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.symbolId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading contracts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if contracts.isEmpty {
                    ContentUnavailableView(
                        "No Contracts",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Tap refresh to load contracts.")
                    )
                } else {
                    List(filtered) { contract in
                        ContractRow(contract: contract)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedContract = contract }
                    }
                    .searchable(text: $searchText, prompt: "Search by name or symbol")
                }
            }
            .navigationTitle("Contracts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle("Live data", isOn: $useLive)
                            .onChange(of: useLive) { _, _ in
                                Task { await loadContracts() }
                            }
                        Divider()
                        Button {
                            Task { await loadContracts() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task { await loadContracts() }
            .sheet(item: $selectedContract) { contract in
                ContractDetailView(contract: contract)
                    .environment(service)
            }
        }
    }

    private func loadContracts() async {
        isLoading = true
        contracts = await service.availableContracts(live: useLive)
        isLoading = false
    }
}

struct ContractRow: View {
    let contract: Contract

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(contract.name).font(.headline)
                Spacer()
                if contract.activeContract {
                    Text("Active")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }
            Text(contract.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label("Tick: \(contract.tickSize, specifier: "%.4g")", systemImage: "arrow.up.and.down")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Value: $\(contract.tickValue, specifier: "%.2f")", systemImage: "dollarsign.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ContractDetailView: View {
    @Environment(ProjectXService.self) var service
    @Environment(\.dismiss) var dismiss

    let contract: Contract

    @State private var showPlaceOrder = false
    @State private var showBars       = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Contract Info") {
                    row("Name",        contract.name)
                    row("ID",          contract.id)
                    row("Symbol",      contract.symbolId)
                    row("Description", contract.description)
                    row("Tick Size",   "\(contract.tickSize)")
                    row("Tick Value",  "$\(contract.tickValue)")
                    row("Status",      contract.activeContract ? "Active" : "Inactive")
                }
                Section("Actions") {
                    Button {
                        showPlaceOrder = true
                    } label: {
                        Label("Place Order", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .disabled(service.accounts.isEmpty)

                    Button {
                        showBars = true
                    } label: {
                        Label("View Historical Bars", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            .navigationTitle(contract.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPlaceOrder) {
                PlaceOrderView(contract: contract).environment(service)
            }
            .sheet(isPresented: $showBars) {
                BarsView(contract: contract).environment(service)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
