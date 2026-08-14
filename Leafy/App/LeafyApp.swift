import GoogleSignIn
import SwiftUI

@main struct LeafyApp: App {
    @UIApplicationDelegateAdaptor(LeafyAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var reminders = DailyReminderCoordinator()
    @State private var appLock = AppLockCoordinator()
    @Environment(\.scenePhase) private var scenePhase
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
            .environment(appLock)
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { appLock.sceneDidEnterBackground() }
                if phase == .active { appLock.sceneDidBecomeActive() }
            }
            .overlay {
                if appLock.isLocked {
                    AppLockView()
                        .environment(appLock)
                }
            }
            .sheet(isPresented: Bindable(model).showPasswordRecovery) {
                PasswordRecoveryView(initialMode: .choosePassword)
            }
            .fullScreenCover(isPresented: Bindable(model).showCoreDataAcknowledgment) {
                CoreDataUseAcknowledgmentView()
                    .environment(model)
            }
            .onOpenURL { url in
                if !GIDSignIn.sharedInstance.handle(url) {
                    Task { await model.handleIncomingURL(url) }
                }
            }
        }
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRawValue) ?? .light
    }

    private func openPendingMorningCheckIn() {
        guard splashCompleted, model.route == .dashboard, !model.showCoreDataAcknowledgment,
              reminders.consumePendingMorningCheckIn() else { return }
        model.presentMorningCheckIn()
    }
}

private struct AppLockView: View {
    @Environment(AppLockCoordinator.self) private var appLock

    var body: some View {
        ZStack {
            LeafyTheme.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "leaf.fill").font(.system(size: 56)).foregroundStyle(LeafyTheme.green)
                Text("Leafy is locked").font(LeafyTypography.title)
                Button("Unlock with \(appLock.biometricName)") { Task { await appLock.unlock() } }
                    .buttonStyle(PrimaryButtonStyle())
            }.padding(30)
        }
    }
}
