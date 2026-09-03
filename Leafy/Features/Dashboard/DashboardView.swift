import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
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
        .sheet(isPresented: $app.showProductScanner) {
            NavigationStack {
                ProductDiscoveryView(
                    intent: .analyze,
                    startsWithScanner: true,
                    onScannerCancelled: { app.showProductScanner = false },
                    onLogged: { app.showProductScanner = false }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { app.showProductScanner = false }
                    }
                }
            }
        }
    }
}

private enum DashboardTab: Hashable { case today, progress, ai, settings }
