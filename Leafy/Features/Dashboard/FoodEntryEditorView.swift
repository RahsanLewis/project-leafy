import SwiftUI

struct FoodEntryEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let entry: FoodEntry?
    let logDate: Date
    @State private var name: String
    @State private var caloriesText: String
    @State private var time: Date
    @State private var showDetails = false
    @State private var amountText: String
    @State private var amountUnit: String
    @State private var mealType: MealType

    init(entry: FoodEntry?, logDate: Date) {
        self.entry = entry
        self.logDate = logDate
        _name = State(initialValue: entry?.name ?? "")
        _caloriesText = State(initialValue: entry.map { String($0.calories) } ?? "")
        _time = State(initialValue: entry?.consumedAt ?? .now)
        _showDetails = State(initialValue: entry.map { $0.amount != nil || $0.mealType != .unspecified } ?? false)
        _amountText = State(initialValue: entry?.amount.map { String(format: "%g", $0) } ?? "")
        _amountUnit = State(initialValue: entry?.amountUnit ?? "serving")
        _mealType = State(initialValue: entry?.mealType ?? .unspecified)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food or meal", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("foodNameField")
                    HStack {
                        TextField("Calories", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("foodCaloriesField")
                        Text("kcal").foregroundStyle(.secondary)
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
                    }
                } footer: {
                    Text("Optional serving details make nutrient estimates and your personalized calorie budget more accurate.")
                }

                if let message = app.dailyErrorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(entry == nil ? "Log Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            .overlay {
                if app.isFoodMutationInProgress {
                    ProgressView().padding(18).background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
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
            mealType: mealType
        )
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
            if didSave { dismiss() }
        }
    }
}
