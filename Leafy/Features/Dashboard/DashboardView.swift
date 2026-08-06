import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: DashboardTab = .home

    var body: some View {
        @Bindable var app = app
        TabView(selection: $selection) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(DashboardTab.home)

            NavigationStack {
                WeightView()
            }
            .tabItem { Label("Weight", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(DashboardTab.weight)

            NavigationStack {
                AIMealView { selection = .home }
            }
            .tabItem { Label("AI", systemImage: "sparkles") }
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
        .sheet(isPresented: $app.showMorningCheckIn, onDismiss: app.dismissMorningCheckIn) {
            MorningCheckInView()
        }
    }
}

private enum DashboardTab: Hashable { case home, weight, ai, scan, settings }
