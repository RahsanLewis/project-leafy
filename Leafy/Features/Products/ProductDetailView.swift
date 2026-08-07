import SwiftUI

struct ProductDetailView: View {
    @Environment(AppModel.self) private var app
    let product: ProductDetail
    let intent: ProductDiscoveryIntent
    let onLogged: () -> Void
    @State private var grams: Double
    @State private var consumedAt = Date()
    @State private var mealType: MealType = .unspecified

    init(
        product: ProductDetail,
        intent: ProductDiscoveryIntent,
        logDate: Date = .now,
        initialGrams: Double? = nil,
        onLogged: @escaping () -> Void
    ) {
        self.product = product; self.intent = intent; self.onLogged = onLogged
        _grams = State(initialValue: initialGrams ?? product.defaultGrams)
        _consumedAt = State(initialValue: Self.logDate(logDate, usingTimeFrom: .now))
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    ScoreBadge(score: product.score?.score, label: product.score?.label)
                        .scaleEffect(1.7).padding(.vertical, 22)
                    Text(product.score?.label ?? "Not enough data to score").font(LeafyTypography.title2)
                    Text("Nutrition score").font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .leafyBorderlessRows(separators: false)
            Section("Product") {
                LabeledContent("Brand", value: product.brand ?? "Not listed")
                LabeledContent("Source", value: product.source)
                if let barcode = product.barcode { LabeledContent("Barcode", value: barcode) }
                if intent == .analyze {
                    LabeledContent("Serving") {
                        HStack {
                            TextField("100", value: $grams, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Text("g").foregroundStyle(.secondary)
                        }
                        .frame(width: 130)
                    }
                }
            }
            .leafyBorderlessRows()
            Section("Nutrition for \(grams.formatted(.number.precision(.fractionLength(0...1)))) g") {
                nutrient("Calories", code: "energy_kcal", unit: "Cal")
                ForEach(NutrientCatalog.items) { item in
                    nutrient(item.name, code: item.code, unit: item.unit)
                }
            }
            .leafyBorderlessRows()
            if let score = product.score, !(score.positiveFactors + score.limitingFactors).isEmpty {
                Section("What affects the score") {
                    ForEach(score.positiveFactors, id: \.self) { Label($0, systemImage: "checkmark.circle.fill").foregroundStyle(LeafyTheme.green) }
                    ForEach(score.limitingFactors, id: \.self) { Label($0, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                }
                .leafyBorderlessRows()
            }
            if let ingredients = product.ingredients, !ingredients.isEmpty {
                Section("Ingredients") { Text(ingredients).font(LeafyTypography.subheadline).foregroundStyle(.secondary) }
                    .leafyBorderlessRows(separators: false)
            }
            if intent == .log {
                Section("Add to food log") {
                    LabeledContent("Amount") {
                        HStack { TextField("100", value: $grams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("g").foregroundStyle(.secondary) }.frame(width: 130)
                    }
                    DatePicker("Time", selection: $consumedAt, displayedComponents: .hourAndMinute)
                    Picker("Meal", selection: $mealType) { ForEach(MealType.allCases) { Text($0.label).tag($0) } }
                    LabeledContent("Estimated calories", value: "\(estimatedCalories) Cal")
                }
                .leafyBorderlessRows()
            }
            Section {
                Text("Leafy’s score evaluates nutrition data only. Ingredients and allergens are informational; always check the package if you have an allergy.")
                    .font(LeafyTypography.footnote).foregroundStyle(.secondary)
            }
            .leafyBorderlessRows(separators: false)
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.large)
        .navigationTitle(product.name.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if intent == .log {
                Button(app.isFoodMutationInProgress ? "Adding…" : "Add to Food Log") {
                    Task { if await app.logProduct(product, grams: grams, consumedAt: consumedAt, mealType: mealType) { onLogged() } }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(app.isFoodMutationInProgress || grams <= 0)
                .padding().background(.regularMaterial)
            }
        }
        .alert("Couldn’t add food", isPresented: .constant(app.productErrorMessage != nil)) {
            Button("OK") { app.productErrorMessage = nil }
        } message: { Text(app.productErrorMessage ?? "") }
    }

    private var estimatedCalories: Int { Int(((product.caloriesPer100G ?? 0) * grams / 100).rounded()) }
    private static func logDate(_ day: Date, usingTimeFrom time: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components) ?? day
    }

    @ViewBuilder private func nutrient(_ title: String, code: String, unit: String) -> some View {
        if let value = product.nutrients.first(where: { $0.code == code })?.amountPer100G {
            let servingValue = value * grams / 100
            LabeledContent(title, value: "\(servingValue.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
        }
    }
}
