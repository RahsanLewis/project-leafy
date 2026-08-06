import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                WeightView()
            }
            .tabItem { Label("Weight", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack {
                PlanView()
            }
            .tabItem { Label("Plan", systemImage: "target") }

            NavigationStack {
                ProductDiscoveryView(intent: .analyze)
            }
            .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(LeafyTheme.green)
        .sheet(isPresented: $app.showMorningCheckIn, onDismiss: app.dismissMorningCheckIn) {
            MorningCheckInView()
        }
    }
}
