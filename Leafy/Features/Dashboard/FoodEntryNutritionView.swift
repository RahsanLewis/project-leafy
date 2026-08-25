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
    var showsCalories = true
    var showsMacros = true

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                Text(name.capitalized).font(LeafyTypography.title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                }
            }
            if showsCalories {
                HStack(alignment: .firstTextBaseline, spacing: LeafySpacing.small) {
                    Text(calories.formatted()).font(LeafyTypography.metric(52, extraBold: true)).monospacedDigit()
                    Text("Cal").font(LeafyTypography.title3).foregroundStyle(.secondary)
                }
            }
            if showsMacros {
                HStack(alignment: .top, spacing: LeafySpacing.large) {
                    macro("Protein", code: "protein_g")
                    macro("Carbs", code: "carbohydrate_g")
                    macro("Fat", code: "fat_g")
                }
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

enum LeafyScoreBand: Equatable {
    case red, orange, yellow, green, blue

    init(score: Int) {
        switch score {
        case ..<25: self = .red
        case 25..<50: self = .orange
        case 50..<70: self = .yellow
        case 70..<90: self = .green
        default: self = .blue
        }
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: Color(red: 0.72, green: 0.56, blue: 0.02)
        case .green: LeafyTheme.green
        case .blue: .blue
        }
    }
}

struct ProvisionalScoreBadge: View {
    let score: ProductNutritionScore
    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: LeafySpacing.xSmall) {
            Text("Provisional")
                .font(LeafyTypography.captionSemibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(LeafyTheme.track, in: Capsule())
            Button { showingDetails = true } label: {
                Image(systemName: "info.circle")
                    .font(LeafyTypography.icon(16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("About provisional score")
            .accessibilityIdentifier("provisionalScoreInfoButton")
        }
        .sheet(isPresented: $showingDetails) {
            LeafyInfoSheet(title: "Provisional Leafy Score", dismissIdentifier: "dismissProvisionalScoreInfo") {
                Text("This score uses the best information currently available and may change when Leafy receives more complete or verified nutrition data.")
                    .font(LeafyTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Confidence", value: score.confidenceLevel.capitalized)
                LabeledContent(
                    "Data coverage",
                    value: score.evidenceCoverage.formatted(.percent.precision(.fractionLength(0)))
                )
            }
        }
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
                let items = NutrientCatalog.items(in: group).filter { amount(for: $0.code) != nil }
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
    @State private var refreshedScore: ProductNutritionScore?
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

                if let score = refreshedScore ?? entry.score {
                    entryScore(score)
                }

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

                Text("Leafy keeps saved values separate from estimates. Provisional scores clearly reflect estimated or incomplete nutrition data.")
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
        .task(id: entry.id) {
            async let loadedNutrients = app.loadNutrients(for: entry)
            async let loadedScore = app.loadScore(for: entry)
            nutrients = await loadedNutrients
            refreshedScore = await loadedScore
        }
    }

    private var sourceLabel: String { entry.isAIEstimate ? "AI-assisted estimate" : "Manual entry" }
    private func entryScore(_ score: ProductNutritionScore) -> some View {
        let scoreColor = score.score.map { LeafyScoreBand(score: $0).color } ?? Color.secondary
        return VStack(alignment: .leading, spacing: LeafySpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leafy Score").font(LeafyTypography.title3)
                    Text(score.scoreStatus == "pending" ? "Calculating from nutrition data" : "Best available food quality")
                        .font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(score.score.map(String.init) ?? "—").font(LeafyTypography.metric(40)).foregroundStyle(scoreColor)
                if score.score != nil { Text("/100").font(LeafyTypography.subheadline).foregroundStyle(.secondary) }
            }
            HStack(spacing: LeafySpacing.small) {
                if let rating = score.rating {
                    Text(rating).font(LeafyTypography.headline).foregroundStyle(scoreColor)
                }
                if score.isProvisional { ProvisionalScoreBadge(score: score) }
            }
            scoreFactors("Strengths", score.strengths, color: LeafyTheme.green)
            scoreFactors("What lowered it", score.weaknesses, color: .orange)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("foodEntryLeafyScore")
    }
    @ViewBuilder private func scoreFactors(_ title: String, _ factors: [String], color: Color) -> some View {
        if !factors.isEmpty {
            VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                Text(title).font(LeafyTypography.subheadlineSemibold)
                ForEach(factors, id: \.self) { factor in
                    HStack(alignment: .top, spacing: LeafySpacing.xSmall) {
                        Circle().fill(color).frame(width: 5, height: 5).padding(.top, 7)
                        Text(factor).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
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
