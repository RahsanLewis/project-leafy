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
                    NavigationLink("View Logged Details") {
                        LimitedFoodNutritionView(entry: entry)
                    }
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

private struct LimitedFoodNutritionView: View {
    @Environment(AppModel.self) private var app
    let entry: FoodEntry
    @State private var nutrients: [NutrientAmountInput] = []

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    ScoreBadge(score: nil, label: nil)
                        .scaleEffect(1.7)
                        .padding(.vertical, 22)
                    Text("Nutrition data incomplete")
                        .font(LeafyTypography.title2)
                    Text("No verified product profile is linked")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .leafyBorderlessRows(separators: false)

            Section("Logged serving") {
                LabeledContent("Calories", value: "\(entry.calories.formatted()) Cal")
                if let portion = entry.portionDescription {
                    LabeledContent("Amount", value: portion)
                }
                LabeledContent("Meal", value: entry.mealType.label)
                LabeledContent("Time", value: entry.consumedAt.formatted(date: .omitted, time: .shortened))
                LabeledContent("Source", value: sourceLabel)
            }
            .leafyBorderlessRows()

            Section("Nutrition") {
                ForEach(NutrientCatalog.items) { item in
                    nutrientRow(item)
                }
            }
            .leafyBorderlessRows()

            Section {
                Text("Only information saved with this log is shown. Leafy will not guess missing nutrients or attach an unverified catalog product.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .leafyBorderlessRows(separators: false)
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.large)
        .navigationTitle(entry.name.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("limitedFoodNutritionView")
        .task(id: entry.id) { nutrients = await app.loadNutrients(for: entry) }
    }

    private var sourceLabel: String {
        entry.isAIEstimate ? "AI-assisted estimate" : "Manual entry"
    }

    private func nutrientRow(_ item: NutrientCatalog.Item) -> some View {
        let value = nutrients.first { $0.code == item.code }
        return LabeledContent {
            if let value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(value.amount.formatted(.number.precision(.fractionLength(0...2)))) \(item.unit)")
                    if value.derivationMethod == .estimated {
                        Text("Estimated").font(LeafyTypography.caption).foregroundStyle(.secondary)
                    }
                }
            } else { Text("Not available").foregroundStyle(.secondary) }
        } label: { Text(item.name) }
    }
}
