import SwiftUI

@main struct LeafyApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            Group {
                switch model.route {
                case .onboarding: OnboardingView()
                case .dashboard: DashboardView()
                }
            }
            .environment(model)
            .tint(LeafyTheme.green)
            .task { await model.restore() }
        }
    }
}

