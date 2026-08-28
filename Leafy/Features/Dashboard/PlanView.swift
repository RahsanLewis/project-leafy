import SwiftUI

struct PlanView: View {
    @Environment(AppCoordinator.self) private var app
    @State private var showingEditor = false
    @State private var updateConfirmation = false

    var body: some View {
        Group {
            if let plan = app.currentPlan {
                PlanResultsView(plan: plan, input: app.draft.input, isPreview: false)
            } else {
                ContentUnavailableView("Plan unavailable", systemImage: "target", description: Text("Update your answers to create a nutrition plan."))
                    .padding(.top, 80)
            }
        }
        .background(LeafyTheme.canvas)
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .fullScreenCover(isPresented: $showingEditor) {
            PlanEditView { updateConfirmation = true }
        }
        .overlay(alignment: .top) {
            if updateConfirmation {
                Label("Plan updated", systemImage: "checkmark.circle.fill")
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                    .padding(.horizontal, LeafySpacing.medium)
                    .padding(.vertical, LeafySpacing.compact)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.top, LeafySpacing.small)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(LeafyMotion.state) { updateConfirmation = false }
                    }
            }
        }
    }
}
