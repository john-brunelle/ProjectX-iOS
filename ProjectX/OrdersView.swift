import SwiftUI

struct OrdersView: View {
    @Environment(ProjectXService.self) var service

    var isEmbedded: Bool = false

    @State private var openOrders:      [Order]  = []
    @State private var historyOrders:   [Order]  = []
    @State private var selectedTab               = 0
    @State private var isLoading                 = false

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Open (\(openOrders.count))").tag(0)
                    Text("History (\(historyOrders.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if isLoading {
                    ProgressView("Loading orders...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if selectedTab == 0 {
                            if openOrders.isEmpty {
                                ContentUnavailableView(
                                    "No Open Orders",
                                    systemImage: "tray",
                                    description: Text("You have no open orders.")
                                )
                            } else {
                                ForEach(openOrders) { order in
                                    OrderRow(order: order, showCancel: true) {
                                        Task { await cancelOrder(order) }
                                    }
                                }
                            }
                        } else {
                            if historyOrders.isEmpty {
                                ContentUnavailableView(
                                    "No Order History",
                                    systemImage: "clock",
                                    description: Text("No orders in the last 7 days.")
                                )
                            } else {
                                ForEach(historyOrders) { order in
                                    OrderRow(order: order, showCancel: false) {}
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Orders")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await loadAll() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await loadAll()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    await loadAll()
                }
            }
            .onChange(of: service.activeAccount) { _, _ in
                Task { await loadAll() }
            }
    }

    private func loadAll() async {
        guard let account = service.activeAccount else { return }
        isLoading = true
        async let open    = service.searchOpenOrders(accountId: account.id)
        async let history = service.searchOrders(
            accountId:      account.id,
            startTimestamp: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
            endTimestamp:   Date()
        )
        openOrders    = await open
        historyOrders = await history
        isLoading = false
    }

    private func cancelOrder(_ order: Order) async {
        guard let account = service.activeAccount else { return }
        let ok = await service.cancelOrder(accountId: account.id, orderId: order.id)
        if ok { await loadAll() }
    }
}

struct OrderRow: View {
    let order: Order
    let showCancel: Bool
    let onCancel: () -> Void

    var sideColor: Color { order.side == 0 ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(order.sideLabel)
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(sideColor.opacity(0.15))
                    .foregroundStyle(sideColor)
                    .clipShape(Capsule())
                Text(order.contractId).font(.headline)
                Spacer()
                Text(order.statusLabel).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Label(order.typeLabel, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Qty: \(order.size)", systemImage: "number")
                    .font(.caption).foregroundStyle(.secondary)
                if let price = order.filledPrice {
                    Label("@\(price, specifier: "%.2f")", systemImage: "dollarsign")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let lp = order.limitPrice {
                    Label("Limit: \(lp, specifier: "%.2f")", systemImage: "dollarsign")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let sp = order.stopPrice {
                    Label("Stop: \(sp, specifier: "%.2f")", systemImage: "dollarsign")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("ID: \(order.id)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if showCancel {
                    Button(role: .destructive) { onCancel() } label: {
                        Text("Cancel")
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
