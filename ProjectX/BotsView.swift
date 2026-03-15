import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// Bots Tab — Placeholder
//
// Phase 2 will add: bot wizard, bot library,
// start/stop controls, and live status.
// ─────────────────────────────────────────────

struct BotsView: View {
    @Query(sort: \BotConfig.updatedAt, order: .reverse)
    private var bots: [BotConfig]

    var body: some View {
        NavigationStack {
            Group {
                if bots.isEmpty {
                    ContentUnavailableView(
                        "No Bots Yet",
                        systemImage: "gearshape.2.fill",
                        description: Text("Bot wizard coming soon. Build your indicators first!")
                    )
                } else {
                    List(bots) { bot in
                        BotRow(bot: bot)
                    }
                }
            }
            .navigationTitle("Bots")
        }
    }
}

// MARK: - Bot Row (basic, will be enhanced in Phase 2)

struct BotRow: View {
    let bot: BotConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bot.name)
                    .font(.headline)
                Spacer()
                Label(bot.status.displayName, systemImage: bot.status.systemImage)
                    .font(.caption)
                    .foregroundStyle(bot.status == .running ? .green : .secondary)
            }
            HStack(spacing: 12) {
                Text(bot.contractName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(bot.barSizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(bot.indicators.count) indicator\(bot.indicators.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
