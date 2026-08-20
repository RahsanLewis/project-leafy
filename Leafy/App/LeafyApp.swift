import GoogleSignIn
import SwiftUI

@main struct LeafyApp: App {
    @UIApplicationDelegateAdaptor(LeafyAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var reminders = DailyReminderCoordinator()
    @State private var appLock = AppLockCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceMode.storageKey) private var appearanceRawValue = AppearanceMode.light.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                switch model.route {
                case .launching: LaunchLoadingView()
                case .onboarding: OnboardingView()
                case .dashboard: DashboardView()
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
                _ = await (restoration, reminderRefresh)
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
        guard model.route == .dashboard, !model.showCoreDataAcknowledgment,
              reminders.consumePendingMorningCheckIn() else { return }
        model.presentMorningCheckIn()
    }
}

private struct LaunchLoadingView: View {
    @State private var showProgress = false

    var body: some View {
        ZStack {
            LeafyTheme.canvas.ignoresSafeArea()
            if showProgress {
                ProgressView()
                    .tint(LeafyTheme.green)
                    .accessibilityLabel("Loading Leafy")
            }
        }
        .task {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            showProgress = true
        }
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
