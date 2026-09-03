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
                    onLogged: { app.showProductScanner = false }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { app.showProductScanner = false }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $app.showProductScannerCamera, onDismiss: {
            app.productScannerCameraDidDismiss()
        }) {
            TodayProductScannerCover()
        }
    }
}

private struct TodayProductScannerCover: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var scannerStatus: BarcodeScannerStatus = .requestingPermission

    var body: some View {
        NavigationStack {
            BarcodeScannerView(onCode: { app.completeProductScannerScan($0) }, onStatusChange: { scannerStatus = $0 })
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { app.cancelProductScanner() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: LeafySpacing.xSmall) {
                        if scannerStatus == .denied {
                            Button("Open Settings") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                openURL(url)
                            }
                            .font(LeafyTypography.subheadlineSemibold)
                            .foregroundStyle(.white)
                            .frame(minHeight: 44)
                        }
                        Button("Search Instead") {
                            app.dismissProductScannerCameraForSearch()
                        }
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, LeafyTheme.pageInset)
                }
        }
    }
}

private enum DashboardTab: Hashable { case today, progress, ai, settings }
