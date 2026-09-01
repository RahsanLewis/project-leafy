import SwiftUI

struct CoreDataUseAcknowledgmentView: View {
    @Environment(AppModel.self) private var app
    @State private var showDeleteConfirmation = false
    @State private var browser: SafariDestination?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                    Image(systemName: "lock.shield.fill")
                        .font(LeafyTypography.icon(38, relativeTo: .largeTitle))
                        .foregroundStyle(LeafyTheme.green)

                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        Text("How Leafy uses your data")
                            .font(LeafyTypography.largeTitle)
                        Text("Leafy needs to store and analyze your information to calculate targets, sync your history, and personalize guidance.")
                            .font(LeafyTypography.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: LeafySpacing.medium) {
                        acknowledgmentRow("Nutrition plans and preferences", icon: "target")
                        acknowledgmentRow("Food logs, servings, and corrections", icon: "fork.knife")
                        acknowledgmentRow("Weight history and progress", icon: "scalemass")
                    }

                    Text("Leafy uses this information only to operate your account and personalize your experience. Leafy does not sell your health data.")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Read the Privacy Policy") {
                        browser = SafariDestination(url: app.configuration.privacyURL)
                    }
                        .font(LeafyTypography.headline)

                    if let error = app.errorMessage ?? app.coreDataAcknowledgmentError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(LeafyTheme.pageInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LeafyTheme.canvas)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: LeafySpacing.compact) {
                    Button(primaryActionTitle) {
                        Task { await app.acceptCoreDataUse() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(app.isCoreDataAcknowledgmentLoading)
                    .accessibilityIdentifier("acceptCoreDataUseButton")

                    Menu("Other options") {
                        Button("Sign out") { Task { await app.signOut() } }
                        Button("Delete account", role: .destructive) { showDeleteConfirmation = true }
                    }
                    .font(LeafyTypography.button)
                }
                .leafyDetachedBottomControl()
            }
        }
        .interactiveDismissDisabled()
        .sheet(item: $browser) { SafariWebView(url: $0.url).ignoresSafeArea() }
        .sheet(isPresented: $showDeleteConfirmation) {
            LeafyConfirmationSheet(
                title: "Permanently delete your Leafy account?",
                message: coreDataDeletionMessage,
                confirmTitle: "Delete account",
                isDestructive: true,
                confirmIdentifier: "confirmCoreDataAccountDeletionButton",
                sheetIdentifier: "coreDataAccountDeletionConfirmationSheet"
            ) {
                Task { await app.deleteAccount() }
            }
        }
        .overlay {
            if app.saveState == .deleting {
                ProgressView("Deleting account…").padding().background(.regularMaterial, in: .rect(cornerRadius: LeafyRadius.control))
            }
        }
        .accessibilityIdentifier("coreDataUseAcknowledgment")
    }

    private func acknowledgmentRow(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(LeafyTypography.bodyMedium)
            .foregroundStyle(.primary)
    }

    private var primaryActionTitle: String {
        if app.isCoreDataAcknowledgmentLoading { return "Saving…" }
        if app.coreDataAcknowledgmentError != nil { return "Try again" }
        return "Accept and continue"
    }

    private var coreDataDeletionMessage: String {
        var message = "This permanently removes your profile, plans, food logs, and weight history."
        if app.account?.hasAppleIdentity == true {
            message += " Next, confirm with Sign in with Apple."
        }
        return message
    }
}
