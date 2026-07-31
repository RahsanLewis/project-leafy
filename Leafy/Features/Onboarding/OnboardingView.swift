import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var showWhySex = false
    @State private var showBirthdayPicker = false
    @State private var pendingBirthday = Date.now

    var body: some View {
        @Bindable var draft = app.draft
        NavigationStack {
            VStack(spacing: 0) {
                if draft.step != .welcome {
                    ProgressView(value: Double(draft.step.rawValue), total: Double(OnboardingDraft.Step.results.rawValue))
                        .tint(LeafyTheme.green).padding(.horizontal).padding(.top, 8)
                }
                if draft.step == .welcome {
                    welcomeContent
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) { stepContent }.padding(24)
                    }
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
            .sheet(isPresented: $showBirthdayPicker) { birthdayPickerSheet }
        }
    }

    @ViewBuilder private var stepContent: some View {
        @Bindable var draft = app.draft
        switch draft.step {
        case .welcome:
            EmptyView()
        case .eligibility:
            eligibilityHeader
            EligibilityQuestionCard(
                title: "Are you 18 or older?",
                detail: "Leafy’s calorie estimates are designed for adults.",
                considerations: [],
                selection: $draft.confirmsAdult
            )
            EligibilityQuestionCard(
                title: "Do any of these apply to you?",
                detail: "Select Yes if you are:",
                considerations: [
                    "Pregnant or breastfeeding",
                    "In eating-disorder recovery",
                    "Following a clinician-directed diet"
                ],
                selection: $draft.hasContraindication
            )
            if draft.isIneligible {
                eligibilityGuidance
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
            title("Tell us about you", "A few details help us estimate your resting energy and daily needs.")

            ProfileSectionCard(title: "Measurement system", icon: "ruler") {
                Picker("Units", selection: $draft.unitSystem) {
                    ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            ProfileSectionCard(title: "Your profile", icon: "person.crop.circle") {
                Button {
                    pendingBirthday = draft.birthDate
                    showBirthdayPicker = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date of birth")
                                .foregroundStyle(.primary)
                            Text("Age \(age(for: draft.birthDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(draft.birthDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Divider()
                LabeledContent("Calculation sex") {
                    Picker("Calculation sex", selection: $draft.calculationSex) {
                        ForEach(CalculationSex.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                Button("Why this is used", systemImage: "info.circle") { showWhySex = true }
                    .font(.footnote.weight(.medium))
                    .alert("Why Leafy asks", isPresented: $showWhySex) { Button("OK") {} } message: { Text("The Mifflin–St Jeor energy equation uses different physiological constants for female and male bodies. Leafy does not use this as your gender identity.") }
            }

            ProfileSectionCard(title: "Your measurements", icon: "figure.arms.open") {
                MeasurementFields(draft: draft)
                Text("These measurements help estimate your resting energy before your activity level is added.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

    private var birthdayPickerSheet: some View {
        @Bindable var draft = app.draft
        let calendar = Calendar.current
        let latestBirthday = calendar.date(byAdding: .year, value: -18, to: .now) ?? .now
        let earliestBirthday = calendar.date(byAdding: .year, value: -120, to: .now) ?? .distantPast

        return NavigationStack {
            VStack(spacing: 12) {
                DatePicker(
                    "Date of birth",
                    selection: $pendingBirthday,
                    in: earliestBirthday...latestBirthday,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Text("Age \(age(for: pendingBirthday))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .navigationTitle("Date of birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBirthdayPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        draft.birthDate = pendingBirthday
                        showBirthdayPicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }

    private func age(for birthday: Date) -> Int {
        Calendar.current.dateComponents([.year], from: birthday, to: .now).year ?? 0
    }

    private var welcomeContent: some View {
        @Bindable var draft = app.draft
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .center, spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(LeafyTheme.green)
                Text("Your nutrition, made clear")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Personalized nutrition targets built around your body and your goal.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 15) {
                Text("What you’ll get")
                    .font(.headline)
                WelcomeOutcomeRow("A personalized daily calorie target")
                WelcomeOutcomeRow("Protein, carb, and fat goals")
                WelcomeOutcomeRow("A pace matched to your weight goal")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LeafyTheme.green.opacity(0.08), in: .rect(cornerRadius: 18))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Label("Takes about 2 minutes", systemImage: "clock")
                    Text("·")
                    Text("No account required to preview")
                }
                VStack(spacing: 6) {
                    Label("Takes about 2 minutes", systemImage: "clock")
                    Label("No account required to preview", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            VStack(spacing: 16) {
                Button(draft.isEditing ? "Review my plan" : "Continue") { draft.step = .eligibility }
                    .buttonStyle(PrimaryButtonStyle())
                Text("For general wellness only—not medical advice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 22) {
                    Link("Privacy", destination: app.configuration.privacyURL)
                    Link("Terms", destination: app.configuration.termsURL)
                    Link("Support", destination: app.configuration.supportURL)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
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
        if draft.step == .eligibility { return draft.hasCompletedEligibility && draft.isEligible }
        if draft.step == .body { return draft.hasValidMeasurements }
        return true
    }

    private var eligibilityHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(LeafyTheme.green)
                    .frame(width: 48, height: 48)
                    .background(LeafyTheme.mint, in: .circle)
                Text("A quick safety check")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("These answers help us confirm Leafy’s estimates are appropriate for you.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Label("Leafy uses general adult wellness equations. These answers are not saved with your nutrition plan.", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LeafyTheme.green.opacity(0.08), in: .rect(cornerRadius: 14))
        }
    }

    private var eligibilityGuidance: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(LeafyTheme.green)
            VStack(alignment: .leading, spacing: 5) {
                Text("Personal guidance is best")
                    .font(.headline)
                Text(eligibilityGuidanceMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var eligibilityGuidanceMessage: String {
        if app.draft.confirmsAdult == false {
            return "Leafy’s generic calorie targets are intended for adults. Please seek guidance from a parent or guardian and a qualified health professional."
        }
        return "Generic calorie targets may not be appropriate right now. Please work with a qualified clinician or registered dietitian."
    }

    private func next() {
        let draft = app.draft
        var next = draft.step.rawValue + 1
        if draft.step == .activity && draft.goal == .maintain { next = OnboardingDraft.Step.results.rawValue }
        if next == OnboardingDraft.Step.results.rawValue {
            guard app.calculatePreview() else { return }
        }
        draft.step = OnboardingDraft.Step(rawValue: next) ?? .results
    }

    private func previous() {
        let draft = app.draft
        let prior = draft.step.rawValue - 1
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

private struct WelcomeOutcomeRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LeafyTheme.green)
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct EligibilityQuestionCard: View {
    let title: String
    let detail: String
    let considerations: [String]
    @Binding var selection: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !considerations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(considerations, id: \.self) { consideration in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(LeafyTheme.green)
                                Text(consideration)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(.top, 3)
                }
            }

            HStack(spacing: 10) {
                answerButton("Yes", value: true)
                answerButton("No", value: false)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(selection == nil ? Color.primary.opacity(0.06) : LeafyTheme.green.opacity(0.55), lineWidth: 1.5)
        }
    }

    private func answerButton(_ label: String, value: Bool) -> some View {
        let selected = selection == value
        return Button {
            selection = value
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(label)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(selected ? .white : LeafyTheme.green)
            .background(selected ? LeafyTheme.green : LeafyTheme.green.opacity(0.08), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ProfileSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(LeafyTheme.ink)
                .symbolRenderingMode(.hierarchical)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct MeasurementFields: View {
    private enum PickerKind: String, Identifiable {
        case height, currentWeight, targetWeight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .height: "Height"
            case .currentWeight: "Current weight"
            case .targetWeight: "Target weight"
            }
        }
    }

    @Bindable var draft: OnboardingDraft
    @State private var activePicker: PickerKind?
    @State private var pendingValue = 0.0

    var body: some View {
        measurementRow("Height", value: formattedHeight) { present(.height, value: draft.heightCM) }
        Divider()
        measurementRow("Current weight", value: formattedWeight(draft.currentWeightKG)) {
            present(.currentWeight, value: draft.currentWeightKG)
        }
        if draft.goal != .maintain {
            Divider()
            measurementRow("Target weight", value: formattedWeight(draft.targetWeightKG)) {
                present(.targetWeight, value: draft.targetWeightKG)
            }
        }
        WeightGoalSummary(draft: draft)
        .sheet(item: $activePicker) { kind in
            measurementPicker(kind)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
    }

    private func measurementRow(_ label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                Text(value).foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }

    private func present(_ kind: PickerKind, value: Double) {
        pendingValue = value
        activePicker = kind
    }

    private func measurementPicker(_ kind: PickerKind) -> some View {
        NavigationStack {
            Group {
                if kind == .height { heightWheels } else { weightWheels }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activePicker = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        switch kind {
                        case .height: draft.heightCM = pendingValue
                        case .currentWeight: draft.currentWeightKG = pendingValue
                        case .targetWeight: draft.targetWeightKG = pendingValue
                        }
                        activePicker = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder private var heightWheels: some View {
        if draft.unitSystem == .metric {
            HStack(spacing: 4) {
                Picker("Centimeters", selection: Binding(
                    get: { Int(pendingValue.rounded()) },
                    set: { pendingValue = Double($0) }
                )) {
                    ForEach(120...230, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                Text("cm").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 56)
        } else {
            HStack(spacing: 8) {
                Picker("Feet", selection: feetBinding) {
                    ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) }
                }
                Picker("Inches", selection: inchesBinding) {
                    ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .padding(.horizontal, 32)
        }
    }

    private var weightWheels: some View {
        let isMetric = draft.unitSystem == .metric
        let displayValue = isMetric ? pendingValue : pendingValue * 2.2046226218
        let range = isMetric ? 35...350 : 77...772
        return HStack(spacing: 0) {
            Picker("Whole", selection: Binding(
                get: { Int(displayValue) },
                set: { setPendingWeight(Double($0) + Double(weightTenths) / 10) }
            )) {
                ForEach(range, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            Text(".").font(.title2.bold())
            Picker("Tenths", selection: Binding(
                get: { weightTenths },
                set: { setPendingWeight(Double(Int(displayWeight)) + Double($0) / 10) }
            )) {
                ForEach(0...9, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            Text(isMetric ? "kg" : "lb").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 42)
    }

    private var displayWeight: Double {
        draft.unitSystem == .metric ? pendingValue : pendingValue * 2.2046226218
    }

    private var weightTenths: Int { Int((displayWeight * 10).rounded()) % 10 }

    private func setPendingWeight(_ displayValue: Double) {
        pendingValue = draft.unitSystem == .metric ? displayValue : displayValue / 2.2046226218
    }

    private var feetBinding: Binding<Int> {
        Binding(
            get: { Int((pendingValue / 2.54).rounded()) / 12 },
            set: { pendingValue = Double($0 * 12 + inchesBinding.wrappedValue) * 2.54 }
        )
    }

    private var inchesBinding: Binding<Int> {
        Binding(
            get: { Int((pendingValue / 2.54).rounded()) % 12 },
            set: { pendingValue = Double(feetBinding.wrappedValue * 12 + $0) * 2.54 }
        )
    }

    private var formattedHeight: String {
        if draft.unitSystem == .metric { return "\(Int(draft.heightCM.rounded())) cm" }
        let totalInches = Int((draft.heightCM / 2.54).rounded())
        return "\(totalInches / 12) ft \(totalInches % 12) in"
    }

    private func formattedWeight(_ kilograms: Double) -> String {
        let value = draft.unitSystem == .metric ? kilograms : kilograms * 2.2046226218
        return String(format: "%.1f %@", value, draft.unitSystem == .metric ? "kg" : "lb")
    }
}

private struct WeightGoalSummary: View {
    var draft: OnboardingDraft

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private var isValid: Bool { draft.hasValidMeasurements }

    private var color: Color {
        isValid ? LeafyTheme.green : .orange
    }

    private var icon: String {
        if !isValid { return "exclamationmark.triangle.fill" }
        if draft.goal == .maintain { return "equal.circle.fill" }
        return draft.goal == .lose ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }

    private var headline: String {
        if !isValid {
            if !(120...230).contains(draft.heightCM) { return "Check your height" }
            if !(35...350).contains(draft.currentWeightKG) { return "Check your current weight" }
            return draft.goal == .lose ? "Choose a lower target weight" : "Choose a higher target weight"
        }
        if draft.goal == .maintain { return "Maintain around \(formattedWeight(draft.currentWeightKG))" }
        return "\(formattedWeight(draft.goalDifferenceKG)) to \(draft.goal == .lose ? "lose" : "gain")"
    }

    private var detail: String {
        if !isValid {
            return "Your target should match the direction of your selected goal."
        }
        if draft.goal == .maintain { return "Leafy will calculate targets that support your current weight." }
        return "You can adjust this target later as your goals change."
    }

    private func formattedWeight(_ kilograms: Double) -> String {
        let value = draft.unitSystem == .imperial ? kilograms * 2.2046226218 : kilograms
        return String(format: "%.1f %@", value, draft.unitSystem == .imperial ? "lb" : "kg")
    }
}
