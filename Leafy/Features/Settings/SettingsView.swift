import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(DailyReminderCoordinator.self) private var reminders
    @AppStorage(AppearanceMode.storageKey) private var appearanceRawValue = AppearanceMode.light.rawValue
    @State private var browser: SafariDestination?
    @State private var showingSignOutConfirmation = false

    var body: some View {
        List {
            Section {
                if app.isAuthenticated || app.isPreviewMode {
                    NavigationLink { AccountCenterView() } label: { identityHeader }

                    Button {
                        showingSignOutConfirmation = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("settingsSignOutButton")
                } else {
                    Button { app.presentAuthentication() } label: { identityHeader }
                }
            }
            .leafyBorderlessRows()

            Section("Plan & preferences") {
                NavigationLink {
                    PlanView()
                } label: {
                    SettingsValueRow(
                        title: "Nutrition plan",
                        value: app.currentPlan.map { "\($0.calorieTargetKcal) Cal" } ?? "Unavailable",
                        symbol: "target"
                    )
                }
                .accessibilityIdentifier("nutritionPlanLink")

                Picker(selection: $appearanceRawValue) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("appearancePicker")

                Toggle(isOn: Binding(
                    get: { reminders.preferences.isEnabled },
                    set: { enabled in Task { await reminders.setEnabled(enabled) } }
                )) {
                    Label("Morning check-in", systemImage: "bell")
                }
                .accessibilityIdentifier("morningReminderToggle")

                if reminders.preferences.isEnabled {
                    DatePicker(
                        "Reminder time",
                        selection: Binding(
                            get: { reminders.preferences.displayDate },
                            set: { date in Task { await reminders.setTime(date) } }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                if reminders.authorizationState == .denied {
                    Button("Open notification settings") { reminders.openSystemSettings() }
                }
            }
            .leafyBorderlessRows()

            Section("Privacy & support") {
                NavigationLink {
                    DataPrivacyView()
                } label: {
                    Label("Data & Privacy", systemImage: "hand.raised")
                }

                Button { browser = SafariDestination(url: app.configuration.termsURL) } label: {
                    Label("Terms of Use", systemImage: "doc.text")
                }
                Button { browser = SafariDestination(url: app.configuration.supportURL) } label: {
                    Label("Support", systemImage: "questionmark.circle")
                }
            }
            .leafyBorderlessRows()

            Section {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Text("Leafy provides general wellness estimates and is not a substitute for medical care.")
                    Text(versionText)
                }
                .font(LeafyTypography.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, LeafySpacing.medium)
            }
            .leafyBorderlessRows(separators: false)
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.large)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task { await reminders.refresh() }
        .sheet(item: $browser) { SafariWebView(url: $0.url).ignoresSafeArea() }
        .sheet(isPresented: $showingSignOutConfirmation) {
            LeafyConfirmationSheet(
                title: "Sign out?",
                message: "You’ll need to sign in again to access your saved Leafy data on this device.",
                confirmTitle: "Sign out",
                confirmIdentifier: "confirmSignOutButton",
                sheetIdentifier: "signOutConfirmationSheet"
            ) {
                Task { await app.signOut() }
            }
        }
        .overlay {
            if app.saveState == .deleting {
                ProgressView("Deleting account…").padding().background(.regularMaterial, in: .rect(cornerRadius: LeafyRadius.control))
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) { Button("OK") {} } message: { Text(app.errorMessage ?? "") }
    }

    private var identityHeader: some View {
        HStack(spacing: LeafySpacing.medium) {
            Image(systemName: "person.crop.circle.fill")
                .font(LeafyTypography.icon(42, relativeTo: .title))
                .foregroundStyle(LeafyTheme.green)
            VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                Text(app.account?.email ?? (app.isPreviewMode ? "Simulator preview" : "Sign in to Leafy"))
                    .font(LeafyTypography.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(identitySubtitle)
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, LeafySpacing.small)
    }

    private var identitySubtitle: String {
        if app.isPreviewMode { return "Preview account" }
        guard app.isAuthenticated else { return "Access your saved nutrition history" }
        let provider = app.account?.identities.first?.displayName ?? "Leafy account"
        return app.account?.emailConfirmed == true ? "Verified · \(provider)" : "Verification pending · \(provider)"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Leafy \(version) (\(build))"
    }
}
