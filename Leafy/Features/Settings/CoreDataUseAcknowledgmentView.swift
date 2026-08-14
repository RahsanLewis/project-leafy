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

                    if let error = app.coreDataAcknowledgmentError {
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
        .confirmationDialog("Permanently delete your Leafy account and health history?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await app.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
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
}
