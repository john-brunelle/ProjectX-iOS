import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// BotRemovalSheet
//
// Picker sheet for removing (unassigning) bots
// from an account. Mirrors BotAssignmentSheet.
// ─────────────────────────────────────────────

struct BotRemovalSheet: View {
    let accountId: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(BotRunner.self) private var botRunner

    @Query(sort: \BotConfig.name) private var allBots: [BotConfig]
    @Query private var allAssignments: [AccountBotAssignment]

    /// Bot IDs assigned to this account.
    private var assignedBotIds: Set<UUID> {
        Set(allAssignments.filter { $0.accountId == accountId }.map(\.botId))
    }

    /// Active bots currently assigned to this account.
    private var assignedBots: [BotConfig] {
        allBots.filter { assignedBotIds.contains($0.id) && !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            List {
                if assignedBots.isEmpty {
                    Section {
                        Text("No bots are assigned to this account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Assigned Bots") {
                        ForEach(assignedBots) { bot in
                            Button(role: .destructive) {
                                unassignBot(bot)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bot.name)
                                            .font(.body.weight(.medium))
                                        HStack(spacing: 6) {
                                            Text(bot.contractName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if botRunner.isRunning(bot, accountId: accountId) {
                                                Text("Running")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Remove Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func unassignBot(_ bot: BotConfig) {
        if botRunner.isRunning(bot, accountId: accountId) {
            botRunner.stop(bot: bot, accountId: accountId)
        }
        if let assignment = allAssignments.first(where: { $0.botId == bot.id && $0.accountId == accountId }) {
            modelContext.delete(assignment)
            try? modelContext.save()
        }
    }
}
