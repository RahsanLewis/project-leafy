import SwiftUI
import UIKit

private enum PlanEditPhase { case editing, review }

struct PlanEditView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var original: NutritionPlanInput?
    @State private var edited: NutritionPlanInput?
    @State private var preview: NutritionPlan?
    @State private var phase: PlanEditPhase = .editing
    @State private var showingProfile = false
    @State private var showingDiscard = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isTargetTextValid = true
    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let input = edited {
                    if phase == .review, let preview {
                        review(input: input, preview: preview)
                    } else {
                        editor(input: input)
                    }
                } else {
                    ProgressView()
                }
            }
            .background(LeafyTheme.canvas)
            .navigationTitle(phase == .review ? "Review changes" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .review ? "Back" : "Cancel") {
                        if phase == .review {
                            phase = .editing
                        } else {
                            requestDismiss()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .sheet(isPresented: $showingDiscard) {
            LeafyConfirmationSheet(
                title: "Discard your changes?",
                message: "Your plan will stay as it is now.",
                confirmTitle: "Discard changes",
                isDestructive: true,
                confirmIdentifier: "confirmDiscardPlanChangesButton",
                cancelTitle: "Keep editing",
                sheetIdentifier: "discardPlanChangesConfirmationSheet"
            ) { dismiss() }
        }
        .alert("Unable to update plan", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .onAppear(perform: initialize)
        .accessibilityIdentifier("planEditView")
    }

    private func editor(input: NutritionPlanInput) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                section("Goal") {
                    choiceRow(WeightGoal.allCases, selection: input.goal, title: \WeightGoal.title) { value in
                        isTargetTextValid = true
                        update { $0.goal = value; normalizeTarget(&$0) }
                    }
                    if input.goal != .maintain {
                        InlineTargetWeightEditor(
                            kilograms: targetWeightBinding(fallback: input.currentWeightKG),
                            unit: input.unitSystem,
                            currentWeightKG: input.currentWeightKG,
                            goal: input.goal,
                            isTextValid: $isTargetTextValid
                        )
                        choiceRow(GoalPace.allCases, selection: input.pace, title: \GoalPace.title) { value in
                            update { $0.pace = value }
                        }
                    }
                }

                section("Activity") {
                    choiceRow(ActivityLevel.allCases, selection: input.activityLevel, title: \ActivityLevel.title) { value in
                        update { $0.activityLevel = value }
                    }
                }

                section("Measurements") {
                    Picker("Units", selection: binding(\.unitSystem, fallback: input.unitSystem)) {
                        ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Current weight", value: weightText(input.currentWeightKG))
                    Text("Current weight comes from your latest weigh-in. Update it from Progress.")
                        .font(LeafyTypography.footnote)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Profile details", isExpanded: $showingProfile) {
                    VStack(alignment: .leading, spacing: LeafySpacing.large) {
                        DatePicker("Date of birth", selection: binding(\.birthDate, fallback: input.birthDate).datePickerSelection, in: birthDateRange, displayedComponents: .date)
                        Picker("Calculation sex", selection: binding(\.calculationSex, fallback: input.calculationSex)) {
                            ForEach(CalculationSex.allCases) { Text($0.title).tag($0) }
                        }
                        LabeledContent("Height") {
                            HeightAdjustmentView(centimeters: binding(\.heightCM, fallback: input.heightCM), unit: input.unitSystem)
                        }
                    }
                    .padding(.top, LeafySpacing.medium)
                }
                .font(LeafyTypography.headline)
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.vertical, LeafySpacing.large)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Review changes") { makePreview() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValid || !isDirty)
                .leafyDetachedBottomControl()
                .accessibilityIdentifier("reviewPlanChangesButton")
        }
    }

    private func review(input: NutritionPlanInput, preview: NutritionPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                Text("Your updated targets")
                    .font(LeafyTypography.largeTitle)
                comparison("Daily calories", old: app.currentPlan?.calorieTargetKcal, new: preview.calorieTargetKcal, unit: "Cal")
                HStack(spacing: 0) {
                    macroComparison("Protein", old: app.currentPlan?.proteinG, new: preview.proteinG)
                    macroComparison("Carbs", old: app.currentPlan?.carbohydrateG, new: preview.carbohydrateG)
                    macroComparison("Fat", old: app.currentPlan?.fatG, new: preview.fatG)
                }
                Divider().overlay(LeafyTheme.hairline)
                LabeledContent("Goal", value: input.goal.title)
                if input.goal != .maintain {
                    LabeledContent("Target weight", value: weightText(input.targetWeightKG ?? input.currentWeightKG))
                    LabeledContent("Pace", value: input.pace.title)
                }
                LabeledContent("Activity", value: input.activityLevel.title)
            }
            .padding(LeafyTheme.pageInset)
        }
        .safeAreaInset(edge: .bottom) {
            Button(isSaving ? "Updating…" : "Update plan") { save(input) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
                .leafyDetachedBottomControl()
                .accessibilityIdentifier("updatePlanButton")
        }
        .accessibilityIdentifier("planEditReview")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            Text(title).font(LeafyTypography.title3)
            content()
        }
    }

    private func choiceRow<Value: Identifiable & Equatable>(_ values: [Value], selection: Value, title: KeyPath<Value, String>, onSelect: @escaping (Value) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                Button { onSelect(value); UISelectionFeedbackGenerator().selectionChanged() } label: {
                    HStack {
                        Text(value[keyPath: title]).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection == value ? LeafyTheme.green : .secondary)
                    }
                    .frame(minHeight: LeafyTheme.rowMinHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if index < values.count - 1 { Divider().overlay(LeafyTheme.hairline) }
            }
        }
    }

    private func comparison(_ label: String, old: Int?, new: Int, unit: String) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(label).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: LeafySpacing.small) {
                Text(new.formatted()).font(LeafyTypography.metric(52, extraBold: true)).monospacedDigit()
                Text(unit).font(LeafyTypography.title3).foregroundStyle(.secondary)
            }
            if let old, old != new { Text("Previously \(old.formatted()) \(unit)").font(LeafyTypography.footnote).foregroundStyle(.secondary) }
        }
    }

    private func macroComparison(_ label: String, old: Int?, new: Int) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text("\(new) g").font(LeafyTypography.title2).monospacedDigit()
            Text(label).font(LeafyTypography.caption).foregroundStyle(.secondary)
            if let old, old != new { Text("was \(old) g").font(LeafyTypography.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func initialize() {
        guard original == nil else { return }
        var input = app.draft.input
        if let latest = app.weightEntries.first?.weightKG { input.currentWeightKG = latest }
        normalizeTarget(&input)
        original = input
        edited = input
    }

    private func update(_ change: (inout NutritionPlanInput) -> Void) {
        guard var value = edited else { return }
        change(&value)
        edited = value
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NutritionPlanInput, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { edited?[keyPath: keyPath] ?? fallback }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func targetWeightBinding(fallback: Double) -> Binding<Double> {
        Binding(
            get: { edited?.targetWeightKG ?? fallback },
            set: { newValue in
                update { value in
                    value.targetWeightKG = value.goal == .maintain ? nil : newValue
                }
            }
        )
    }

    private var isDirty: Bool { edited != original }
    private var isValid: Bool {
        guard isTargetTextValid,
              let input = edited,
              (120...230).contains(input.heightCM),
              (35...350).contains(input.currentWeightKG) else { return false }
        guard input.goal != .maintain else { return true }
        guard let target = input.targetWeightKG, (35...350).contains(target) else { return false }
        return input.goal == .lose ? target < input.currentWeightKG : target > input.currentWeightKG
    }

    private func normalizeTarget(_ input: inout NutritionPlanInput) {
        if input.goal == .maintain { input.targetWeightKG = nil }
        else if input.goal == .lose, (input.targetWeightKG ?? input.currentWeightKG) >= input.currentWeightKG { input.targetWeightKG = max(35, input.currentWeightKG - 5) }
        else if input.goal == .gain, (input.targetWeightKG ?? input.currentWeightKG) <= input.currentWeightKG { input.targetWeightKG = min(350, input.currentWeightKG + 5) }
    }

    private func makePreview() {
        guard let input = edited else { return }
        do { preview = try NutritionCalculator.calculate(input: input); phase = .review }
        catch { errorMessage = error.localizedDescription }
    }

    private func save(_ input: NutritionPlanInput) {
        isSaving = true
        Task {
            do {
                try await app.updateAuthenticatedPlan(input: input)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSaved()
                dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }

    private func requestDismiss() {
        if isDirty {
            showingDiscard = true
        } else {
            dismiss()
        }
    }
    private var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        return (calendar.date(byAdding: .year, value: -120, to: .now) ?? .distantPast)...(calendar.date(byAdding: .year, value: -18, to: .now) ?? .now)
    }
    private func weightText(_ kilograms: Double) -> String {
        edited?.unitSystem == .metric ? String(format: "%.1f kg", kilograms) : String(format: "%.1f lb", kilograms * 2.20462)
    }
}

private struct InlineTargetWeightEditor: View {
    @Binding var kilograms: Double
    let unit: UnitSystem
    let currentWeightKG: Double
    let goal: WeightGoal
    @Binding var isTextValid: Bool
    @State private var text = ""
    @State private var isTyping = false
    @FocusState private var isFieldFocused: Bool

    private var displayValue: Double { unit == .metric ? kilograms : kilograms * 2.2046226218 }
    private var unitLabel: String { unit == .metric ? "kg" : "lb" }
    private var wheelSelection: Binding<WeightWheelSelection> {
        Binding(
            get: { WeightWheelSelection(kilograms: kilograms) },
            set: {
                kilograms = $0.kilograms
                isTextValid = true
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            HStack {
                Text("Target weight")
                    .foregroundStyle(LeafyTheme.green)
                Spacer()
                if isTyping {
                    HStack(spacing: LeafySpacing.xSmall) {
                        TextField("0.0", text: $text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isFieldFocused)
                            .frame(width: 92)
                            .accessibilityIdentifier("targetWeightTextField")
                        Text(unitLabel).foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        beginTyping()
                    } label: {
                        Text(String(format: "%.1f %@", displayValue, unitLabel))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Target weight, \(String(format: "%.1f", displayValue)) \(unitLabel). Tap to type.")
                    .accessibilityIdentifier("targetWeightValueButton")
                }
            }
            .font(LeafyTypography.body)
            .frame(minHeight: LeafyTheme.rowMinHeight)

            WeightWheelPicker(
                selection: wheelSelection,
                unitSystem: unit,
                identifierPrefix: "targetWeight"
            )

            if let validationMessage {
                Text(validationMessage)
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("targetWeightValidation")
            } else {
                Text("Scroll the dial or tap the number to type.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: text) { _, newValue in
            guard isTyping else { return }
            applyTypedValue(newValue)
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && isTyping { finishTyping() }
        }
        .onChange(of: unit) { _, _ in
            if isTyping { text = String(format: "%.1f", displayValue) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { finishTyping() }
            }
        }
    }

    private var validationMessage: String? {
        guard isTextValid else { return "Enter a valid weight between \(unit == .metric ? "35 and 350 kg" : "77 and 772 lb")." }
        if goal == .lose, kilograms >= currentWeightKG { return "Choose a target below your current weight." }
        if goal == .gain, kilograms <= currentWeightKG { return "Choose a target above your current weight." }
        return nil
    }

    private func beginTyping() {
        text = String(format: "%.1f", displayValue)
        isTextValid = true
        isTyping = true
        DispatchQueue.main.async { isFieldFocused = true }
    }

    private func applyTypedValue(_ value: String) {
        guard let typedValue = Double(value), typedValue.isFinite else {
            isTextValid = false
            return
        }
        let newKilograms = unit == .metric ? typedValue : typedValue / 2.2046226218
        guard (35...350).contains(newKilograms) else {
            isTextValid = false
            return
        }
        kilograms = newKilograms
        isTextValid = true
    }

    private func finishTyping() {
        if !isTextValid {
            text = String(format: "%.1f", displayValue)
            isTextValid = true
        }
        isFieldFocused = false
        isTyping = false
    }
}

private struct HeightAdjustmentView: View {
    @Binding var centimeters: Double
    let unit: UnitSystem
    var body: some View {
        HStack(spacing: LeafySpacing.small) {
            Text(unit == .metric ? "\(Int(centimeters.rounded())) cm" : imperialHeight)
            Stepper("Height", value: $centimeters, in: 120...230, step: unit == .metric ? 1 : 2.54).labelsHidden()
        }
    }
    private var imperialHeight: String {
        let selection = ImperialHeightSelection(centimeters: centimeters)
        return "\(selection.feet) ft \(selection.inches) in"
    }
}
