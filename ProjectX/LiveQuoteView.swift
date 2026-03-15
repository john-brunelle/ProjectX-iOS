import SwiftUI

// ─────────────────────────────────────────────
// LiveQuoteView
// Shows live streaming quote for a contract.
// Includes bid/ask, OHLV, market trade tape,
// and a compact DOM (depth of market) ladder.
// ─────────────────────────────────────────────

struct LiveQuoteView: View {
    @Environment(ProjectXService.self) var service
    @Environment(RealtimeService.self) var realtime
    @Environment(\.dismiss) var dismiss

    let contract: Contract

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Connection status ─────
                    ConnectionBadge(isConnected: realtime.isMarketConnected)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal)

                    // ── Quote card ────────────
                    if let quote = realtime.currentQuote {
                        QuoteCard(quote: quote)
                            .padding(.horizontal)
                    } else {
                        ProgressView("Connecting to live feed...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }

                    // ── DOM ladder ────────────
                    if !realtime.domEntries.isEmpty {
                        DOMView(entries: realtime.domEntries)
                            .padding(.horizontal)
                    }

                    // ── Market trade tape ─────
                    if !realtime.marketTrades.isEmpty {
                        MarketTapeView(trades: realtime.marketTrades)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("\(contract.name) Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        realtime.disconnectMarket()
                        dismiss()
                    }
                }
            }
            .onAppear {
                realtime.connectMarketHub(contractId: contract.id)
            }
        }
    }
}

// ── Connection Status Badge ───────────────────

struct ConnectionBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(isConnected ? "Live" : "Connecting...")
                .font(.caption)
                .foregroundStyle(isConnected ? .green : .orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            (isConnected ? Color.green : Color.orange).opacity(0.1)
        )
        .clipShape(Capsule())
    }
}

// ── Quote Card ────────────────────────────────

struct QuoteCard: View {
    let quote: Quote

    var changeColor: Color { quote.change >= 0 ? .green : .red }

    var body: some View {
        VStack(spacing: 12) {
            // Price + change
            HStack(alignment: .bottom) {
                Text("\(quote.lastPrice, specifier: "%.2f")")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(changeColor)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%+.2f", quote.change))
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(changeColor)
                    Text(String(format: "%+.2f%%", quote.changePercent))
                        .font(.subheadline)
                        .foregroundStyle(changeColor)
                }
            }

            Divider()

            // Bid / Ask
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BID").font(.caption2).foregroundStyle(.secondary)
                    Text("\(quote.bestBid, specifier: "%.2f")")
                        .font(.title2).fontWeight(.semibold).foregroundStyle(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ASK").font(.caption2).foregroundStyle(.secondary)
                    Text("\(quote.bestAsk, specifier: "%.2f")")
                        .font(.title2).fontWeight(.semibold).foregroundStyle(.red)
                }
            }

            Divider()

            // OHLV
            HStack(spacing: 0) {
                ohlvCell("Open",   String(format: "%.2f", quote.open))
                ohlvCell("High",   String(format: "%.2f", quote.high))
                ohlvCell("Low",    String(format: "%.2f", quote.low))
                ohlvCell("Volume", "\(Int(quote.volume))")
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func ohlvCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }
}

// ── DOM Ladder ────────────────────────────────

struct DOMView: View {
    let entries: [DOMEntry]

    var asks: [DOMEntry] { entries.filter { $0.type == DomType.ask.rawValue || $0.type == DomType.bestAsk.rawValue }.sorted { $0.price > $1.price } }
    var bids: [DOMEntry] { entries.filter { $0.type == DomType.bid.rawValue || $0.type == DomType.bestBid.rawValue }.sorted { $0.price > $1.price } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Depth of Market")
                .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                // Asks
                VStack(spacing: 2) {
                    Text("Ask").font(.caption2).foregroundStyle(.red)
                    ForEach(asks.prefix(8)) { entry in
                        domRow(price: entry.price, volume: entry.volume, color: .red)
                    }
                }
                .frame(maxWidth: .infinity)

                // Bids
                VStack(spacing: 2) {
                    Text("Bid").font(.caption2).foregroundStyle(.green)
                    ForEach(bids.prefix(8)) { entry in
                        domRow(price: entry.price, volume: entry.volume, color: .green)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func domRow(price: Double, volume: Int, color: Color) -> some View {
        HStack {
            Text("\(price, specifier: "%.2f")")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
            Spacer()
            Text("\(volume)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }
}

// ── Market Trade Tape ─────────────────────────

struct MarketTapeView: View {
    let trades: [MarketTrade]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Market Tape — last \(trades.count) trades")
                .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)

            ForEach(trades.prefix(20)) { trade in
                HStack {
                    Text(trade.isBuy ? "▲" : "▼")
                        .foregroundStyle(trade.isBuy ? .green : .red)
                        .font(.caption2)
                    Text("\(trade.price, specifier: "%.2f")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(trade.isBuy ? .green : .red)
                    Spacer()
                    Text("\(trade.volume)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 1)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
