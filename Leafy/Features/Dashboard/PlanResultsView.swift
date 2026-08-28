import SwiftUI

struct PlanResultsView: View {
    @Environment(AppCoordinator.self) private var app
    let plan: NutritionPlan
    let input: NutritionPlanInput
    let isPreview: Bool
    @State private var showingCalculation = false

    var body: some View {
        ScrollView {
            planContent
                .padding(.horizontal, LeafyTheme.pageInset)
                .padding(.top, isPreview ? LeafySpacing.xLarge : LeafySpacing.medium)
                .padding(.bottom, isPreview ? LeafySpacing.xLarge : LeafySpacing.large)
        }
        .background(LeafyTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            if isPreview { onboardingActions }
        }
        .sheet(isPresented: $showingCalculation) {
            PlanCalculationView(plan: plan, input: input)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { app.errorMessage != nil && !app.showAuthentication },
                set: { if !$0 && !app.showAuthentication { app.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
        .accessibilityIdentifier(isPreview ? "onboardingPlanResults" : "planResults")
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text(isPreview ? "Your plan is ready" : "Your daily targets")
                    .font(LeafyTypography.largeTitle)
                Text("A practical starting point based on the information you shared.")
                    .font(LeafyTypography.body)
                    .foregroundStyle(.secondary)
            }

            calorieTarget
            macroTargets
            Divider().overlay(LeafyTheme.hairline)
            goalSummary

            Button {
                showingCalculation = true
            } label: {
                HStack(spacing: LeafySpacing.medium) {
                    VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                        Text("How targets are set")
                            .font(LeafyTypography.headline)
                            .foregroundStyle(.primary)
                        Text("See your energy estimate and goal adjustment")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(LeafyTypography.icon(13))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: LeafyTheme.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("showPlanCalculation")

            Text("For general wellness only. Leafy does not provide medical advice.")
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var calorieTarget: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Daily calories")
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: LeafySpacing.xSmall) {
                Text(plan.calorieTargetKcal.formatted())
                    .font(LeafyTypography.metric(54, extraBold: true))
                    .monospacedDigit()
                Text("Cal")
                    .font(LeafyTypography.title3)
                    .foregroundStyle(.secondary)
            }
            Text("per day")
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily calorie target, \(plan.calorieTargetKcal) calories per day")
        .accessibilityIdentifier("planCalorieTarget")
    }

    private var macroTargets: some View {
        HStack(alignment: .top, spacing: 0) {
            macroDatum("Protein", value: plan.proteinG)
            macroDatum("Carbs", value: plan.carbohydrateG)
            macroDatum("Fat", value: plan.fatG)
        }
        .accessibilityIdentifier("planMacroTargets")
    }

    private func macroDatum(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text("\(value) g")
                .font(LeafyTypography.title2)
                .monospacedDigit()
            Text(label)
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value) grams")
    }

    @ViewBuilder private var goalSummary: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            Text("Your goal")
                .font(LeafyTypography.title3)

            if input.goal == .maintain {
                goalDatum("Direction", value: "Maintain your current weight")
            } else {
                HStack(alignment: .top, spacing: LeafySpacing.large) {
                    goalDatum("Direction", value: input.goal == .lose ? "Lose weight" : "Gain weight")
                    goalDatum("Projected pace", value: directionalWeeklyChange)
                }
                if let date = plan.estimatedGoalDate {
                    VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                        Text("Estimated goal")
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.secondary)
                        Text(date.formatted(date: .long, time: .omitted))
                            .font(LeafyTypography.headline)
                        Text("A projection, not a deadline.")
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("planGoalSummary")
    }

    private func goalDatum(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text(label)
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(LeafyTypography.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onboardingActions: some View {
        VStack(spacing: LeafySpacing.compact) {
            Button(app.isConfigured ? "Save my plan" : "Preview complete") {
                Task {
                    if await app.service.currentUserID() != nil {
                        do { try await app.saveAuthenticatedDraft() }
                        catch { app.errorMessage = error.localizedDescription }
                    } else {
                        app.draft.step = .account
                        await app.persistPendingOnboarding()
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!app.isConfigured)
            .accessibilityIdentifier("savePlanButton")

            Button("Adjust answers") { app.draft.step = .goal }
                .font(LeafyTypography.button)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("adjustPlanAnswers")

            if !app.isConfigured {
                Text("Add your Supabase values to Config/Base.xcconfig to enable sign-in and cloud saving.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .leafyDetachedBottomControl()
    }

    private var directionalWeeklyChange: String {
        let amount = input.unitSystem == .imperial
            ? plan.projectedWeeklyChangeKG * 2.20462
            : plan.projectedWeeklyChangeKG
        let number = input.unitSystem == .imperial
            ? String(format: "%.1f", amount)
            : String(format: "%.2f", amount)
        return "\(number) \(input.unitSystem == .imperial ? "lb" : "kg") per week"
    }
}

private struct PlanCalculationView: View {
    @Environment(AppCoordinator.self) private var app
    let plan: NutritionPlan
    let input: NutritionPlanInput

    var body: some View {
        LeafyInfoSheet(
            title: "How targets are set",
            dismissIdentifier: "dismissPlanCalculation"
        ) {
            Text("Leafy combines a resting-energy equation with your activity estimate and selected goal.")
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                calculationRow("Resting energy", value: "\(plan.bmrKcal.formatted()) Cal")
                Divider().overlay(LeafyTheme.hairline)
                calculationRow("Estimated maintenance", value: "\(plan.tdeeKcal.formatted()) Cal")
                Divider().overlay(LeafyTheme.hairline)
                calculationRow(adjustmentLabel, value: adjustmentValue)
                Divider().overlay(LeafyTheme.hairline)
                calculationRow("Activity estimate", value: input.activityLevel.title)
                Divider().overlay(LeafyTheme.hairline)
                calculationRow("Goal pace", value: input.goal == .maintain ? "Maintain" : input.pace.title)
            }

            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("Protein target")
                    .font(LeafyTypography.headline)
                Text(proteinExplanation)
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Leafy uses the Mifflin–St Jeor equation. Energy needs and weight changes vary, so these targets are a practical starting point rather than a medical prescription.")
                .font(LeafyTypography.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("planCalculationView")
    }

    private func calculationRow(_ label: String, value: String) -> some View {
        LabeledContent(label, value: value)
            .font(LeafyTypography.body)
            .frame(minHeight: LeafyTheme.rowMinHeight)
            .accessibilityIdentifier("planCalculation-\(label.replacingOccurrences(of: " ", with: "-"))")
    }

    private var adjustmentCalories: Int { plan.calorieTargetKcal - plan.tdeeKcal }
    private var adjustmentLabel: String {
        switch input.goal {
        case .lose: "Daily deficit"
        case .gain: "Daily surplus"
        case .maintain: "Daily adjustment"
        }
    }
    private var adjustmentValue: String {
        input.goal == .maintain ? "No adjustment" : "\(abs(adjustmentCalories).formatted()) Cal"
    }
    private var proteinExplanation: String {
        if input.goal == .maintain {
            return "Based on your body weight, with room for a balanced mix of carbohydrates and fat."
        }
        return "Set higher relative to body weight to support lean mass while your weight changes."
    }
}
