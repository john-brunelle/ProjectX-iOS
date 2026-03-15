import SwiftUI

struct BarsView: View {
    @Environment(ProjectXService.self) var service
    @Environment(\.dismiss) var dismiss

    let contract: Contract

    @State private var bars:           [Bar]    = []
    @State private var isLoading                = false
    @State private var selectedUnit: BarUnit    = .hour
    @State private var unitNumber               = 1
    @State private var limit                    = 100
    @State private var useLive                  = false
    @State private var daysBack                 = 7

    var body: some View {
        NavigationStack {
            Form {
                Section("Settings") {
                    Picker("Bar Unit", selection: $selectedUnit) {
                        ForEach(BarUnit.allCases) { u in Text(u.label).tag(u) }
                    }
                    Stepper("Unit Count: \(unitNumber)", value: $unitNumber, in: 1...60)
                    Stepper("Days Back: \(daysBack)",    value: $daysBack,   in: 1...365)
                    Stepper("Limit: \(limit)",           value: $limit,      in: 10...1000, step: 10)
                    Toggle("Live Data", isOn: $useLive)
                    Button {
                        Task { await loadBars() }
                    } label: {
                        Label("Fetch Bars", systemImage: "arrow.clockwise")
                    }
                }

                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading bars...")
                            Spacer()
                        }
                    }
                }

                if !bars.isEmpty {
                    Section("Results — \(bars.count) bars") {
                        ForEach(bars) { bar in BarRow(bar: bar) }
                    }
                }
            }
            .navigationTitle("\(contract.name) Bars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func loadBars() async {
        isLoading = true
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        bars = await service.retrieveBars(
            contractId:  contract.id,
            live:        useLive,
            startTime:   start,
            endTime:     Date(),
            unit:        selectedUnit,
            unitNumber:  unitNumber,
            limit:       limit
        )
        isLoading = false
    }
}

struct BarRow: View {
    let bar: Bar

    var changeColor: Color { bar.c >= bar.o ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formattedTime(bar.t))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(bar.c, format: .number.precision(.fractionLength(2)))
                    .font(.headline).foregroundStyle(changeColor)
            }
            HStack(spacing: 12) {
                ohlc("O", bar.o)
                ohlc("H", bar.h)
                ohlc("L", bar.l)
                ohlc("C", bar.c)
                Spacer()
                Text("Vol: \(bar.v)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func ohlc(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.caption2).foregroundStyle(.secondary)
        }
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
