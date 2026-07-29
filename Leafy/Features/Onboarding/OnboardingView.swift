import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var showWhySex = false

    var body: some View {
        @Bindable var draft = app.draft
        NavigationStack {
            VStack(spacing: 0) {
                if draft.step != .welcome {
                    ProgressView(value: Double(draft.step.rawValue), total: Double(OnboardingDraft.Step.results.rawValue))
                        .tint(LeafyTheme.green).padding(.horizontal).padding(.top, 8)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) { stepContent }.padding(24)
                }
                if draft.step != .welcome && draft.step != .results { navigationBar }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                if draft.isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { app.route = .dashboard }
                    }
                }
            }
            .alert("Unable to calculate", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
                Button("OK", role: .cancel) { app.errorMessage = nil }
            } message: { Text(app.errorMessage ?? "") }
            .sheet(isPresented: Bindable(app).showAuthentication) { AuthenticationView() }
        }
    }

    @ViewBuilder private var stepContent: some View {
        @Bindable var draft = app.draft
        switch draft.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 50)
                Image(systemName: "leaf.fill").font(.system(size: 64)).foregroundStyle(LeafyTheme.green)
                Text("Meet Leafy").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("A clear daily calorie and macro target, built around your body and your goal.")
                    .font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    Label("Takes about two minutes", systemImage: "clock")
                    Label("Your draft stays on this device until you save", systemImage: "lock.shield")
                    Label("Estimates for general wellness—not medical advice", systemImage: "heart.text.square")
                }.font(.subheadline)
                Button(draft.isEditing ? "Review my plan" : "Build my plan") { draft.step = .eligibility }
                    .buttonStyle(PrimaryButtonStyle())
                HStack(spacing: 18) {
                    Link("Privacy", destination: app.configuration.privacyURL)
                    Link("Terms", destination: app.configuration.termsURL)
                    Link("Support", destination: app.configuration.supportURL)
                }.font(.footnote)
            }
        case .eligibility:
            title("Before we begin", "Leafy’s calculator is designed for general adult wellness.")
            Toggle("I am 18 or older", isOn: $draft.confirmsAdult).tint(LeafyTheme.green)
            Toggle("I am pregnant or breastfeeding, in eating-disorder recovery, or following a clinician-directed diet", isOn: $draft.hasContraindication).tint(LeafyTheme.green)
            if draft.hasContraindication {
                ContentUnavailableView("Personal guidance is best", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("Generic calorie targets may not be appropriate. Please work with a qualified clinician or registered dietitian."))
            }
        case .goal:
            title("What’s your goal?", "You can change this later and Leafy will recalculate your plan.")
            ForEach(WeightGoal.allCases) { goal in
                Button { draft.goal = goal } label: {
                    ChoiceCard(selected: draft.goal == goal) {
                        VStack(alignment: .leading, spacing: 4) { Text(goal.title).font(.headline); Text(goal.subtitle).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain)
            }
        case .body:
            title("Tell us about you", "These inputs are used only to estimate energy needs.")
            Picker("Units", selection: $draft.unitSystem) { ForEach(UnitSystem.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            DatePicker("Date of birth", selection: $draft.birthDate, in: ...Calendar.current.date(byAdding: .year, value: -18, to: .now)!, displayedComponents: .date)
            Picker("Sex used for calculation", selection: $draft.calculationSex) { ForEach(CalculationSex.allCases) { Text($0.title).tag($0) } }
            Button("Why do we ask this?") { showWhySex = true }.font(.footnote)
                .alert("Why Leafy asks", isPresented: $showWhySex) { Button("OK") {} } message: { Text("The Mifflin–St Jeor energy equation uses different physiological constants for female and male bodies. Leafy does not use this as your gender identity.") }
            MeasurementFields(draft: draft)
        case .target:
            title("Choose a destination", "Your target must be below your current weight to lose or above it to gain.")
            WeightField(label: "Target weight", kilograms: $draft.targetWeightKG, units: draft.unitSystem)
        case .activity:
            title("How active are you?", "Choose the level that best reflects a typical week.")
            ForEach(ActivityLevel.allCases) { level in
                Button { draft.activityLevel = level } label: {
                    ChoiceCard(selected: draft.activityLevel == level) {
                        VStack(alignment: .leading, spacing: 4) { Text(level.title).font(.headline); Text(level.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain)
            }
        case .pace:
            title("Choose your pace", "Steady is a balanced starting point. Leafy applies safety limits automatically.")
            ForEach(GoalPace.allCases) { pace in
                Button { draft.pace = pace } label: {
                    ChoiceCard(selected: draft.pace == pace) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pace.title).font(.headline)
                            Text(paceText(pace)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        case .results:
            if let plan = app.preview { PlanResultsView(plan: plan, isPreview: true) }
        }
    }

    private var navigationBar: some View {
        @Bindable var draft = app.draft
        return HStack(spacing: 12) {
            Button { previous() } label: { Image(systemName: "chevron.left").frame(width: 48, height: 52).background(.thinMaterial, in: .rect(cornerRadius: 16)) }
            Button("Continue") { next() }.buttonStyle(PrimaryButtonStyle()).disabled(!canContinue)
        }.padding()
    }

    private var canContinue: Bool {
        let draft = app.draft
        if draft.step == .eligibility { return draft.confirmsAdult && !draft.hasContraindication }
        return true
    }

    private func next() {
        let draft = app.draft
        var next = draft.step.rawValue + 1
        if draft.step == .goal && draft.goal == .maintain { next = OnboardingDraft.Step.activity.rawValue }
        if draft.step == .activity && draft.goal == .maintain { next = OnboardingDraft.Step.results.rawValue }
        if next == OnboardingDraft.Step.results.rawValue {
            guard app.calculatePreview() else { return }
        }
        draft.step = OnboardingDraft.Step(rawValue: next) ?? .results
    }

    private func previous() {
        let draft = app.draft
        var prior = draft.step.rawValue - 1
        if draft.step == .activity && draft.goal == .maintain { prior = OnboardingDraft.Step.goal.rawValue }
        draft.step = OnboardingDraft.Step(rawValue: max(0, prior)) ?? .welcome
    }

    private func title(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.largeTitle.bold()); Text(subtitle).foregroundStyle(.secondary) }
    }

    private func paceText(_ pace: GoalPace) -> String {
        let percent = abs(pace.adjustment(for: app.draft.goal) * 100)
        return String(format: "%.0f%% %@ from maintenance calories", percent, app.draft.goal == .lose ? "deficit" : "surplus")
    }
}

private struct MeasurementFields: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        if draft.unitSystem == .metric {
            LabeledContent("Height") { TextField("cm", value: $draft.heightCM, format: .number.precision(.fractionLength(0))).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
        } else {
            ImperialHeightField(centimeters: $draft.heightCM)
        }
        WeightField(label: "Current weight", kilograms: $draft.currentWeightKG, units: draft.unitSystem)
    }
}

private struct ImperialHeightField: View {
    @Binding var centimeters: Double
    private var feet: Binding<Int> { Binding(get: { Int(centimeters / 2.54) / 12 }, set: { centimeters = Double($0 * 12 + inches.wrappedValue) * 2.54 }) }
    private var inches: Binding<Int> { Binding(get: { Int((centimeters / 2.54).rounded()) % 12 }, set: { centimeters = Double(feet.wrappedValue * 12 + $0) * 2.54 }) }
    var body: some View { LabeledContent("Height") { HStack { TextField("ft", value: feet, format: .number).frame(width: 38); Text("ft"); TextField("in", value: inches, format: .number).frame(width: 38); Text("in") }.keyboardType(.numberPad) } }
}

struct WeightField: View {
    let label: String
    @Binding var kilograms: Double
    let units: UnitSystem
    private var value: Binding<Double> { Binding(get: { units == .metric ? kilograms : kilograms * 2.2046226218 }, set: { kilograms = units == .metric ? $0 : $0 / 2.2046226218 }) }
    var body: some View { LabeledContent(label) { HStack { TextField("Weight", value: value, format: .number.precision(.fractionLength(1))).multilineTextAlignment(.trailing).keyboardType(.decimalPad); Text(units == .metric ? "kg" : "lb").foregroundStyle(.secondary) }.frame(maxWidth: 150) } }
}
