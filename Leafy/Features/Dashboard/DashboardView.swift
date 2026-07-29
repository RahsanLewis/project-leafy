import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = app.currentPlan {
                    PlanResultsView(plan: plan, isPreview: false).padding(24)
                } else { ProgressView().padding() }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Leafy")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Edit") { app.editPlan() }
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
            }
        }
    }
}

