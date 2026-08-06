import SwiftUI

@main struct LeafyApp: App {
    @UIApplicationDelegateAdaptor(LeafyAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var reminders = DailyReminderCoordinator()

    var body: some Scene {
        WindowGroup {
            Group {
                switch model.route {
                case .launching:
                    ZStack {
                        Color(.systemGroupedBackground).ignoresSafeArea()
                        ProgressView("Loading Leafy…")
                    }
                case .onboarding: OnboardingView()
                case .dashboard: DashboardView()
                }
            }
            .font(LeafyTypography.body)
            .environment(model)
            .environment(reminders)
            .tint(LeafyTheme.green)
            .task {
                await model.restore()
                await reminders.refresh()
                openPendingMorningCheckIn()
            }
            .onReceive(NotificationCenter.default.publisher(for: .leafyOpenMorningCheckIn)) { _ in
                openPendingMorningCheckIn()
            }
            .onChange(of: model.route) { _, route in
                if route == .dashboard { openPendingMorningCheckIn() }
            }
        }
    }

    private func openPendingMorningCheckIn() {
        guard model.route == .dashboard, reminders.consumePendingMorningCheckIn() else { return }
        model.presentMorningCheckIn()
    }
}
