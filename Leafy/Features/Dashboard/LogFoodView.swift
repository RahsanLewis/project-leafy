import SwiftUI
import UIKit

enum FoodLoggingMethod: String, CaseIterable, Identifiable {
    case search
    case ai
    case manual

    var id: Self { self }

    var label: String {
        switch self {
        case .search: "Scan"
        case .ai: "AI"
        case .manual: "Manual"
        }
    }
}

struct LogFoodView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var method: FoodLoggingMethod
    @State private var searchHasDraft = false
    @State private var aiHasDraft = false
    @State private var manualHasDraft = false
    @State private var showingDiscardConfirmation = false
    @State private var successMessage: String?
    @State private var hasLoggedFood = false
    let initialAIDescription: String

    init(initialMethod: FoodLoggingMethod = .search, initialAIDescription: String = "") {
        _method = State(initialValue: initialMethod)
        self.initialAIDescription = initialAIDescription
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Logging method", selection: $method) {
                    ForEach(FoodLoggingMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, LeafyTheme.pageInset)
                .padding(.top, LeafySpacing.small)
                .padding(.bottom, LeafySpacing.compact)
                .background(LeafyTheme.canvas)
                .accessibilityIdentifier("foodLoggingMethodPicker")

                TabView(selection: $method) {
                    ProductDiscoveryView(
                        intent: .log,
                        embedded: true,
                        onLogged: { handleLogged(method: .search) },
                        hasUnsavedDraft: $searchHasDraft
                    )
                        .tag(FoodLoggingMethod.search)

                    AIMealView(
                        logDate: app.selectedLogDate,
                        embedded: true,
                        initialDescription: initialAIDescription,
                        onSaved: { handleLogged(method: .ai) },
                        hasUnsavedDraft: $aiHasDraft
                    )
                        .tag(FoodLoggingMethod.ai)

                    FoodEntryEditorView(
                        entry: nil,
                        logDate: app.selectedLogDate,
                        embedded: true,
                        onSaved: { handleLogged(method: .manual) },
                        hasUnsavedDraft: $manualHasDraft
                    )
                    .tag(FoodLoggingMethod.manual)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
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
            .confirmationDialog(
                "Discard this food entry?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Entry", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved description, photos, or food details will be lost.")
            }
        }
    }

    private var hasUnsavedDraft: Bool {
        searchHasDraft || aiHasDraft || manualHasDraft
    }

    private func requestDismiss() {
        if hasUnsavedDraft { showingDiscardConfirmation = true }
        else { dismiss() }
    }

    private func handleLogged(method: FoodLoggingMethod) {
        hasLoggedFood = true
        switch method {
        case .search: searchHasDraft = false
        case .ai: aiHasDraft = false
        case .manual: manualHasDraft = false
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(LeafyMotion.state) { successMessage = "Food added" }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(LeafyMotion.state) { successMessage = nil }
        }
    }
}
