import SwiftUI

struct FoodEntryNutritionView: View {
    @Environment(AppModel.self) private var app
    let entry: FoodEntry
    @State private var product: ProductDetail?
    @State private var attemptedLoad = false

    var body: some View {
        Group {
            if entry.canonicalFoodVersionID == nil {
                LimitedFoodNutritionView(entry: entry)
            } else if let product {
                ProductDetailView(
                    product: product,
                    intent: .analyze,
                    impactContext: .logged,
                    initialGrams: entry.gramWeight,
                    onLogged: {}
                )
            } else if app.isProductLoading || !attemptedLoad {
                ProgressView("Loading nutrition…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LeafyTheme.canvas)
            } else {
                ContentUnavailableView {
                    Label("Nutrition unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(app.productErrorMessage ?? "Leafy couldn’t load this product’s nutrition profile.")
                } actions: {
                    Button("Try Again") { Task { await loadProduct() } }
                        .buttonStyle(.borderedProminent)
                        .tint(LeafyTheme.green)
                    NavigationLink("View Logged Details") { LimitedFoodNutritionView(entry: entry) }
                }
            }
        }
        .task(id: entry.id) {
            guard entry.canonicalFoodVersionID != nil else { return }
            await loadProduct()
        }
    }

    private func loadProduct() async {
        attemptedLoad = false
        product = await app.loadProductDetail(for: entry)
        attemptedLoad = true
    }
}

struct ServingNutritionHero: View {
    let name: String
    let subtitle: String?
    let calories: Int
    let nutrients: [NutrientAmountInput]

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                Text(name.capitalized).font(LeafyTypography.title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: LeafySpacing.small) {
                Text(calories.formatted()).font(LeafyTypography.metric(52, extraBold: true)).monospacedDigit()
                Text("Cal").font(LeafyTypography.title3).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: LeafySpacing.large) {
                macro("Protein", code: "protein_g")
                macro("Carbs", code: "carbohydrate_g")
                macro("Fat", code: "fat_g")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func macro(_ title: String, code: String) -> some View {
        if let value = nutrients.first(where: { $0.code == code }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LeafyTypography.caption).foregroundStyle(.secondary)
                Text("\(format(value.amount)) g").font(LeafyTypography.title3).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct NutritionValueDisclosure: View {
    let title: String
    let nutrients: [NutrientAmountInput]
    @State private var expandedGroups: Set<NutritionGroup> = []

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            Text(title).font(LeafyTypography.title3)
            ForEach(groups, id: \.self) { group in
                let items = NutrientCatalog.items.filter { $0.group == group && amount(for: $0.code) != nil }
                if !items.isEmpty {
                    DisclosureGroup(isExpanded: binding(for: group)) {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.name)
                                    Spacer()
                                    Text(value(for: item)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .font(LeafyTypography.body)
                                .frame(minHeight: LeafyTheme.rowMinHeight)
                                if item.id != items.last?.id { Divider().overlay(LeafyTheme.hairline) }
                            }
                        }
                        .padding(.top, LeafySpacing.small)
                    } label: {
                        HStack {
                            Text(group.title).font(LeafyTypography.headline)
                            Spacer()
                            Text("\(items.count)").font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: LeafyTheme.minimumTouchTarget)
                    }
                    .tint(LeafyTheme.green)
                }
            }
        }
    }

    private var groups: [NutritionGroup] { NutritionGroup.detailOrder }
    private func amount(for code: String) -> NutrientAmountInput? { nutrients.first { $0.code == code } }
    private func value(for item: NutrientCatalog.Item) -> String {
        guard let amount = amount(for: item.code) else { return "Not available" }
        return "\(amount.amount.formatted(.number.precision(.fractionLength(0...2)))) \(item.unit)"
    }
    private func binding(for group: NutritionGroup) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(group) },
            set: { expanded in
                withAnimation(LeafyMotion.state) {
                    if expanded { expandedGroups.insert(group) } else { expandedGroups.remove(group) }
                }
            }
        )
    }
}

private struct LimitedFoodNutritionView: View {
    @Environment(AppModel.self) private var app
    let entry: FoodEntry
    @State private var nutrients: [NutrientAmountInput] = []
    @State private var servingScale = 1.0
    @State private var showingImpact = false
    @State private var showingDetails = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                ServingNutritionHero(
                    name: entry.name,
                    subtitle: entry.portionDescription ?? "Logged serving",
                    calories: entry.calories,
                    nutrients: nutrients
                )

                if app.configuration.isFoodImpactEnabled {
                    DisclosureGroup("Food impact", isExpanded: $showingImpact) {
                        FoodImpactDashboard(
                            input: impactInput,
                            servingScale: $servingScale,
                            servingDescription: { scale in
                                if let grams = entry.gramWeight {
                                    return "\((grams * scale).formatted(.number.precision(.fractionLength(0...1)))) g"
                                }
                                return "\(scale.formatted(.number.precision(.fractionLength(0...2))))× logged serving"
                            },
                            showsHeader: false
                        )
                        .padding(.top, LeafySpacing.small)
                    }
                    .font(LeafyTypography.title3)
                    .tint(LeafyTheme.green)
                }

                NutritionValueDisclosure(title: "Nutrition", nutrients: nutrients)

                DisclosureGroup("Logged details", isExpanded: $showingDetails) {
                    VStack(spacing: 0) {
                        detailRow("Meal", entry.mealType.label)
                        detailRow("Time", entry.consumedAt.formatted(date: .omitted, time: .shortened))
                        detailRow("Source", sourceLabel)
                    }
                    .padding(.top, LeafySpacing.small)
                }
                .font(LeafyTypography.headline)
                .tint(LeafyTheme.green)

                Text("Only information saved with this log is shown. Leafy does not guess missing nutrients or attach an unverified product.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.vertical, LeafySpacing.medium)
            .padding(.bottom, LeafySpacing.xxLarge)
        }
        .background(LeafyTheme.canvas)
        .navigationTitle("Food details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("limitedFoodNutritionView")
        .task(id: entry.id) { nutrients = await app.loadNutrients(for: entry) }
    }

    private var sourceLabel: String { entry.isAIEstimate ? "AI-assisted estimate" : "Manual entry" }
    private var impactInput: FoodImpactInput {
        let confidences = nutrients.compactMap(\.confidence)
        let confidence = entry.confidence ?? (confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count))
        return FoodImpactInput(
            name: entry.name,
            baseCalories: Double(entry.calories),
            nutrients: nutrients,
            provenance: sourceLabel,
            confidence: confidence,
            context: .logged
        )
    }
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
            .font(LeafyTypography.body)
            .frame(minHeight: LeafyTheme.rowMinHeight)
            .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
    }
}
