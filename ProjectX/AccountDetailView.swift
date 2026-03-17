import SwiftUI
import SwiftData

// ─────────────────────────────────────────────
// AccountDetailView
//
// Shows account details, lets the user set an
// alias nickname, and displays a generated avatar.
// ─────────────────────────────────────────────

struct AccountDetailView: View {
    let account: Account

    @Environment(\.modelContext) private var modelContext
    @Environment(ProjectXService.self)  var service

    // Query only the profile for this account
    @Query private var profiles: [AccountProfile]

    @State private var alias = ""
    @FocusState private var aliasFocused: Bool

    private var profile: AccountProfile? { profiles.first }
    private var isActive: Bool { service.activeAccount?.id == account.id }
    private var displayName: String {
        let trimmed = alias.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? account.name : trimmed
    }

    init(account: Account) {
        self.account = account
        let id = account.id
        _profiles = Query(filter: #Predicate<AccountProfile> { $0.accountId == id })
    }

    var body: some View {
        List {
            // ── Hero ──────────────────────────
            Section {
                VStack(spacing: 14) {
                    AccountAvatar(accountId: account.id, size: 96)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                    VStack(spacing: 4) {
                        Text(displayName)
                            .font(.title2.weight(.semibold))
                        if !alias.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(account.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            if account.simulated == true {
                                Text("SIM")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // ── Active Account Toggle ────────
                    if isActive {
                        Label("Active Account", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.green, in: Capsule())
                    } else if account.canTrade {
                        Button {
                            service.activeAccount = account
                        } label: {
                            Label("Set as Active Account", systemImage: "arrow.right.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(.blue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            // ── Nickname ──────────────────────
            Section {
                HStack {
                    TextField("Add a nickname…", text: $alias)
                        .focused($aliasFocused)
                        .onChange(of: alias) { _, newValue in
                            saveAlias(newValue)
                        }
                    if !alias.isEmpty {
                        Button {
                            alias = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Nickname")
            } footer: {
                Text("A personal label shown instead of the account name throughout the app.")
            }

            // ── Account Details ───────────────
            Section("Account Details") {
                detailRow("Account Name", account.name)
                detailRow("Account ID",   "\(account.id)")
                detailRow("Balance",      account.balance.formatted(.currency(code: "USD")))
                detailRow("Type",         account.simulated == true ? "Simulated" : "Live")
                HStack {
                    Text("Trading").foregroundStyle(.secondary)
                    Spacer()
                    Label(
                        account.canTrade ? "Enabled" : "Disabled",
                        systemImage: account.canTrade ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(account.canTrade ? .green : .red)
                    .font(.subheadline)
                }
                HStack {
                    Text("Visibility").foregroundStyle(.secondary)
                    Spacer()
                    Label(
                        account.isVisible ? "Visible" : "Hidden",
                        systemImage: account.isVisible ? "eye.fill" : "eye.slash.fill"
                    )
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }
            }

        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureProfile()
            alias = profile?.alias ?? ""
        }
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func ensureProfile() {
        guard profile == nil else { return }
        modelContext.insert(AccountProfile(accountId: account.id))
    }

    private func saveAlias(_ value: String) {
        guard let p = profile else { return }
        p.alias = value
        try? modelContext.save()
    }
}
