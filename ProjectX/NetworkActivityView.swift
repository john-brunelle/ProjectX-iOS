import SwiftUI

// ─────────────────────────────────────────────
// Network Activity Tab
//
// Running log of REST + SignalR traffic with
// filter segments, expandable rows, and a
// clear button. Entries auto-expire at 24h.
// ─────────────────────────────────────────────

struct NetworkActivityView: View {
    @Environment(NetworkLogger.self) private var logger

    @State private var selectedFilter: NetworkLogger.Source = .all
    @State private var selectedEndpoint: NetworkLogger.Endpoint = .all
    @State private var expandedEntryIDs: Set<UUID> = []

    private var filteredEntries: [NetworkLogger.Entry] {
        logger.entries.filter { entry in
            (selectedFilter == .all || entry.source == selectedFilter)
            && selectedEndpoint.matches(entry)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                rateGauges
                entryList
            }
            .navigationTitle("Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Picker("Source", selection: $selectedFilter) {
                    ForEach(NetworkLogger.Source.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    ForEach(NetworkLogger.Endpoint.allCases) { endpoint in
                        Button {
                            selectedEndpoint = endpoint
                        } label: {
                            if selectedEndpoint == endpoint {
                                Label(endpoint.rawValue, systemImage: "checkmark")
                            } else {
                                Text(endpoint.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.caption2)
                        Text(selectedEndpoint == .all ? "Endpoint" : selectedEndpoint.rawValue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        selectedEndpoint == .all ? Color.clear : Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
            }
            .padding(.horizontal)

            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Logs kept for up to 12 hours")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(filteredEntries.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Divider()
        }
        .padding(.top, 8)
    }

    // MARK: - Rate Gauges

    @ViewBuilder
    private var rateGauges: some View {
        let barsCount = logger.barsFeedRequestsPer30s
        let barsLimit = 50
        let otherCount = logger.otherRequestsPer60s
        let otherLimit = 200

        HStack(spacing: 12) {
            rateGauge(label: "Bars Feed", window: "30s", count: barsCount, limit: barsLimit)
            rateGauge(label: "Other", window: "60s", count: otherCount, limit: otherLimit)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)

        Divider()
    }

    @ViewBuilder
    private func rateGauge(label: String, window: String, count: Int, limit: Int) -> some View {
        let ratio = Double(count) / Double(limit)
        let color: Color = ratio >= 0.9 ? .red : ratio >= 0.7 ? .orange : .green

        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("\(count) / \(limit)")
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(color)

            ProgressView(value: min(Double(count), Double(limit)), total: Double(limit))
                .tint(color)

            Text(window)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Entry List

    @ViewBuilder
    private var entryList: some View {
        if filteredEntries.isEmpty {
            ContentUnavailableView(
                "No Network Activity",
                systemImage: "network.slash",
                description: Text("Network requests will appear here as they occur.")
            )
        } else {
            List {
                ForEach(filteredEntries) { entry in
                    entryRow(entry)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Entry Row

    @ViewBuilder
    private func entryRow(_ entry: NetworkLogger.Entry) -> some View {
        let isExpanded = expandedEntryIDs.contains(entry.id)

        VStack(alignment: .leading, spacing: 6) {
            summaryRow(entry)
            if isExpanded {
                expandedContent(entry)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedEntryIDs.remove(entry.id)
                } else {
                    expandedEntryIDs.insert(entry.id)
                }
            }
        }
    }

    // MARK: - Summary Row

    @ViewBuilder
    private func summaryRow(_ entry: NetworkLogger.Entry) -> some View {
        HStack(spacing: 8) {
            // Source badge
            sourceBadge(entry.source)

            // Method + Path
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.method)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.primary)
                Text(entry.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Status + Duration
            VStack(alignment: .trailing, spacing: 2) {
                statusBadge(entry)
                if let duration = entry.duration {
                    Text(formatDuration(duration))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            // Timestamp
            Text(formatTime(entry.timestamp))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(_ entry: NetworkLogger.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reqBody = entry.requestBody, !reqBody.isEmpty {
                bodyBlock(label: "Request", text: reqBody)
            }
            if let resBody = entry.responseBody, !resBody.isEmpty {
                bodyBlock(label: "Response", text: resBody)
            }
            if let error = entry.error {
                bodyBlock(label: "Error", text: error, isError: true)
            }
            if entry.requestBody == nil && entry.responseBody == nil && entry.error == nil {
                Text("No body data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sourceBadge(_ source: NetworkLogger.Source) -> some View {
        Text(source == .rest ? "REST" : "WS")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(source == .rest ? Color.blue : Color.purple, in: RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func statusBadge(_ entry: NetworkLogger.Entry) -> some View {
        if let code = entry.statusCode {
            Text("\(code)")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(entry.isSuccess ? .green : .red)
        } else if entry.error != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func bodyBlock(label: String, text: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isError ? .red : .secondary)
            Text(text.prefix(2000))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isError ? .red : .primary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                logger.clear()
                expandedEntryIDs.removeAll()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(logger.entries.isEmpty)
        }
    }

    // MARK: - Formatting

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        return String(format: "%.1fs", duration)
    }
}
