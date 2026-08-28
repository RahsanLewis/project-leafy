import SwiftUI

struct DashboardView: View {
    @Environment(AppCoordinator.self) private var app
    @State private var selection: DashboardTab = .today

    var body: some View {
        @Bindable var app = app
        TabView(selection: $selection) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Today", systemImage: "calendar") }
            .tag(DashboardTab.today)

            NavigationStack {
                WeightView()
            }
            .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(DashboardTab.progress)

            NavigationStack {
                AskLeafyView()
            }
            .tabItem { Label("Ask", systemImage: "sparkles") }
            .tag(DashboardTab.ai)

            NavigationStack {
                ProductDiscoveryView(intent: .analyze)
            }
            .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
            .tag(DashboardTab.scan)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(DashboardTab.settings)
        }
        .tint(LeafyTheme.green)
        .sheet(isPresented: $app.showMorningCheckIn, onDismiss: {
            Task { await app.morningCheckInSheetDidDismiss() }
        }) {
            MorningCheckInView()
        }
        .sheet(isPresented: $app.showLogFood, onDismiss: {
            Task { await app.mealLoggerDidDismiss() }
        }) {
            LogFoodView(initialAIDescription: app.pendingMealDescription)
        }
    }
}

private enum DashboardTab: Hashable { case today, progress, ai, scan, settings }
