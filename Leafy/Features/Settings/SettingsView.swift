import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(DailyReminderCoordinator.self) private var reminders
    @State private var confirmDeletion = false
    var body: some View {
        List {
            Section("Account") {
                if app.isPreviewMode {
                    Label("Simulator preview — no account session", systemImage: "hammer")
                        .foregroundStyle(.secondary)
                } else if app.isAuthenticated {
                    Button("Sign out") { Task { await app.signOut() } }
                    Button("Delete account", role: .destructive) { confirmDeletion = true }
                } else {
                    Button("Sign in") { app.presentAuthentication(.accessExistingAccount) }
                }
            }
            .leafyBorderlessRows()
            Section("Personalized targets") {
                NavigationLink {
                    PlanView()
                } label: {
                    LabeledContent("Nutrition plan", value: app.currentPlan.map { "\($0.calorieTargetKcal) Cal" } ?? "Unavailable")
                }
                Label("Leafy uses your confirmed food logs and weight history to learn how your calorie budget fits your body over time.", systemImage: "wand.and.stars")
                Text("Your data personalizes your targets only. Leafy does not show an estimated daily calories-burned number, and weekly budget changes are limited to 100 calories.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .leafyBorderlessRows()
            Section("Daily reminder") {
                Toggle("Morning check-in", isOn: Binding(
                    get: { reminders.preferences.isEnabled },
                    set: { enabled in Task { await reminders.setEnabled(enabled) } }
                ))
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
                    Button("Open iOS Settings") { reminders.openSystemSettings() }
                }

                Text(reminders.authorizationState.description)
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)

                if let reminderError = reminders.errorMessage {
                    Text(reminderError)
                        .font(LeafyTypography.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .leafyBorderlessRows()
            Section("Your data") {
                NavigationLink {
                    DataContributionView()
                } label: {
                    LabeledContent("Nutrition data program") {
                        if app.isDataContributionLoading {
                            ProgressView()
                        } else {
                            Text(app.dataContributionStatus?.isParticipating == true ? "Joined" : "Not joined")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Commercial data participation is optional and separate from personalized targets.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .leafyBorderlessRows()
            Section("Legal and support") {
                Link("Privacy Policy", destination: app.configuration.privacyURL)
                Link("Terms of Use", destination: app.configuration.termsURL)
                Link("Support", destination: app.configuration.supportURL)
            }
            .leafyBorderlessRows()
            Section { Text("Leafy provides general wellness estimates and is not a substitute for medical care.").font(LeafyTypography.footnote) }
                .leafyBorderlessRows(separators: false)
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.large)
        .navigationTitle("Settings")
        .task {
            async let contribution: Void = app.loadDataContributionStatus()
            async let reminder: Void = reminders.refresh()
            _ = await (contribution, reminder)
        }
        .confirmationDialog("Permanently delete your Leafy account and all plan history?", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await app.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        }
        .overlay { if app.saveState == .deleting { ProgressView("Deleting account…").padding().background(.regularMaterial, in: .rect(cornerRadius: 16)) } }
        .alert("Deletion failed", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("OK") {} } message: { Text(app.errorMessage ?? "") }
    }
}
