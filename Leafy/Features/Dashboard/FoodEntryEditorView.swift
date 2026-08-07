import SwiftUI

struct FoodEntryEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let entry: FoodEntry?
    let logDate: Date
    let embedded: Bool
    let onSaved: (() -> Void)?
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
        onSaved: (() -> Void)? = nil
    ) {
        self.entry = entry
        self.logDate = logDate
        self.embedded = embedded
        self.onSaved = onSaved
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
        Form {
                Section {
                    TextField("Food or meal", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("foodNameField")
                    HStack {
                        TextField("Calories", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("foodCaloriesField")
                        Text("Cal").foregroundStyle(.secondary)
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                } header: {
                    Text("What did you eat?")
                } footer: {
                    Text("You can edit the name, calories, or time later from your food log.")
                }

                Section {
                    DisclosureGroup("Add serving details", isExpanded: $showDetails) {
                        Picker("Meal", selection: $mealType) {
                            ForEach(MealType.allCases) { type in Text(type.label).tag(type) }
                        }
                        HStack {
                            TextField("Amount", text: $amountText)
                                .keyboardType(.decimalPad)
                            Picker("Unit", selection: $amountUnit) {
                                ForEach(["serving", "g", "oz", "cup", "piece", "tbsp", "tsp"], id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                        ForEach(Array(NutrientCatalog.items.prefix(3))) { nutrient in
                            HStack {
                                Text(nutrient.name)
                                Spacer()
                                TextField("0", text: nutrientBinding(nutrient.code))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                Text(nutrient.unit).foregroundStyle(.secondary)
                            }
                        }
                        Button("Edit all nutrients") { showingNutrientEditor = true }
                            .foregroundStyle(LeafyTheme.green)
                    }
                } footer: {
                    Text("Optional serving details make nutrient estimates and your personalized calorie budget more accurate.")
                }

                if let mismatchMessage {
                    Section {
                        Label(mismatchMessage, systemImage: "exclamationmark.triangle")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                if let message = app.dailyErrorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                if entry != nil {
                    Section {
                        Button("Delete from Food Log", role: .destructive) {
                            confirmingDeletion = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(app.isFoodMutationInProgress)
                        .accessibilityIdentifier("deleteFoodEntryButton")
                    }
                }
            }
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
                    .padding(20)
                    .background(.regularMaterial)
                    .accessibilityIdentifier("saveFoodButton")
            }
            .interactiveDismissDisabled(app.isFoodMutationInProgress)
            .confirmationDialog(
                "Delete this food entry?",
                isPresented: $confirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete Food", role: .destructive) { deleteEntry() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the item from your food log and updates your calorie total.")
            }
            .overlay {
                if app.isFoodMutationInProgress {
                    ProgressView().padding(18).background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .sheet(isPresented: $showingNutrientEditor) {
                NutrientEditorView(
                    input: input,
                    values: $nutrientValues,
                    estimatedCodes: $estimatedNutrientCodes
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
                if let onSaved { onSaved() }
                else { dismiss() }
            }
        }
    }

    private func deleteEntry() {
        guard let entry else { return }
        Task {
            if await app.deleteFoodEntry(entry) { dismiss() }
        }
    }
}
