import SwiftUI
import UIKit

struct LogFoodView: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var hasDraft = false
    @State private var showingDiscardConfirmation = false
    @State private var successMessage: String?
    @State private var hasLoggedFood = false
    let initialAIDescription: String

    init(initialAIDescription: String = "") {
        self.initialAIDescription = initialAIDescription
    }

    var body: some View {
        NavigationStack {
            AIMealView(
                logDate: app.selectedLogDate,
                embedded: true,
                initialDescription: initialAIDescription,
                onSaved: handleLogged,
                hasUnsavedDraft: $hasDraft
            )
            .overlay(alignment: .top) {
                if let successMessage {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(LeafyTheme.green)
                        .padding(.horizontal, LeafySpacing.medium)
                        .padding(.vertical, LeafySpacing.small)
                        .background(.regularMaterial, in: .capsule)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                        .padding(.top, LeafySpacing.xSmall)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                        .accessibilityIdentifier("foodLogSuccessMessage")
                }
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(hasLoggedFood ? "Done" : "Cancel") { requestDismiss() }
                }
            }
            .interactiveDismissDisabled(hasUnsavedDraft)
            .sheet(isPresented: $showingDiscardConfirmation) {
                LeafyConfirmationSheet(
                    title: "Discard this food entry?",
                    message: "Your unsaved description, photos, or food details will be lost.",
                    confirmTitle: "Discard Entry",
                    isDestructive: true,
                    confirmIdentifier: "confirmDiscardFoodEntryButton",
                    cancelTitle: "Keep Editing",
                    sheetIdentifier: "discardFoodEntryConfirmationSheet"
                ) { dismiss() }
            }
        }
    }

    private var hasUnsavedDraft: Bool { hasDraft }

    private func requestDismiss() {
        if hasUnsavedDraft { showingDiscardConfirmation = true }
        else { dismiss() }
    }

    private func handleLogged() {
        hasLoggedFood = true
        hasDraft = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(LeafyMotion.state) { successMessage = "Food added" }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(LeafyMotion.state) { successMessage = nil }
        }
    }
}
