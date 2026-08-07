import SwiftUI

struct DailyNutritionView: View {
    @Environment(AppModel.self) private var app
    @State private var isChangingDay = false

    var body: some View {
        List {
            Section {
                nutritionDateNavigator
                if let summary = app.dailyNutrition {
                    MacroNutritionSummary(summary: summary, plan: app.dailyPlan, showsDisclosure: false)
                    coverageNotice(summary)
                } else if app.isDailyLoading {
                    HStack { Spacer(); ProgressView("Loading nutrition…"); Spacer() }
                        .padding(.vertical, LeafySpacing.xLarge)
                } else {
                    ContentUnavailableView(
                        "Nutrition unavailable",
                        systemImage: "chart.pie",
                        description: Text("Log food with nutrient information to see your daily totals.")
                    )
                }
            }
            .leafyBorderlessRows(separators: false)

            if let summary = app.dailyNutrition {
                nutrientSection("Build toward", nutrients: summary.nutrients.filter {
                    $0.targetKind == .goal && !DailyNutritionSummary.macroCodes.contains($0.code)
                })
                nutrientSection("Keep within", nutrients: summary.nutrients.filter { $0.targetKind == .limit })
                nutrientSection("Additional", nutrients: summary.nutrients.filter { $0.targetKind == .informational })

                Section {
                    Link(destination: summary.reference.sourceURL) {
                        Label("Targets use \(summary.reference.name)", systemImage: "arrow.up.right.square")
                    }
                    Text("General wellness guidance for \(summary.reference.population.lowercased()). Known totals may be incomplete when foods lack nutrient data.")
                        .font(LeafyTypography.footnote)
                        .foregroundStyle(.secondary)
                }
                .leafyBorderlessRows(separators: false)
            }
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.large)
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.loadDailyLog() }
        .accessibilityIdentifier("dailyNutritionView")
    }

    private var nutritionDateNavigator: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled(isChangingDay)
                .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 2) {
                Text(app.isViewingToday ? "Today" : app.selectedLogDate.formatted(.dateTime.weekday(.wide)))
                    .font(LeafyTypography.title2)
                Text(app.selectedLogDate.formatted(date: .abbreviated, time: .omitted))
                    .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(app.isViewingToday || isChangingDay)
                .accessibilityLabel("Next day")
        }
        .tint(LeafyTheme.green)
    }

    @ViewBuilder private func coverageNotice(_ summary: DailyNutritionSummary) -> some View {
        if let coverage = summary.macroCoverage, coverage < 0.999 {
            Label(
                "Macro data covers \(coverage.formatted(.percent.precision(.fractionLength(0)))) of logged calories",
                systemImage: "chart.bar.doc.horizontal"
            )
            .font(LeafyTypography.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, LeafySpacing.small)
            .accessibilityIdentifier("nutritionCoverageNotice")
        }
    }

    @ViewBuilder private func nutrientSection(_ title: String, nutrients: [DailyNutrient]) -> some View {
        let visible = nutrients.sorted { $0.displayOrder < $1.displayOrder }
        if !visible.isEmpty {
            Section(title) {
                ForEach(visible) { NutrientProgressRow(nutrient: $0) }
            }
            .leafyBorderlessRows()
        }
    }

    private func move(_ days: Int) {
        guard !isChangingDay else { return }
        isChangingDay = true
        Task {
            _ = await app.moveLogDate(by: days)
            isChangingDay = false
        }
    }
}

struct MacroNutritionSummary: View {
    let summary: DailyNutritionSummary
    let plan: NutritionPlan?
    let showsDisclosure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            HStack {
                Text("Nutrition").font(LeafyTypography.title3)
                Spacer()
                if showsDisclosure {
                    HStack(spacing: 4) {
                        Text("View all")
                        Image(systemName: "chevron.right").font(LeafyTypography.captionSemibold)
                    }
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                }
            }
            HStack(alignment: .top, spacing: LeafySpacing.medium) {
                MacroMiniRing(title: "Protein", nutrient: summary.nutrient("protein_g"), target: plan.map { Double($0.proteinG) })
                MacroMiniRing(title: "Carbs", nutrient: summary.nutrient("carbohydrate_g"), target: plan.map { Double($0.carbohydrateG) })
                MacroMiniRing(title: "Fat", nutrient: summary.nutrient("fat_g"), target: plan.map { Double($0.fatG) })
            }
            if let coverage = summary.macroCoverage, coverage < 0.999 {
                Text("Some foods are missing macro data · \(coverage.formatted(.percent.precision(.fractionLength(0)))) covered")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, LeafyTheme.pageInset)
        .padding(.vertical, LeafySpacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeMacroSummary")
    }
}

private struct MacroMiniRing: View {
    let title: String
    let nutrient: DailyNutrient?
    let target: Double?

    var body: some View {
        VStack(spacing: LeafySpacing.small) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(LeafyTheme.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(amountText)
                    .font(LeafyTypography.headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 82, height: 82)
            Text(title).font(LeafyTypography.subheadlineSemibold)
            Text(target.map { "of \(format($0)) g" } ?? "No target")
                .font(LeafyTypography.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(amountText), target \(target.map { format($0) } ?? "unavailable") grams")
    }

    private var amountText: String { "\(format(nutrient?.amount ?? 0))g" }
    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(max((nutrient?.amount ?? 0) / target, 0), 1)
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

private struct NutrientProgressRow: View {
    let nutrient: DailyNutrient
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(nutrient.name).font(LeafyTypography.headline)
                Button { showingInfo = true } label: {
                    Image(systemName: "info.circle").frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("About \(nutrient.name)")
                Spacer()
                Text(amountAndTarget).font(LeafyTypography.subheadlineSemibold).monospacedDigit()
            }
            if nutrient.targetAmount != nil {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        Capsule().fill(barColor).frame(width: proxy.size.width * nutrient.progress)
                    }
                }
                .frame(height: 6)
            }
            HStack {
                if let signal { Text(signal).foregroundStyle(signalColor) }
                Spacer()
                if let coverage = nutrient.coverage, coverage < 0.999 {
                    Text("\(coverage.formatted(.percent.precision(.fractionLength(0)))) covered")
                }
            }
            .font(LeafyTypography.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, LeafySpacing.xSmall)
        .popover(isPresented: $showingInfo) {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text(nutrient.name).font(LeafyTypography.headline)
                Text(infoText).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                if nutrient.hasEstimate {
                    Text("Includes \(format(nutrient.estimatedAmount)) \(nutrient.unit) estimated by AI.")
                        .font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
            }
            .padding().frame(width: 290)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var amountAndTarget: String {
        let amount = "\(format(nutrient.amount)) \(nutrient.unit)"
        guard let target = nutrient.targetAmount else { return amount }
        return "\(amount) / \(format(target))"
    }
    private var signal: String? {
        guard let percent = nutrient.percentOfTarget else { return nil }
        if nutrient.targetKind == .limit {
            if percent >= 1 { return "Above daily limit" }
            if percent >= 0.8 { return "Near daily limit" }
            return nil
        }
        guard nutrient.hasSufficientCoverage else { return nil }
        if percent >= 1 { return "Daily value reached" }
        if percent < 0.5 { return "Low so far" }
        return nil
    }
    private var signalColor: Color { nutrient.targetKind == .limit ? .orange : LeafyTheme.green }
    private var barColor: Color { nutrient.targetKind == .limit && (nutrient.percentOfTarget ?? 0) >= 0.8 ? .orange : LeafyTheme.green }
    private var infoText: String {
        let coverage = nutrient.coverage?.formatted(.percent.precision(.fractionLength(0))) ?? "not available"
        let target = nutrient.targetKind == .limit ? "a general daily limit" : "a general Daily Value"
        return "Leafy shows known intake against \(target). Data for this nutrient covers \(coverage) of today’s logged calories."
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}
