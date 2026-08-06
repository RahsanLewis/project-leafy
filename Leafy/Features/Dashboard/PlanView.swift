import SwiftUI

struct PlanView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            if let plan = app.currentPlan {
                PlanResultsView(plan: plan, isPreview: false)
                    .padding(20)
            } else {
                ContentUnavailableView("Plan unavailable", systemImage: "target", description: Text("Update your answers to create a nutrition plan."))
                    .padding(.top, 80)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { app.editPlan() }
            }
        }
    }
}
