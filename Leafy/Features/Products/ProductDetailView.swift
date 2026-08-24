import SwiftUI
import UIKit

struct ProductDetailView: View {
    @Environment(AppModel.self) private var app
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
    @State private var showingIngredients = false
    @State private var showingProductDetails = false
    @State private var showingScoreDetails = false

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
            LazyVStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                ServingNutritionHero(
                    name: product.name,
                    subtitle: heroSubtitle,
                    calories: estimatedCalories,
                    nutrients: servingNutrients
                )

                if intent == .log {
                    loggingControls
                }

                if let score = product.score, score.isAvailable {
                    leafyScore(score)
                }

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

                NutritionValueDisclosure(title: "Nutrition", nutrients: servingNutrients)

                if let ingredients = product.ingredients, !ingredients.isEmpty || !product.allergens.isEmpty {
                    DisclosureGroup("Ingredients & allergens", isExpanded: $showingIngredients) {
                        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
                            if !ingredients.isEmpty {
                                Text(ingredients).font(LeafyTypography.body).foregroundStyle(.secondary)
                            }
                            if !product.allergens.isEmpty {
                                VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                                    Text("Allergens").font(LeafyTypography.subheadlineSemibold)
                                    Text(product.allergens.joined(separator: ", "))
                                        .font(LeafyTypography.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, LeafySpacing.small)
                    }
                    .font(LeafyTypography.headline)
                    .tint(LeafyTheme.green)
                }

                DisclosureGroup("Product information", isExpanded: $showingProductDetails) {
                    VStack(spacing: 0) {
                        detailRow("Brand", product.brand ?? "Not listed")
                        detailRow("Source", product.source)
                        if let verificationLabel { detailRow("Verification", verificationLabel) }
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
    }

    private var heroSubtitle: String? {
        let details = intent == .log ? [product.brand] : [product.brand, analyzedServingLabel]
        let subtitle = details.compactMap { $0 }.joined(separator: " · ")
        return subtitle.isEmpty ? nil : subtitle
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
    private var verificationLabel: String? {
        switch product.verificationStatus {
        case "verified": "Verified"
        case "community_confirmed": "Leafy reviewed"
        case "unverified": "Community submitted"
        default: nil
        }
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
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leafy Score").font(LeafyTypography.title3)
                    Text("Packaged food quality").font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(score.score.map(String.init) ?? "—")
                    .font(LeafyTypography.metric(40))
                Text("/100").font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            }
            if let rating = score.rating {
                Text(rating).font(LeafyTypography.headline).foregroundStyle(LeafyTheme.green)
            }
            if score.flags.regulatoryFlag {
                Label("Regulatory concern identified", systemImage: "exclamationmark.triangle.fill")
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(.orange)
            }
            DisclosureGroup("Why this score", isExpanded: $showingScoreDetails) {
                VStack(alignment: .leading, spacing: LeafySpacing.medium) {
                    scoreFactors("Strengths", score.strengths, color: LeafyTheme.green)
                    scoreFactors("What lowered it", score.weaknesses, color: .orange)
                    HStack {
                        Text("Base score")
                        Spacer()
                        Text(score.baseScore.map(String.init) ?? "—")
                    }
                    HStack {
                        Text("Ingredient concern adjustment")
                        Spacer()
                        Text(score.additivePenalty == 0 ? "0" : "−\(score.additivePenalty)")
                    }
                    .foregroundStyle(score.additivePenalty == 0 ? Color.secondary : Color.orange)
                    Text("PFQS is comparative wellness guidance, not a medical diagnosis or government-approved health claim.")
                        .font(LeafyTypography.footnote)
                        .foregroundStyle(.secondary)
                }
                .font(LeafyTypography.subheadline)
                .padding(.top, LeafySpacing.small)
            }
            .font(LeafyTypography.headline)
            .tint(LeafyTheme.green)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func scoreFactors(_ title: String, _ factors: [String], color: Color) -> some View {
        if !factors.isEmpty {
            VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                Text(title).font(LeafyTypography.subheadlineSemibold)
                ForEach(factors, id: \.self) { factor in
                    HStack(alignment: .top, spacing: LeafySpacing.xSmall) {
                        Circle().fill(color).frame(width: 5, height: 5).padding(.top, 7)
                        Text(factor).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
