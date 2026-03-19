import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(ProjectXService.self) var service
    @Environment(RealtimeService.self) var realtime
    @Environment(BotRunner.self) var botRunner

    @Query private var allBots: [BotConfig]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("The Hub", systemImage: "circle.hexagongrid.fill") }
                .tag(0)
            AccountsTab()
                .tabItem { Label("Accounts",   systemImage: "person.crop.rectangle.stack") }
                .tag(1)
            BotsView()
                .tabItem { Label("Bots",       systemImage: "gearshape.2.fill") }
                .badge(botRunner.runningCount)
                .tag(2)
            IndicatorsView()
                .tabItem { Label("Signals", systemImage: "waveform.path.ecg") }
                .tag(3)
            LiveDashboardView()
                .tabItem { Label("Live",       systemImage: "dot.radiowaves.left.and.right") }
                .tag(4)
            OrdersView()
                .tabItem { Label("Orders",     systemImage: "list.bullet.rectangle") }
                .tag(5)
            PositionsView()
                .tabItem { Label("Positions",  systemImage: "chart.bar.fill") }
                .tag(6)
            TradesView()
                .tabItem { Label("Trades",     systemImage: "chart.xyaxis.line") }
                .tag(7)
            ContractsView()
                .tabItem { Label("Contracts",  systemImage: "doc.text.magnifyingglass") }
                .tag(8)
            NetworkActivityView()
                .tabItem { Label("Network",    systemImage: "network") }
                .tag(9)
            ControlsView()
                .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }
                .tag(10)
            PreferencesView()
                .tabItem { Label("Preferences", systemImage: "gearshape.fill") }
                .tag(11)
        }
        .environment(service)
        .environment(realtime)
        .environment(botRunner)
        .onAppear {
            NetworkLogger.shared.log(NetworkLogger.Entry(
                timestamp: Date(), source: .signalR, method: "DashboardView.onAppear",
                path: "lifecycle", statusCode: nil, duration: nil,
                requestBody: "activeAccount=\(service.activeAccount?.id.description ?? "nil")",
                responseBody: nil, error: nil
            ))
            // Inject model context before any restore/persistence calls
            botRunner.modelContext = modelContext
            NetworkLogger.shared.modelContext = modelContext
            NetworkLogger.shared.restoreEntries()
            // One-time migration: create AccountBotAssignment records from legacy accountId
            migrateBotAssignmentsIfNeeded()
            // Auto-connect user hub when dashboard loads
            if let account = service.activeAccount {
                realtime.connectUserHub(accountId: account.id)
            }
            // Seed contract name cache from bots (they store contractName)
            for bot in allBots {
                service.contractNameCache[bot.contractId] = bot.contractName
            }
            // Restart any bots that were running before a cold start/kill
            botRunner.restoreRunningBots(allBots)
        }
        .onChange(of: service.activeAccount) { _, newAccount in
            NetworkLogger.shared.log(NetworkLogger.Entry(
                timestamp: Date(), source: .signalR, method: "DashboardView.onChange(activeAccount)",
                path: "lifecycle", statusCode: nil, duration: nil,
                requestBody: "newAccountId=\(newAccount?.id.description ?? "nil")",
                responseBody: nil, error: nil
            ))
            guard let account = newAccount else { return }
            realtime.switchAccount(to: account.id)
        }
        .onDisappear {
            NetworkLogger.shared.log(NetworkLogger.Entry(
                timestamp: Date(), source: .signalR, method: "DashboardView.onDisappear",
                path: "lifecycle", statusCode: nil, duration: nil,
                requestBody: nil, responseBody: "dashboard disappeared", error: nil
            ))
            realtime.disconnectAll()
        }
    }

    // MARK: - Migration

    /// One-time migration: creates AccountBotAssignment records from legacy BotConfig.accountId values.
    private func migrateBotAssignmentsIfNeeded() {
        let key = "didMigrateBotAssignments"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let existing = (try? modelContext.fetch(FetchDescriptor<AccountBotAssignment>())) ?? []
        let existingPairs = Set(existing.map { "\($0.accountId)-\($0.botId)" })

        for bot in allBots where bot.accountId != 0 {
            let pair = "\(bot.accountId)-\(bot.id)"
            if !existingPairs.contains(pair) {
                modelContext.insert(AccountBotAssignment(accountId: bot.accountId, botId: bot.id))
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}

struct AccountsTab: View {
    @Environment(ProjectXService.self) var service
    @Environment(RealtimeService.self) var realtime
    @Environment(BotRunner.self) var botRunner

    var isEmbedded: Bool = false

    @State private var isLoading      = false
    @State private var showOnlyActive = true

    @Query private var allProfiles: [AccountProfile]

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if isLoading {
                ProgressView("Loading accounts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.accounts.isEmpty {
                ContentUnavailableView(
                    "No Accounts Found",
                    systemImage: "tray",
                    description: Text("No accounts matched your filter.")
                )
            } else {
                List(service.accounts) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountRow(
                            account: account,
                            isActive: account.id == service.activeAccount?.id,
                            alias: allProfiles.first { $0.accountId == account.id }?.alias ?? "",
                            onAvatarTap: account.id == service.activeAccount?.id ? nil : {
                                service.activeAccount = account
                            }
                        )
                    }
                    .swipeActions(edge: .leading) {
                        if account.id != service.activeAccount?.id {
                            Button {
                                service.activeAccount = account
                            } label: {
                                Label("Set Active", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("My Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Active accounts only", isOn: $showOnlyActive)
                        .onChange(of: showOnlyActive) { _, _ in
                            Task { await reload() }
                        }
                    Divider()
                    Button(role: .destructive) {
                        botRunner.stopAll()
                        realtime.disconnectAll()
                        service.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .navigation) {
                Button { Task { await reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        await service.fetchAccounts(onlyActive: showOnlyActive)
        isLoading = false
    }
}

struct AccountRow: View {
    let account: Account
    var isActive: Bool = false
    var alias: String  = ""
    var onAvatarTap: (() -> Void)? = nil

    private var displayName: String {
        let trimmed = alias.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? account.name : trimmed
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AccountAvatar(accountId: account.id, size: 46)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                        .background(Circle().fill(Color(uiColor: .systemBackground)).padding(1))
                        .offset(x: 4, y: -4)
                }
            }
            .onTapGesture { onAvatarTap?() }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName).font(.headline).lineLimit(1)
                    if account.simulated == true {
                        Text("SIM")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(account.balance, format: .currency(code: "USD"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(account.balance >= 0 ? .green : .red)
                }

                HStack(spacing: 10) {
                    if !alias.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(account.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Label(account.canTrade ? "Can Trade" : "No Trading",
                          systemImage: account.canTrade ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(account.canTrade ? .green : .red)
                        .font(.caption2)
                    Spacer()
                    Text("ID: \(account.id)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
