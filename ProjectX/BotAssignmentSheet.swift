import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// BotAssignmentSheet
//
// Picker sheet for assigning existing bots to an
// account, or creating a new bot. Used by both
// HomeView and AccountDetailView.
// ─────────────────────────────────────────────

struct BotAssignmentSheet: View {
    let accountId: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BotConfig.name) private var allBots: [BotConfig]
    @Query private var allAssignments: [AccountBotAssignment]

    @State private var showBotWizard = false

    /// Bot IDs already assigned to this account.
    private var assignedBotIds: Set<UUID> {
        Set(allAssignments.filter { $0.accountId == accountId }.map(\.botId))
    }

    /// Active bots not yet assigned to this account.
    private var unassignedBots: [BotConfig] {
        allBots.filter { !assignedBotIds.contains($0.id) && $0.isActive && !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            List {
                if unassignedBots.isEmpty {
                    Section {
                        Text("All bots are already assigned to this account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Available Bots") {
                        ForEach(unassignedBots) { bot in
                            Button {
                                assignBot(bot)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bot.name)
                                            .font(.body.weight(.medium))
                                        Text(bot.contractName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }

                Section {
                    Button {
                        showBotWizard = true
                    } label: {
                        Label("Create New Bot", systemImage: "plus.square.fill")
                    }
                }
            }
            .navigationTitle("Add Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showBotWizard) {
                BotWizardView(assignToAccountId: accountId)
            }
        }
    }

    private func assignBot(_ bot: BotConfig) {
        modelContext.insert(AccountBotAssignment(accountId: accountId, botId: bot.id))
        try? modelContext.save()
    }
}
