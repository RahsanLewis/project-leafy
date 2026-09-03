import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showWhySex = false

    var body: some View {
        @Bindable var draft = app.draft
        NavigationStack {
            Group {
                if draft.step == .welcome {
                    welcomeContent
                } else if draft.step == .results {
                    PlanResultsView(plan: app.preview!, input: app.draft.input, isPreview: true)
                } else if draft.step == .account {
                    ScrollView { AccountCreationView().padding(LeafyTheme.pageInset) }
                        .scrollDismissesKeyboard(.interactively)
                } else {
                    questionFlow
                }
            }
            .background(LeafyTheme.canvas)
            .toolbar {
            }
            .alert("Unable to calculate", isPresented: Binding(
                get: { app.errorMessage != nil && !app.showAuthentication },
                set: { if !$0 && !app.showAuthentication { app.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { app.errorMessage = nil }
            } message: { Text(app.errorMessage ?? "") }
            .sheet(isPresented: Bindable(app).showAuthentication) { AuthenticationView() }
        }
    }

    private var questionFlow: some View {
        VStack(spacing: 0) {
            progressBar
            ScrollView {
                VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                    stepContent
                }
                .padding(.horizontal, LeafyTheme.pageInset)
                .padding(.top, LeafySpacing.xLarge)
                .padding(.bottom, LeafySpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(app.draft.step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            navigationBar
        }
        .animation(reduceMotion ? .none : LeafyMotion.content, value: app.draft.step)
    }

    private var visibleQuestionSteps: [OnboardingDraft.Step] {
        var steps: [OnboardingDraft.Step] = [
            .adultEligibility, .healthConsiderations, .goal, .birthDate,
            .calculationSex, .height, .currentWeight
        ]
        if app.draft.goal != .maintain { steps.append(.targetWeight) }
        steps.append(.activity)
        if app.draft.goal != .maintain { steps.append(.pace) }
        return steps
    }

    private var progressBar: some View {
        let steps = visibleQuestionSteps
        let index = steps.firstIndex(of: app.draft.step) ?? 0
        return ProgressView(value: Double(index + 1), total: Double(steps.count))
            .tint(LeafyTheme.green)
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.top, LeafySpacing.small)
            .accessibilityLabel("Onboarding progress")
            .accessibilityValue("Step \(index + 1) of \(steps.count)")
    }

    @ViewBuilder private var stepContent: some View {
        @Bindable var draft = app.draft
        switch draft.step {
        case .adultEligibility:
            question("Are you 18 or older?", "Leafy’s calorie estimates are designed for adults.")
            binaryChoices(selection: $draft.confirmsAdult, title: "Are you 18 or older?")
            if draft.confirmsAdult == false { eligibilityGuidance(adult: false) }
        case .healthConsiderations:
            question("A few health questions", "Answer each question so Leafy can determine whether its general wellness estimates are appropriate for you.")
            VStack(alignment: .leading, spacing: LeafySpacing.large) {
                healthQuestion(
                    "Are you pregnant or breastfeeding?",
                    selection: $draft.isPregnantOrBreastfeeding,
                    identifier: "pregnancyAnswer"
                )
                healthQuestion(
                    "Are you in eating-disorder recovery?",
                    selection: $draft.isInEatingDisorderRecovery,
                    identifier: "recoveryAnswer"
                )
                healthQuestion(
                    "Are you following a diet directed by a clinician?",
                    selection: $draft.followsClinicianDirectedDiet,
                    identifier: "clinicianDietAnswer"
                )
            }
            if draft.hasContraindication == true { eligibilityGuidance(adult: true) }
        case .goal:
            question("What’s your goal?", "You can change this later and Leafy will recalculate your plan.")
            choiceRows(WeightGoal.allCases, selection: $draft.goal, title: \.title, detail: \.subtitle)
        case .birthDate:
            question("When were you born?", "Your age helps estimate your resting energy needs.")
            birthdayPicker
        case .calculationSex:
            question("Which calculation should Leafy use?", "Energy equations use different physiological constants. This is not used as your gender identity.")
            choiceRows(CalculationSex.allCases, selection: $draft.calculationSex, title: \.title)
            Button("Why this is used", systemImage: "info.circle") { showWhySex = true }
                .font(LeafyTypography.footnote)
                .alert("Why Leafy asks", isPresented: $showWhySex) { Button("OK") {} } message: {
                    Text("The Mifflin–St Jeor energy equation uses different physiological constants for female and male bodies. Leafy does not use this as your gender identity.")
                }
        case .height:
            question("How tall are you?", "This helps estimate your resting energy before activity is added.")
            unitPicker
            HeightPicker(draft: draft)
        case .currentWeight:
            question("What do you weigh today?", "A recent scale reading gives Leafy the best starting point.")
            WeightPicker(valueKG: $draft.currentWeightKG, unitSystem: draft.unitSystem)
        case .targetWeight:
            question("What weight are you working toward?", "Your target must be below your current weight to lose or above it to gain.")
            WeightPicker(valueKG: $draft.targetWeightKG, unitSystem: draft.unitSystem)
            goalSummary
        case .activity:
            question("How active are you?", "Choose the level that best reflects a typical week.")
            choiceRows(ActivityLevel.allCases, selection: $draft.activityLevel, title: \.title, detail: \.detail)
        case .pace:
            question("Choose your pace", "Steady is a balanced starting point. Leafy applies safety limits automatically.")
            choiceRows(GoalPace.allCases, selection: $draft.pace, title: \.title, detail: { paceText($0) })
        case .welcome, .results, .account:
            EmptyView()
        }
    }

    private func question(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(title).font(LeafyTypography.largeTitle)
            Text(subtitle).font(LeafyTypography.body).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func binaryChoices(selection: Binding<Bool?>, title: String) -> some View {
        VStack(spacing: 0) {
            SelectableRow(title: "Yes", selected: selection.wrappedValue == true) {
                selection.wrappedValue = true
                UISelectionFeedbackGenerator().selectionChanged()
            }
            Divider().overlay(LeafyTheme.hairline)
            SelectableRow(title: "No", selected: selection.wrappedValue == false) {
                selection.wrappedValue = false
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func healthQuestion(
        _ title: String,
        selection: Binding<Bool?>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(title)
                .font(LeafyTypography.headline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: LeafySpacing.xLarge) {
                healthAnswer("Yes", value: true, selection: selection, identifier: identifier + "Yes")
                healthAnswer("No", value: false, selection: selection, identifier: identifier + "No")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func healthAnswer(
        _ label: String,
        value: Bool,
        selection: Binding<Bool?>,
        identifier: String
    ) -> some View {
        let selected = selection.wrappedValue == value
        return Button {
            selection.wrappedValue = value
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Label(label, systemImage: selected ? "checkmark.circle.fill" : "circle")
                .font(LeafyTypography.body)
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? LeafyTheme.green : Color.primary)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choiceRows<Value: Identifiable & Equatable>(
        _ values: [Value],
        selection: Binding<Value>,
        title: KeyPath<Value, String>,
        detail: ((Value) -> String)? = nil
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                SelectableRow(
                    title: value[keyPath: title],
                    detail: detail?(value),
                    selected: selection.wrappedValue == value
                ) {
                    selection.wrappedValue = value
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                if index < values.count - 1 { Divider().overlay(LeafyTheme.hairline) }
            }
        }
    }

    private func choiceRows<Value: Identifiable & Equatable>(
        _ values: [Value],
        selection: Binding<Value>,
        title: KeyPath<Value, String>,
        detail: KeyPath<Value, String>
    ) -> some View {
        choiceRows(values, selection: selection, title: title, detail: { $0[keyPath: detail] })
    }

    private var birthdayPicker: some View {
        @Bindable var draft = app.draft
        let calendar = Calendar.current
        let latest = calendar.date(byAdding: .year, value: -18, to: .now) ?? .now
        let earliest = calendar.date(byAdding: .year, value: -120, to: .now) ?? .distantPast
        return VStack(spacing: LeafySpacing.medium) {
            DatePicker("Date of birth", selection: draft.birthDatePickerSelection, in: earliest...latest, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
            Text("Age \(age(for: draft.birthDate))")
                .font(LeafyTypography.subheadlineSemibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var unitPicker: some View {
        @Bindable var draft = app.draft
        return Picker("Measurement system", selection: $draft.unitSystem) {
            ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var goalSummary: some View {
        let valid = app.draft.hasValidMeasurements
        return Label(
            valid ? "Your target matches your goal." : "Choose a target on the other side of your current weight.",
            systemImage: valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(LeafyTypography.footnote)
        .foregroundStyle(valid ? LeafyTheme.green : .orange)
    }

    private func eligibilityGuidance(adult: Bool) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Label("Personal guidance is best", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(LeafyTypography.headline)
            Text(adult
                 ? "Generic calorie targets may not be appropriate right now. Please work with a qualified clinician or registered dietitian."
                 : "Leafy’s generic calorie targets are intended for adults. Please seek guidance from a parent or guardian and a qualified health professional.")
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, LeafySpacing.medium)
        .overlay(alignment: .leading) { Rectangle().fill(LeafyTheme.green).frame(width: 3) }
    }

    private var welcomeContent: some View {
        @Bindable var draft = app.draft
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                    VStack(spacing: LeafySpacing.medium) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(LeafyTheme.green)
                        Text("Your nutrition, made clear")
                            .font(LeafyTypography.largeTitle)
                            .multilineTextAlignment(.center)
                        Text("Personalized nutrition targets built around your body and your goal.")
                            .font(LeafyTypography.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: LeafySpacing.medium) {
                        Text("What you’ll get").font(LeafyTypography.headline)
                        WelcomeOutcomeRow("A personalized daily calorie target")
                        WelcomeOutcomeRow("Protein, carb, and fat goals")
                        WelcomeOutcomeRow("A pace matched to your weight goal")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: LeafySpacing.small) {
                            Label("About 2 minutes", systemImage: "clock")
                            Text("·")
                            Text("Preview before creating an account")
                        }
                        VStack(alignment: .leading, spacing: LeafySpacing.small) {
                            Label("About 2 minutes", systemImage: "clock")
                            Label("Preview before creating an account", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, LeafyTheme.pageInset)
                .padding(.top, LeafySpacing.large)
            }

            VStack(spacing: LeafySpacing.compact) {
                Button("Continue") { move(to: .adultEligibility) }
                    .buttonStyle(PrimaryButtonStyle())
                if !app.isAuthenticated {
                    Button("Sign in") { app.presentAuthentication() }
                        .font(LeafyTypography.button)
                        .accessibilityIdentifier("welcomeSignInButton")
                }
                Text("For general wellness only—not medical advice.")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: LeafySpacing.large) {
                    Link("Privacy", destination: app.configuration.privacyURL)
                    Link("Terms", destination: app.configuration.termsURL)
                    Link("Support", destination: app.configuration.supportURL)
                }
                .font(LeafyTypography.footnote)
            }
            .leafyDetachedBottomControl()
        }
    }

    private var navigationBar: some View {
        HStack(spacing: LeafySpacing.compact) {
            Button { previous() } label: {
                Image(systemName: "chevron.left")
                    .font(LeafyTypography.headline)
                    .frame(width: 48, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Button("Continue") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
        }
        .leafyDetachedBottomControl()
    }

    private var canContinue: Bool {
        switch app.draft.step {
        case .adultEligibility: app.draft.confirmsAdult == true
        case .healthConsiderations: app.draft.hasContraindication == false
        case .birthDate:
            !app.requiresBirthDateConfirmation || app.draft.birthDateChosen
        case .height: (120...230).contains(app.draft.heightCM)
        case .currentWeight: (35...350).contains(app.draft.currentWeightKG)
        case .targetWeight: app.draft.hasValidMeasurements
        default: true
        }
    }

    private func next() {
        let steps = visibleQuestionSteps
        guard let index = steps.firstIndex(of: app.draft.step) else { return }
        if app.draft.step == .currentWeight { normalizeTargetIfNeeded() }
        if app.draft.step == .birthDate {
            app.confirmOnboardingBirthDate()
            Task { await app.persistPendingOnboarding() }
            if app.requiresBirthDateConfirmation { return }
        }
        if index == steps.count - 1 {
            guard app.calculatePreview() else { return }
            move(to: .results)
        } else {
            move(to: steps[index + 1])
        }
    }

    private func previous() {
        let steps = visibleQuestionSteps
        guard let index = steps.firstIndex(of: app.draft.step) else { return }
        move(to: index == 0 ? .welcome : steps[index - 1])
    }

    private func move(to step: OnboardingDraft.Step) {
        if reduceMotion { app.draft.step = step }
        else { withAnimation(LeafyMotion.content) { app.draft.step = step } }
    }

    private func normalizeTargetIfNeeded() {
        let draft = app.draft
        if draft.goal == .lose, draft.targetWeightKG >= draft.currentWeightKG {
            draft.targetWeightKG = max(35, draft.currentWeightKG - 5)
        } else if draft.goal == .gain, draft.targetWeightKG <= draft.currentWeightKG {
            draft.targetWeightKG = min(350, draft.currentWeightKG + 5)
        }
    }

    private func age(for birthday: LocalDate) -> Int {
        let today = LocalDate(localCivilFrom: .now, timeZone: .current)
            ?? LocalDate.utcCivilDate(from: .now)
        return birthday.ageInYears(asOf: today)
    }

    private func paceText(_ pace: GoalPace) -> String {
        let percent = abs(pace.adjustment(for: app.draft.goal) * 100)
        return String(format: "%.0f%% %@ from maintenance calories", percent, app.draft.goal == .lose ? "deficit" : "surplus")
    }
}

private struct SelectableRow: View {
    let title: String
    var detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: LeafySpacing.medium) {
                VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                    Text(title).font(LeafyTypography.headline).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(LeafyTypography.title3)
                    .foregroundStyle(selected ? LeafyTheme.green : Color.secondary.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(minHeight: LeafyTheme.rowMinHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(title)
    }
}

private struct HeightPicker: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        if draft.unitSystem == .metric {
            HStack(spacing: LeafySpacing.small) {
                Picker("Centimeters", selection: Binding(
                    get: { Int(draft.heightCM.rounded()) },
                    set: { draft.heightCM = Double($0) }
                )) {
                    ForEach(120...230, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                Text("cm").foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: LeafySpacing.small) {
                Picker("Feet", selection: Binding(
                    get: { ImperialHeightSelection(centimeters: draft.heightCM).feet },
                    set: { feet in
                        let current = ImperialHeightSelection(centimeters: draft.heightCM)
                        draft.heightCM = ImperialHeightSelection(feet: feet, inches: current.inches).centimeters
                    }
                )) {
                    ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
                }
                .pickerStyle(.wheel)
                .accessibilityIdentifier("heightFeetPicker")
                Picker("Inches", selection: Binding(
                    get: { ImperialHeightSelection(centimeters: draft.heightCM).inches },
                    set: { inches in
                        let current = ImperialHeightSelection(centimeters: draft.heightCM)
                        draft.heightCM = ImperialHeightSelection(feet: current.feet, inches: inches).centimeters
                    }
                )) {
                    ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                }
                .pickerStyle(.wheel)
                .accessibilityIdentifier("heightInchesPicker")
            }
        }
    }
}

private struct WeightPicker: View {
    @Binding var valueKG: Double
    let unitSystem: UnitSystem

    private var displayValue: Double { unitSystem == .metric ? valueKG : valueKG * 2.2046226218 }
    private var tenths: Int { Int((displayValue * 10).rounded()) % 10 }

    var body: some View {
        let range = unitSystem == .metric ? 35...350 : 77...772
        HStack(spacing: 0) {
            Picker("Whole", selection: Binding(
                get: { Int(displayValue) },
                set: { setDisplayValue(Double($0) + Double(tenths) / 10) }
            )) {
                ForEach(range, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            Text(".").font(LeafyTypography.title2)
            Picker("Tenths", selection: Binding(
                get: { tenths },
                set: { setDisplayValue(Double(Int(displayValue)) + Double($0) / 10) }
            )) {
                ForEach(0...9, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            Text(unitSystem == .metric ? "kg" : "lb").foregroundStyle(.secondary)
        }
    }

    private func setDisplayValue(_ value: Double) {
        valueKG = unitSystem == .metric ? value : value / 2.2046226218
    }
}

private struct WelcomeOutcomeRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LeafySpacing.compact) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(LeafyTheme.green)
            Text(text).font(LeafyTypography.subheadline)
        }
    }
}
