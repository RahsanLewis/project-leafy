import SwiftUI

@main struct LeafyApp: App {
    @UIApplicationDelegateAdaptor(LeafyAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var reminders = DailyReminderCoordinator()
    @State private var splashCompleted = ProcessInfo.processInfo.arguments.contains("-SkipBrandSplash")
    @AppStorage(AppearanceMode.storageKey) private var appearanceRawValue = AppearanceMode.light.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if splashCompleted {
                    switch model.route {
                    case .launching:
                        ZStack {
                            LeafyTheme.canvas.ignoresSafeArea()
                            ProgressView("Loading Leafy…")
                        }
                    case .onboarding: OnboardingView()
                    case .dashboard: DashboardView()
                    }
                } else {
                    LeafySplashView()
                        .transition(.opacity)
                }
            }
            .font(LeafyTypography.body)
            .preferredColorScheme(appearanceMode.preferredColorScheme)
            .environment(model)
            .environment(reminders)
            .tint(LeafyTheme.green)
            .task {
                async let restoration: Void = model.restore()
                async let reminderRefresh: Void = reminders.refresh()
                if !splashCompleted {
                    let splashMilliseconds = ProcessInfo.processInfo.arguments.contains("-HoldBrandSplash") ? 4_000 : 1_200
                    try? await Task.sleep(for: .milliseconds(splashMilliseconds))
                }
                _ = await (restoration, reminderRefresh)
                if !splashCompleted {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        splashCompleted = true
                    }
                }
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

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRawValue) ?? .light
    }

    private func openPendingMorningCheckIn() {
        guard splashCompleted, model.route == .dashboard, reminders.consumePendingMorningCheckIn() else { return }
        model.presentMorningCheckIn()
    }
}
