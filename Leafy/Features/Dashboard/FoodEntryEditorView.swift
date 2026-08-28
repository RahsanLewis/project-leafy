import SwiftUI

struct FoodEntryEditorView: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(\.dismiss) private var dismiss

    let entry: FoodEntry?
    let logDate: Date
    let embedded: Bool
    let onSaved: (() -> Void)?
    @Binding private var hasUnsavedDraft: Bool
    @State private var name: String
    @State private var caloriesText: String
    @State private var time: Date
    @State private var showDetails = false
    @State private var amountText: String
    @State private var amountUnit: String
    @State private var mealType: MealType
    @State private var confirmingDeletion = false
    @State private var nutrientValues: [String: String]
    @State private var estimatedNutrientCodes: Set<String> = []
    @State private var showingNutrientEditor = false
    @State private var loadedExistingNutrients = false

    init(
        entry: FoodEntry?,
        logDate: Date,
        embedded: Bool = false,
        onSaved: (() -> Void)? = nil,
        hasUnsavedDraft: Binding<Bool> = .constant(false)
    ) {
        self.entry = entry
        self.logDate = logDate
        self.embedded = embedded
        self.onSaved = onSaved
        _hasUnsavedDraft = hasUnsavedDraft
        _name = State(initialValue: entry?.name ?? "")
        _caloriesText = State(initialValue: entry.map { String($0.calories) } ?? "")
        _time = State(initialValue: entry?.consumedAt ?? .now)
        _showDetails = State(initialValue: entry.map { $0.amount != nil || $0.mealType != .unspecified } ?? false)
        _amountText = State(initialValue: entry?.amount.map { String(format: "%g", $0) } ?? "")
        _amountUnit = State(initialValue: entry?.amountUnit ?? "serving")
        _mealType = State(initialValue: entry?.mealType ?? .unspecified)
        _nutrientValues = State(initialValue: [:])
    }

    var body: some View {
        Group {
            if embedded {
                editorContent
            } else {
                NavigationStack { editorContent }
            }
        }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("What did you eat?")
                    TextField("Food or meal", text: $name)
                        .font(LeafyTypography.title3)
                        .textInputAutocapitalization(.sentences)
                        .padding(.vertical, LeafySpacing.medium)
                        .accessibilityIdentifier("foodNameField")
                    Divider().overlay(LeafyTheme.hairline)
                    HStack {
                        Text("Calories").font(LeafyTypography.body)
                        Spacer()
                        TextField("0", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(LeafyTypography.title3)
                            .frame(width: 100)
                            .accessibilityIdentifier("foodCaloriesField")
                        Text("Cal").foregroundStyle(.secondary)
                    }
                    .frame(minHeight: LeafyTheme.rowMinHeight)
                    Divider().overlay(LeafyTheme.hairline)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .frame(minHeight: LeafyTheme.rowMinHeight)
                }

                VStack(alignment: .leading, spacing: LeafySpacing.compact) {
                    DisclosureGroup("Serving and nutrition", isExpanded: $showDetails) {
                        VStack(spacing: 0) {
                            Picker("Meal", selection: $mealType) {
                                ForEach(MealType.allCases) { type in Text(type.label).tag(type) }
                            }
                            .frame(minHeight: LeafyTheme.rowMinHeight)
                            Divider().overlay(LeafyTheme.hairline)
                            HStack {
                                Text("Amount")
                                Spacer()
                                TextField("1", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Picker("Unit", selection: $amountUnit) {
                                    ForEach(["serving", "g", "oz", "cup", "piece", "tbsp", "tsp"], id: \.self) {
                                        Text($0).tag($0)
                                    }
                                }
                                .labelsHidden()
                            }
                            .frame(minHeight: LeafyTheme.rowMinHeight)
                            ForEach(Array(NutrientCatalog.items.prefix(3))) { nutrient in
                                Divider().overlay(LeafyTheme.hairline)
                                HStack {
                                    Text(nutrient.name)
                                    Spacer()
                                    TextField("0", text: nutrientBinding(nutrient.code))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 90)
                                    Text(nutrient.unit).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: LeafyTheme.rowMinHeight)
                            }
                            Button("Edit all nutrients") { showingNutrientEditor = true }
                                .font(LeafyTypography.subheadlineSemibold)
                                .foregroundStyle(LeafyTheme.green)
                                .frame(minHeight: LeafyTheme.rowMinHeight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, LeafySpacing.small)
                    }
                    .font(LeafyTypography.headline)
                    Text("Optional details improve nutrient totals and personalization.")
                        .font(LeafyTypography.footnote)
                        .foregroundStyle(.secondary)
                }

                if entry != nil && hasResolutionAffectingChanges {
                    Button {
                        recalculateNutrition()
                    } label: {
                        Label("Recalculate Nutrition", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                    .disabled(!input.isValid || app.isNutrientAutoFillLoading)
                }

                if let mismatchMessage {
                    inlineError(mismatchMessage, symbol: "exclamationmark.triangle")
                }
                if let message = app.dailyErrorMessage {
                    inlineError(message, symbol: "exclamationmark.triangle.fill")
                }

                if entry != nil {
                    Button("Delete from Food Log", role: .destructive) { confirmingDeletion = true }
                        .frame(maxWidth: .infinity)
                        .disabled(app.isFoodMutationInProgress)
                        .accessibilityIdentifier("deleteFoodEntryButton")
                }
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.top, LeafySpacing.medium)
            .padding(.bottom, 112)
        }
            .background(LeafyTheme.canvas)
            .navigationTitle(entry == nil ? "Log Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(entry == nil ? "Add Food" : "Save Changes") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!input.isValid || app.isFoodMutationInProgress)
                    .opacity(input.isValid ? 1 : 0.45)
                    .leafyDetachedBottomControl()
                    .accessibilityIdentifier("saveFoodButton")
            }
            .interactiveDismissDisabled(app.isFoodMutationInProgress)
            .sheet(isPresented: $confirmingDeletion) {
                LeafyConfirmationSheet(
                    title: "Delete this food entry?",
                    message: "This removes the item from your food log and updates your calorie total.",
                    confirmTitle: "Delete Food",
                    isDestructive: true,
                    confirmIdentifier: "confirmDeleteFoodEntryButton",
                    sheetIdentifier: "deleteFoodEntryConfirmationSheet"
                ) { deleteEntry() }
            }
            .overlay {
                if app.isFoodMutationInProgress {
                    Rectangle()
                        .fill(.regularMaterial)
                        .opacity(0.55)
                        .ignoresSafeArea()
                    ProgressView().controlSize(.large)
                }
            }
            .sheet(isPresented: $showingNutrientEditor) {
                NutrientEditorView(
                    input: input,
                    values: $nutrientValues,
                    estimatedCodes: $estimatedNutrientCodes,
                    loggingContext: embedded && entry == nil
                )
            }
            .task(id: entry?.id) {
                guard let entry, !loadedExistingNutrients else { return }
                let nutrients = await app.loadNutrients(for: entry)
                nutrientValues = Dictionary(uniqueKeysWithValues: nutrients.map {
                    ($0.code, String(format: "%g", $0.amount))
                })
                estimatedNutrientCodes = Set(
                    nutrients.filter { $0.derivationMethod == .estimated }.map(\.code)
                )
                loadedExistingNutrients = true
            }
            .onChange(of: name) { _, _ in updateDraftState() }
            .onChange(of: caloriesText) { _, _ in updateDraftState() }
            .onChange(of: amountText) { _, _ in updateDraftState() }
            .onChange(of: nutrientValues) { _, _ in updateDraftState() }
            .onAppear { updateDraftState() }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(LeafyTypography.captionSemibold)
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }

    private func inlineError(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(LeafyTypography.subheadline)
            .foregroundStyle(.orange)
    }

    private var hasResolutionAffectingChanges: Bool {
        guard let entry else { return false }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
        return name.trimmingCharacters(in: .whitespacesAndNewlines) != entry.name
            || amount != entry.amount
            || (amount != nil && amountUnit != entry.amountUnit)
    }

    private func recalculateNutrition() {
        Task {
            guard let estimates = await app.autoFillNutrients(for: input) else { return }
            nutrientValues = Dictionary(uniqueKeysWithValues: estimates.map {
                ($0.code, String(format: "%g", $0.amount))
            })
            estimatedNutrientCodes = Set(estimates.map(\.code))
        }
    }

    private var input: FoodEntryInput {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
        return FoodEntryInput(
            name: name,
            calories: Int(caloriesText) ?? 0,
            consumedAt: combinedDate,
            amount: amount,
            amountUnit: amount == nil ? nil : amountUnit,
            gramWeight: amountUnit == "g" ? amount : nil,
            portionDescription: amount.map { "\(String(format: "%g", $0)) \(amountUnit)" },
            mealType: mealType,
            nutrients: nutrientValues.compactMap { code, text in
                guard let amount = Double(text.replacingOccurrences(of: ",", with: ".")), amount >= 0 else { return nil }
                return NutrientAmountInput(
                    code: code,
                    amount: amount,
                    derivationMethod: estimatedNutrientCodes.contains(code) ? .estimated : .userEntered,
                    confidence: estimatedNutrientCodes.contains(code) ? 0.5 : nil
                )
            }
        )
    }

    private func nutrientBinding(_ code: String) -> Binding<String> {
        Binding(
            get: { nutrientValues[code] ?? "" },
            set: { value in nutrientValues[code] = value; estimatedNutrientCodes.remove(code) }
        )
    }

    private var mismatchMessage: String? {
        let protein = Double(nutrientValues["protein_g"] ?? "")
        let carbs = Double(nutrientValues["carbohydrate_g"] ?? "")
        let fat = Double(nutrientValues["fat_g"] ?? "")
        guard let protein, let carbs, let fat, let logged = Double(caloriesText), logged > 0 else { return nil }
        let implied = protein * 4 + carbs * 4 + fat * 9
        let difference = abs(implied - logged)
        guard difference > 100, difference / logged > 0.2 else { return nil }
        return "These macros account for about \(Int(implied.rounded())) Cal, which differs from the logged calories."
    }

    private var combinedDate: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: logDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return calendar.date(from: components) ?? logDate
    }

    private func save() {
        Task {
            let didSave: Bool
            if let entry {
                didSave = await app.updateFoodEntry(entry, input: input)
            } else {
                didSave = await app.createFoodEntry(input)
            }
            if didSave {
                if let onSaved {
                    if entry == nil { resetForAnotherEntry() }
                    hasUnsavedDraft = false
                    onSaved()
                } else { dismiss() }
            }
        }
    }

    private func updateDraftState() {
        guard entry == nil else { return }
        hasUnsavedDraft = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !caloriesText.isEmpty || !amountText.isEmpty || !nutrientValues.isEmpty
    }

    private func resetForAnotherEntry() {
        name = ""
        caloriesText = ""
        time = .now
        showDetails = false
        amountText = ""
        amountUnit = "serving"
        mealType = .unspecified
        nutrientValues = [:]
        estimatedNutrientCodes = []
        app.dailyErrorMessage = nil
    }

    private func deleteEntry() {
        guard let entry else { return }
        Task {
            if await app.deleteFoodEntry(entry) { dismiss() }
        }
    }
}
