import SwiftUI
import UIKit

struct ProductDetailView: View {
    @Environment(AppCoordinator.self) private var app
    let product: ProductDetail
    let intent: ProductDiscoveryIntent
    let impactContext: FoodImpactContext
    private let referenceServingGrams: Double
    private let analyzedGrams: Double
    let onLogged: () -> Void
    @State private var servingCountText = "1"
    @State private var consumedAt = Date()
    @State private var mealType: MealType = .unspecified
    @State private var showingImpact = false
    @State private var showingIngredients = true
    @State private var showingProductDetails = false
    @State private var showingLabelUpdate = false

    init(
        product: ProductDetail,
        intent: ProductDiscoveryIntent,
        impactContext: FoodImpactContext = .prospective,
        logDate: Date = .now,
        initialGrams: Double? = nil,
        onLogged: @escaping () -> Void
    ) {
        self.product = product
        self.intent = intent
        self.impactContext = impactContext
        self.onLogged = onLogged
        self.referenceServingGrams = max(product.defaultGrams, 1)
        self.analyzedGrams = max(initialGrams ?? product.defaultGrams, 1)
        _consumedAt = State(initialValue: Self.logDate(logDate, usingTimeFrom: .now))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LeafySpacing.large) {
                ServingNutritionHero(
                    name: product.name,
                    subtitle: heroSubtitle,
                    calories: estimatedCalories,
                    nutrients: servingNutrients,
                    showsCalories: false,
                    showsMacros: false
                )

                if intent == .log {
                    loggingControls
                }

                if let score = product.score { leafyScore(score) }
                else { unavailableScore(title: "Score not calculated", reasons: ["Leafy has not calculated this product yet."]) }

                if app.configuration.isFoodImpactEnabled {
                    DisclosureGroup("How it fits today", isExpanded: $showingImpact) {
                        FoodImpactDashboard(
                            input: impactInput,
                            servingScale: impactScale,
                            servingDescription: { scale in
                                "\((referenceServingGrams * scale).formatted(.number.precision(.fractionLength(0...1)))) g"
                            },
                            showsHeader: false
                        )
                        .padding(.top, LeafySpacing.small)
                    }
                    .font(LeafyTypography.title3)
                    .tint(LeafyTheme.green)
                }

                PackageNutritionFactsView(
                    servingDescription: packageServingLabel,
                    servingsPerContainer: product.servingsPerContainer,
                    nutrients: nutritionFactsNutrients,
                    packageFootnote: product.nutritionFootnote
                )

                if hasIngredientInformation {
                    DisclosureGroup("Ingredients & allergens", isExpanded: $showingIngredients) {
                        IngredientParagraphView(
                            ingredients: product.ingredients ?? "",
                            allergens: product.allergens
                        )
                        .padding(.top, LeafySpacing.small)
                    }
                    .font(LeafyTypography.headline)
                    .tint(LeafyTheme.green)
                }

                DisclosureGroup("Product information", isExpanded: $showingProductDetails) {
                    VStack(spacing: 0) {
                        detailRow("Brand", product.brand ?? "Not listed")
                        detailRow("Source", product.source)
                        if let barcode = product.barcode { detailRow("Barcode", barcode) }
                    }
                    .padding(.top, LeafySpacing.small)
                }
                .font(LeafyTypography.headline)
                .tint(LeafyTheme.green)

                if let message = app.productErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.orange)
                }

                Text(productGuidance)
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.top, LeafySpacing.medium)
            .padding(.bottom, intent == .log ? 112 : LeafySpacing.xxLarge)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LeafyTheme.canvas)
        .navigationTitle("Food details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if intent == .log {
                Button(app.isFoodMutationInProgress ? "Adding…" : "Add to Food Log") {
                    Task {
                        if await app.logProduct(product, grams: effectiveGrams, consumedAt: consumedAt, mealType: mealType) {
                            onLogged()
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(app.isFoodMutationInProgress || validServingCount == nil)
                .opacity(validServingCount == nil ? 0.45 : 1)
                .leafyDetachedBottomControl()
            }
        }
        .alert("Couldn’t load product", isPresented: Binding(
            get: { intent != .log && app.productErrorMessage != nil },
            set: { if !$0 { app.productErrorMessage = nil } }
        )) {
            Button("OK") { app.productErrorMessage = nil }
        } message: { Text(app.productErrorMessage ?? "") }
        .navigationDestination(isPresented: $showingLabelUpdate) {
            if let barcode = product.barcode {
                CatalogContributionView(
                    barcode: barcode,
                    intent: intent,
                    onCompleted: {},
                    refreshExisting: true
                )
            }
        }
    }

    private var heroSubtitle: String? {
        let details = intent == .log ? [product.brand] : [product.brand, analyzedServingLabel]
        let subtitle = details.compactMap { $0 }.joined(separator: " · ")
        return subtitle.isEmpty ? nil : subtitle
    }
    private var hasIngredientInformation: Bool {
        !(product.ingredients?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || !product.allergens.isEmpty
    }
    private var analyzedServingLabel: String {
        if let portion = matchingPortion(for: analyzedGrams) {
            let description = portion.description ?? "\(portion.amount.formatted()) \(portion.unit)"
            return "\(description) (\(portion.gramWeight.formatted(.number.precision(.fractionLength(0...1)))) g)"
        }
        return analyzedGrams == 100 ? "Per 100 g" : "\(analyzedGrams.formatted(.number.precision(.fractionLength(0...1)))) g"
    }
    private var referenceServingLabel: String {
        if let portion = product.portions.first {
            let description = portion.description ?? "\(portion.amount.formatted()) \(portion.unit)"
            return "\(description) (\(portion.gramWeight.formatted(.number.precision(.fractionLength(0...1)))) g)"
        }
        return "100 g"
    }
    private var packageServingLabel: String {
        let household: String? = {
            if let portion = product.portions.first, let description = portion.description, !description.isEmpty { return description }
            if let size = product.servingSize, let unit = product.servingUnit { return "\(size.formatted(.number.precision(.fractionLength(0...2)))) \(unit)" }
            return nil
        }()
        let metric: String? = {
            if let size = product.metricServingSize, let unit = product.metricServingUnit { return "\(size.formatted(.number.precision(.fractionLength(0...2)))) \(unit)" }
            if let portion = product.portions.first { return "\(portion.gramWeight.formatted(.number.precision(.fractionLength(0...1)))) g" }
            if let size = product.servingSize, ["g", "gram", "grams"].contains(product.servingUnit?.lowercased() ?? "") { return "\(size.formatted(.number.precision(.fractionLength(0...1)))) g" }
            return nil
        }()
        if let household, let metric, !household.localizedCaseInsensitiveContains(metric) { return "\(household) (\(metric))" }
        return household ?? metric ?? "Serving information unavailable"
    }
    private var nutritionFactsNutrients: [ProductLabelNutrient] {
        if let values = product.labelNutrients, !values.isEmpty { return values }
        guard ["g", "gram", "grams", "grm"].contains(product.servingUnit?.lowercased() ?? "") else { return [] }
        return product.nutrients.map { nutrient in
            let amount = nutrient.amountPer100G * product.defaultGrams / 100
            return ProductLabelNutrient(
                code: nutrient.code,
                amountPerServing: amount,
                unit: Self.unit(for: nutrient.code),
                percentDailyValue: Self.dailyValue(for: nutrient.code).map { amount / $0 * 100 },
                declarationType: "derived",
                printedText: nil,
                evidenceSection: "normalized_database",
                valueSource: "source_derived"
            )
        }
    }
    private static func unit(for code: String) -> String {
        if code == "energy_kcal" { return "kcal" }
        if code.contains("_mcg") { return "mcg" }
        if code.contains("_mg") { return "mg" }
        return "g"
    }
    private static func dailyValue(for code: String) -> Double? {
        [
            "fat_g": 78, "saturated_fat_g": 20, "cholesterol_mg": 300, "sodium_mg": 2300,
            "carbohydrate_g": 275, "fiber_g": 28, "added_sugars_g": 50,
            "vitamin_d_mcg": 20, "calcium_mg": 1300, "iron_mg": 18, "potassium_mg": 4700,
            "vitamin_a_mcg_rae": 900, "vitamin_c_mg": 90, "vitamin_e_mg": 15,
            "vitamin_k_mcg": 120, "thiamin_mg": 1.2, "riboflavin_mg": 1.3,
            "niacin_mg_ne": 16, "vitamin_b6_mg": 1.7, "folate_mcg_dfe": 400,
            "vitamin_b12_mcg": 2.4, "biotin_mcg": 30, "pantothenic_acid_mg": 5,
            "phosphorus_mg": 1250, "iodine_mcg": 150, "zinc_mg": 11,
            "selenium_mcg": 55, "copper_mg": 0.9, "manganese_mg": 2.3,
            "chromium_mcg": 35, "molybdenum_mcg": 45, "chloride_mg": 2300,
            "choline_mg": 550,
        ][code]
    }
    private func matchingPortion(for grams: Double) -> ProductPortion? {
        product.portions.first { abs($0.gramWeight - grams) < 0.01 }
    }
    private var validServingCount: Double? {
        intent == .log ? ProductServingQuantity.count(from: servingCountText) : 1
    }
    private var effectiveGrams: Double {
        guard intent == .log else { return analyzedGrams }
        guard let validServingCount else { return 0 }
        return ProductServingQuantity.grams(servings: validServingCount, servingGrams: referenceServingGrams)
    }
    private var servingNutrients: [NutrientAmountInput] {
        product.nutrients.map {
            NutrientAmountInput(
                code: $0.code,
                amount: $0.amountPer100G * effectiveGrams / 100,
                derivationMethod: .label,
                sourceVersion: product.verificationStatus
            )
        }
    }
    private var loggingControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add to food log").font(LeafyTypography.title3).padding(.bottom, LeafySpacing.small)
            servingCountControl
            Divider().overlay(LeafyTheme.hairline)
            DatePicker("Time", selection: $consumedAt, displayedComponents: .hourAndMinute)
                .frame(minHeight: LeafyTheme.rowMinHeight)
            Divider().overlay(LeafyTheme.hairline)
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases) { Text($0.label).tag($0) }
            }
            .frame(minHeight: LeafyTheme.rowMinHeight)
        }
    }
    private var servingCountControl: some View {
        HStack(spacing: LeafySpacing.compact) {
            VStack(alignment: .leading, spacing: 3) {
                Text("How many servings did you eat?")
                    .font(LeafyTypography.bodyMedium)
                Text("1 serving = \(referenceServingLabel)")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: LeafySpacing.small)
            HStack(spacing: LeafySpacing.xSmall) {
                servingAdjustmentButton(symbol: "minus", delta: -ProductServingQuantity.step)
                TextField("1", text: $servingCountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(LeafyTypography.headline)
                    .monospacedDigit()
                    .frame(width: 62, height: LeafyTheme.minimumTouchTarget)
                    .background(LeafyTheme.track, in: .rect(cornerRadius: LeafyRadius.control))
                    .accessibilityLabel("Number of servings")
                    .accessibilityIdentifier("productServingCountField")
                servingAdjustmentButton(symbol: "plus", delta: ProductServingQuantity.step)
            }
        }
        .frame(minHeight: 72)
    }
    private func servingAdjustmentButton(symbol: String, delta: Double) -> some View {
        Button {
            let current = validServingCount ?? 1
            let adjusted = min(max(current + delta, ProductServingQuantity.allowedRange.lowerBound), ProductServingQuantity.allowedRange.upperBound)
            servingCountText = ProductServingQuantity.formatted(adjusted)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: symbol)
                .font(LeafyTypography.bodyMedium)
                .frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LeafyTheme.green)
        .disabled(symbol == "minus" && (validServingCount ?? 1) <= ProductServingQuantity.allowedRange.lowerBound)
        .accessibilityLabel(symbol == "minus" ? "Decrease servings" : "Increase servings")
    }
    private var estimatedCalories: Int { Int(((product.caloriesPer100G ?? 0) * effectiveGrams / 100).rounded()) }
    private var productGuidance: String {
        if app.configuration.isFoodImpactEnabled {
            return "Nutrition and food-impact information is general wellness guidance. Always check the package if you have an allergy."
        }
        return "Nutrition information is general wellness guidance. Always check the package if you have an allergy."
    }
    private var impactScale: Binding<Double> {
        Binding(
            get: { min(max(effectiveGrams / referenceServingGrams, 0.25), 3) },
            set: { scale in
                guard intent == .log else { return }
                servingCountText = ProductServingQuantity.formatted(scale)
            }
        )
    }
    private var impactInput: FoodImpactInput {
        let nutrients = product.nutrients.map {
            NutrientAmountInput(
                code: $0.code,
                amount: $0.amountPer100G * referenceServingGrams / 100,
                derivationMethod: .label,
                sourceVersion: product.verificationStatus
            )
        }
        return FoodImpactInput(
            name: product.name,
            baseCalories: (product.caloriesPer100G ?? 0) * referenceServingGrams / 100,
            nutrients: nutrients,
            provenance: product.verificationStatus == "verified" ? "Verified product data" : product.source,
            confidence: product.verificationStatus == "verified" ? 1 : product.verificationStatus == "community_confirmed" ? 0.95 : 0.8,
            context: impactContext
        )
    }
    private static func logDate(_ day: Date, usingTimeFrom time: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components) ?? day
    }
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: LeafySpacing.medium)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .font(LeafyTypography.body)
        .frame(minHeight: LeafyTheme.rowMinHeight)
        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
    }

    private func leafyScore(_ score: ProductNutritionScore) -> some View {
        if !score.isAvailable {
            return AnyView(unavailableScore(
                title: score.scoreStatus == "ineligible" ? "Not scored by this model" : "Calculating Leafy Score",
                reasons: friendlyScoreReasons(score)
            ))
        }
        return AnyView(LeafyScoreSummary(
            score: score,
            subtitle: "Packaged food quality",
            improvementReasons: LeafyScorePresentation.improvementReasons(for: score),
            onImprove: score.isProvisional && product.barcode != nil && scoreNeedsLabelUpdate ? { showingLabelUpdate = true } : nil
        ))
    }

    private func unavailableScore(title: String, reasons: [String]) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leafy Score").font(LeafyTypography.title3)
                    Text(title).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("—").font(LeafyTypography.metric(40)).foregroundStyle(.secondary)
            }
            ForEach(reasons.prefix(3), id: \.self) { reason in
                Label(reason, systemImage: "info.circle")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }
            if product.barcode != nil && scoreNeedsLabelUpdate {
                Button("Add package label") { showingLabelUpdate = true }
                    .font(LeafyTypography.button)
                    .foregroundStyle(LeafyTheme.green)
                    .frame(minHeight: LeafyTheme.minimumTouchTarget)
                    .accessibilityIdentifier("addPackageLabelForScoreButton")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("leafyScoreUnavailable")
    }

    private var scoreNeedsLabelUpdate: Bool {
        guard let score = product.score else { return product.barcode != nil }
        return score.missingFields.contains { !$0.hasPrefix("ingredient_classification:") }
    }

    private func friendlyScoreReasons(_ score: ProductNutritionScore) -> [String] {
        let reasons = LeafyScorePresentation.improvementReasons(for: score)
        return reasons.isEmpty ? ["More verified package information is needed."] : reasons
    }
}

private struct PackageNutritionFactsView: View {
    let servingDescription: String
    let servingsPerContainer: String?
    let nutrients: [ProductLabelNutrient]
    let packageFootnote: String?

    private static let order = [
        "fat_g", "saturated_fat_g", "trans_fat_g", "cholesterol_mg", "sodium_mg",
        "carbohydrate_g", "fiber_g", "sugars_g", "added_sugars_g", "protein_g",
        "vitamin_d_mcg", "calcium_mg", "iron_mg", "potassium_mg",
        "vitamin_a_mcg_rae", "vitamin_c_mg", "vitamin_e_mg", "vitamin_k_mcg",
        "thiamin_mg", "riboflavin_mg", "niacin_mg_ne", "vitamin_b6_mg",
        "folate_mcg_dfe", "vitamin_b12_mcg", "biotin_mcg", "pantothenic_acid_mg",
        "phosphorus_mg", "iodine_mcg", "magnesium_mg", "zinc_mg", "selenium_mcg",
        "copper_mg", "manganese_mg", "chromium_mcg", "molybdenum_mcg", "chloride_mg",
        "choline_mg", "caffeine_mg",
    ]
    private static let names: [String: String] = [
        "fat_g": "Total Fat", "saturated_fat_g": "Saturated Fat", "trans_fat_g": "Trans Fat",
        "cholesterol_mg": "Cholesterol", "sodium_mg": "Sodium", "carbohydrate_g": "Total Carbohydrate",
        "fiber_g": "Dietary Fiber", "sugars_g": "Total Sugars", "added_sugars_g": "Includes Added Sugars",
        "protein_g": "Protein", "vitamin_d_mcg": "Vitamin D", "calcium_mg": "Calcium", "iron_mg": "Iron",
        "potassium_mg": "Potassium", "vitamin_a_mcg_rae": "Vitamin A", "vitamin_c_mg": "Vitamin C",
        "vitamin_e_mg": "Vitamin E", "vitamin_k_mcg": "Vitamin K", "thiamin_mg": "Thiamin",
        "riboflavin_mg": "Riboflavin", "niacin_mg_ne": "Niacin", "vitamin_b6_mg": "Vitamin B6",
        "folate_mcg_dfe": "Folate", "vitamin_b12_mcg": "Vitamin B12", "biotin_mcg": "Biotin",
        "pantothenic_acid_mg": "Pantothenic Acid", "phosphorus_mg": "Phosphorus", "iodine_mcg": "Iodine",
        "magnesium_mg": "Magnesium", "zinc_mg": "Zinc", "selenium_mcg": "Selenium", "copper_mg": "Copper",
        "manganese_mg": "Manganese", "chromium_mcg": "Chromium", "molybdenum_mcg": "Molybdenum",
        "chloride_mg": "Chloride", "choline_mg": "Choline", "caffeine_mg": "Caffeine",
    ]
    private static let indented = Set(["saturated_fat_g", "trans_fat_g", "fiber_g", "sugars_g"])

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts")
                .font(LeafyTypography.metric(30, extraBold: true))
                .padding(.bottom, 2)
            if let servingsPerContainer, !servingsPerContainer.isEmpty {
                Text("\(servingsPerContainer) servings per container")
                    .font(LeafyTypography.subheadline)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Serving size").font(LeafyTypography.headline)
                Spacer(minLength: LeafySpacing.small)
                Text(servingDescription).font(LeafyTypography.headline).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 4)
            thickRule(8)
            Text("Amount per serving")
                .font(LeafyTypography.captionSemibold)
                .padding(.top, 3)
            HStack(alignment: .lastTextBaseline) {
                Text("Calories").font(LeafyTypography.title2)
                Spacer()
                Text(calories).font(LeafyTypography.metric(40, extraBold: true)).monospacedDigit()
            }
            thickRule(5)
            Text("% Daily Value*")
                .font(LeafyTypography.captionSemibold)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 3)

            if orderedNutrients.isEmpty {
                Text("Package nutrition values are unavailable.")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, LeafySpacing.medium)
            } else {
                ForEach(Array(orderedNutrients.enumerated()), id: \.element.code) { index, nutrient in
                    nutrientRow(nutrient)
                    if index < orderedNutrients.count - 1 { Divider().overlay(Color.primary.opacity(0.45)) }
                    if nutrient.code == "protein_g" { thickRule(5) }
                }
            }

            let footnote = packageFootnote?.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(footnote?.isEmpty == false ? footnote! : "* The % Daily Value tells you how much a nutrient in a serving contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                .font(LeafyTypography.caption)
                .padding(.top, LeafySpacing.small)
            if nutrients.contains(where: \.isDerived) {
                Text("† Some serving amounts or % Daily Values are derived from source data rather than transcribed from the package.")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(LeafySpacing.medium)
        .background(LeafyTheme.surface, in: .rect(cornerRadius: LeafyRadius.prominent))
        .overlay(RoundedRectangle(cornerRadius: LeafyRadius.prominent).stroke(Color.primary.opacity(0.8), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("packageNutritionFacts")
    }

    private var calories: String {
        guard let value = nutrients.first(where: { $0.code == "energy_kcal" }) else { return "—" }
        return value.amountPerServing.formatted(.number.precision(.fractionLength(0)))
    }
    private var orderedNutrients: [ProductLabelNutrient] {
        nutrients.filter { $0.code != "energy_kcal" }.sorted {
            (Self.order.firstIndex(of: $0.code) ?? Int.max) < (Self.order.firstIndex(of: $1.code) ?? Int.max)
        }
    }
    private func nutrientRow(_ nutrient: ProductLabelNutrient) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LeafySpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Self.names[nutrient.code] ?? nutrient.code.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(isPrimary(nutrient.code) ? LeafyTypography.subheadlineSemibold : LeafyTypography.subheadline)
                Text(amount(nutrient)).font(LeafyTypography.subheadline).monospacedDigit()
            }
            .padding(.leading, indent(for: nutrient.code))
            Spacer(minLength: LeafySpacing.xSmall)
            if let percent = nutrient.percentDailyValue {
                Text("\(percent.formatted(.number.precision(.fractionLength(0))))%")
                    .font(LeafyTypography.subheadlineSemibold)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
    private func amount(_ nutrient: ProductLabelNutrient) -> String {
        "\(nutrient.amountPerServing.formatted(.number.precision(.fractionLength(0...2))))\(nutrient.unit)"
    }
    private func indent(for code: String) -> CGFloat {
        code == "added_sugars_g" ? 28 : Self.indented.contains(code) ? 14 : 0
    }
    private func isPrimary(_ code: String) -> Bool {
        ["fat_g", "cholesterol_mg", "sodium_mg", "carbohydrate_g", "protein_g"].contains(code)
    }
    private func thickRule(_ height: CGFloat) -> some View {
        Rectangle().fill(Color.primary).frame(height: height)
    }
}

private struct IngredientParagraphView: View {
    let ingredients: String
    let allergens: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            if !allergens.isEmpty {
                Label {
                    Text("Contains: ") + Text(allergens.joined(separator: ", ")).bold()
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.orange)
                .accessibilityLabel("Contains allergens: \(allergens.joined(separator: ", "))")
            }
            if !cleanedIngredients.isEmpty {
                Text(cleanedIngredients)
                    .font(LeafyTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityLabel(cleanedIngredients)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readableIngredients")
    }

    private var cleanedIngredients: String {
        IngredientPresentation.cleaned(ingredients)
    }
}

enum IngredientPresentation {
    static func cleaned(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^\s*ingredients?\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
