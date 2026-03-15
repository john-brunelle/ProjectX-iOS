import SwiftUI

struct DashboardView: View {
    @Environment(ProjectXService.self) var service
    @Environment(RealtimeService.self) var realtime
    @Environment(BotRunner.self) var botRunner

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home",       systemImage: "house.fill") }
                .tag(0)
            LiveDashboardView()
                .tabItem { Label("Live",       systemImage: "dot.radiowaves.left.and.right") }
                .tag(1)
            BotsView()
                .tabItem { Label("Bots",       systemImage: "gearshape.2.fill") }
                .badge(botRunner.runningCount)
                .tag(2)
            IndicatorsView()
                .tabItem { Label("Indicators", systemImage: "waveform.path.ecg") }
                .tag(3)
            AccountsTab()
                .tabItem { Label("Accounts",   systemImage: "person.crop.rectangle.stack") }
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
            ThemesView()
                .tabItem { Label("Themes",     systemImage: "paintbrush.fill") }
                .tag(9)
        }
        .environment(service)
        .environment(realtime)
        .environment(botRunner)
        .onAppear {
            // Auto-connect user hub when dashboard loads
            if let account = service.accounts.first {
                realtime.connectUserHub(accountId: account.id)
            }
        }
        .onDisappear {
            botRunner.stopAll()
            realtime.disconnectAll()
        }
    }
}

struct AccountsTab: View {
    @Environment(ProjectXService.self) var service
    @Environment(RealtimeService.self) var realtime
    @Environment(BotRunner.self) var botRunner

    var isEmbedded: Bool = false

    @State private var isLoading      = false
    @State private var showOnlyActive = true

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
                    AccountRow(account: account)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.name).font(.headline)
                Spacer()
                Text(account.balance, format: .currency(code: "USD"))
                    .font(.headline)
                    .foregroundStyle(account.balance >= 0 ? .green : .red)
            }
            HStack(spacing: 12) {
                Label(account.canTrade ? "Can Trade" : "No Trading",
                      systemImage: account.canTrade ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(account.canTrade ? .green : .red).font(.caption)
                Label(account.isVisible ? "Visible" : "Hidden",
                      systemImage: account.isVisible ? "eye.fill" : "eye.slash.fill")
                    .foregroundStyle(.secondary).font(.caption)
                Spacer()
                Text("ID: \(account.id)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
