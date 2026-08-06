import SwiftUI

struct PlanResultsView: View {
    @Environment(AppModel.self) private var app
    let plan: NutritionPlan
    let isPreview: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isPreview ? "Your plan is ready" : "Your daily targets").font(.largeTitle.bold())
                Text("A practical starting point based on the information you shared.").foregroundStyle(.secondary)
            }
            calorieCard
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 12) {
                MacroCard(value: plan.proteinG, label: "Protein", color: .blue)
                MacroCard(value: plan.carbohydrateG, label: "Carbs", color: .orange)
                MacroCard(value: plan.fatG, label: "Fat", color: .purple)
            }
            if let date = plan.estimatedGoalDate {
                Label("Estimated goal date: \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            DisclosureGroup("How we calculated this", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Resting energy (BMR)", value: "\(plan.bmrKcal) kcal")
                    LabeledContent("Estimated maintenance (TDEE)", value: "\(plan.tdeeKcal) kcal")
                    LabeledContent("Projected weekly change", value: weeklyChange)
                    Text("Leafy uses the Mifflin–St Jeor equation, your activity estimate, and your selected goal pace. Real energy needs and weight changes vary.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }.tint(LeafyTheme.green)
            Text("For general wellness only. Leafy does not provide medical advice.").font(.caption).foregroundStyle(.secondary)
            if isPreview {
                Button(app.isConfigured ? "Save my plan" : "Preview complete") {
                    Task {
                        if await app.service.currentUserID() != nil {
                            do { try await app.saveAuthenticatedDraft() } catch { app.errorMessage = error.localizedDescription }
                        } else { app.presentAuthentication(.savePlan) }
                    }
                }.buttonStyle(PrimaryButtonStyle()).disabled(!app.isConfigured)
                if !app.isConfigured {
                    Text("Add your Supabase values to Config/Base.xcconfig to enable sign-in and cloud saving.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Button("Adjust answers") { app.draft.step = .goal }.frame(maxWidth: .infinity)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { app.errorMessage != nil && !app.showAuthentication }, set: { if !$0 && !app.showAuthentication { app.errorMessage = nil } })) {
            Button("OK", role: .cancel) { app.errorMessage = nil }
        } message: { Text(app.errorMessage ?? "") }
    }

    private var calorieCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily calories").font(.subheadline).foregroundStyle(.secondary)
            Text(plan.calorieTargetKcal.formatted()).font(.system(size: 48, weight: .bold, design: LeafyTheme.fontDesign)) + Text(" kcal").font(.title3).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(LeafyTheme.mint, in: .rect(cornerRadius: 20))
    }

    private var weeklyChange: String {
        let kg = plan.projectedWeeklyChangeKG
        return app.draft.unitSystem == .imperial ? String(format: "%.1f lb", kg * 2.20462) : String(format: "%.2f kg", kg)
    }
}

private struct MacroCard: View {
    let value: Int; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 6) { Text("\(value)g").font(.title2.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(.vertical, 18).background(color.opacity(0.10), in: .rect(cornerRadius: 16))
    }
}
