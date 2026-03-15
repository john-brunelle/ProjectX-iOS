import SwiftUI

// ─────────────────────────────────────────────
// LiveDashboardView
// Shows live streaming updates from the User Hub:
// active positions, open orders, and recent trades
// all updating in real time without manual refresh.
// ─────────────────────────────────────────────

struct LiveDashboardView: View {
    @Environment(RealtimeService.self) var realtime

    var isEmbedded: Bool = false

    @State private var selectedTab = 0

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
                // Status bar
                HStack {
                    ConnectionBadge(isConnected: realtime.isUserConnected)
                    Spacer()
                    Text("Live Updates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))

                Picker("", selection: $selectedTab) {
                    Text("Positions (\(realtime.livePositions.count))").tag(0)
                    Text("Orders (\(realtime.liveOrders.count))").tag(1)
                    Text("Trades (\(realtime.liveTrades.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    if selectedTab == 0 {
                        livePositionsList
                    } else if selectedTab == 1 {
                        liveOrdersList
                    } else {
                        liveTradesList
                    }
                }
            }
            .navigationTitle("Live")
    }

    // ── Live Positions ────────────────────────
    private var livePositionsList: some View {
        Group {
            if realtime.livePositions.isEmpty {
                ContentUnavailableView(
                    "No Live Positions",
                    systemImage: "chart.bar.fill",
                    description: Text("Position updates will appear here in real time.")
                )
            } else {
                List(realtime.livePositions) { position in
                    PositionRow(position: position)
                }
                .listStyle(.plain)
            }
        }
    }

    // ── Live Orders ───────────────────────────
    private var liveOrdersList: some View {
        Group {
            if realtime.liveOrders.isEmpty {
                ContentUnavailableView(
                    "No Live Orders",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Order updates will appear here in real time.")
                )
            } else {
                List(realtime.liveOrders) { order in
                    OrderRow(order: order, showCancel: false) {}
                }
                .listStyle(.plain)
            }
        }
    }

    // ── Live Trades ───────────────────────────
    private var liveTradesList: some View {
        Group {
            if realtime.liveTrades.isEmpty {
                ContentUnavailableView(
                    "No Live Trades",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Trade confirmations will appear here in real time.")
                )
            } else {
                List(realtime.liveTrades) { trade in
                    TradeRow(trade: trade)
                }
                .listStyle(.plain)
            }
        }
    }
}
