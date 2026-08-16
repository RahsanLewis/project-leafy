import SwiftUI

enum NutritionPresentation {
    static let groupOrder = NutritionGroup.dailyOrder

    static func group(for nutrient: DailyNutrient) -> NutritionGroup {
        if nutrient.targetKind == .limit { return .limits }
        if nutrient.targetKind == .informational { return .other }
        switch nutrient.nutrientClass.lowercased() {
        case "vitamin": return .vitamins
        case "mineral": return .minerals
        default: return .fiberAndCholine
        }
    }

    static func focusNutrients(from nutrients: [DailyNutrient]) -> [DailyNutrient] {
        nutrients
            .filter {
                $0.targetKind == .goal &&
                !DailyNutritionSummary.macroCodes.contains($0.code) &&
                $0.targetAmount != nil && $0.hasSufficientCoverage
            }
            .sorted {
                let lhs = $0.percentOfTarget ?? .greatestFiniteMagnitude
                let rhs = $1.percentOfTarget ?? .greatestFiniteMagnitude
                return lhs == rhs ? $0.displayOrder < $1.displayOrder : lhs < rhs
            }
            .prefix(3)
            .map { $0 }
    }

    static func limitNutrients(from nutrients: [DailyNutrient]) -> [DailyNutrient] {
        nutrients
            .filter {
                $0.targetKind == .limit && $0.hasSufficientCoverage &&
                ($0.percentOfTarget ?? 0) >= 0.8
            }
            .sorted { ($0.percentOfTarget ?? 0) > ($1.percentOfTarget ?? 0) }
    }
}

struct DailyNutritionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isChangingDay = false
    @State private var expandedGroups: Set<NutritionGroup> = []
    @State private var selectedNutrient: DailyNutrient?
    @State private var showingTargets = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                nutritionDateNavigator

                if let summary = app.dailyNutrition {
                    MacroNutritionSummary(summary: summary, plan: app.dailyPlan, showsDisclosure: false)
                    coverageNotice(summary)
                    focusContent(summary)
                    allNutrients(summary)
                    aboutTargets(summary)
                } else if app.isDailyLoading {
                    ProgressView("Loading nutrition…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LeafySpacing.xxLarge)
                } else {
                    ContentUnavailableView(
                        "Nutrition unavailable",
                        systemImage: "chart.pie",
                        description: Text("Log food with nutrient information to see your daily totals.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LeafySpacing.xLarge)
                }
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.top, LeafySpacing.small)
            .padding(.bottom, LeafySpacing.xxLarge)
        }
        .background(LeafyTheme.canvas)
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.loadDailyLog() }
        .sheet(item: $selectedNutrient) { nutrient in
            NutrientExplanationSheet(nutrient: nutrient)
        }
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
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
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
                "Nutrition data covers \(coverage.formatted(.percent.precision(.fractionLength(0)))) of logged calories",
                systemImage: "chart.bar.doc.horizontal"
            )
            .font(LeafyTypography.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("nutritionCoverageNotice")
        }
    }

    @ViewBuilder private func focusContent(_ summary: DailyNutritionSummary) -> some View {
        let goals = NutritionPresentation.focusNutrients(from: summary.nutrients)
        let limits = NutritionPresentation.limitNutrients(from: summary.nutrients)
        if !goals.isEmpty {
            nutrientCollection(title: "Nutrients to focus on", subtitle: "Useful progress to keep in view today", nutrients: goals)
        }
        if !limits.isEmpty {
            nutrientCollection(title: "Approaching daily limits", subtitle: "Nutrients nearing a general daily limit", nutrients: limits)
        }
    }

    private func nutrientCollection(title: String, subtitle: String, nutrients: [DailyNutrient]) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                Text(title).font(LeafyTypography.title3)
                Text(subtitle).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            }
            ForEach(nutrients) { nutrient in
                NutrientProgressRow(nutrient: nutrient) { selectedNutrient = nutrient }
            }
        }
    }

    private func allNutrients(_ summary: DailyNutritionSummary) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            Text("All nutrients").font(LeafyTypography.title3)
            ForEach(NutritionPresentation.groupOrder, id: \.self) { group in
                let nutrients = summary.nutrients
                    .filter { !DailyNutritionSummary.macroCodes.contains($0.code) && NutritionPresentation.group(for: $0) == group }
                    .sorted { $0.displayOrder < $1.displayOrder }
                if !nutrients.isEmpty {
                    nutrientDisclosure(group, nutrients: nutrients)
                }
            }
        }
    }

    private func nutrientDisclosure(_ group: NutritionGroup, nutrients: [DailyNutrient]) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedGroups.contains(group) },
            set: { expanded in
                withAnimation(reduceMotion ? nil : LeafyMotion.state) {
                    if expanded { expandedGroups.insert(group) } else { expandedGroups.remove(group) }
                }
            }
        )) {
            VStack(spacing: 0) {
                ForEach(nutrients) { nutrient in
                    NutrientProgressRow(nutrient: nutrient) { selectedNutrient = nutrient }
                    if nutrient.id != nutrients.last?.id { Divider().overlay(LeafyTheme.hairline) }
                }
            }
            .padding(.top, LeafySpacing.small)
        } label: {
            HStack {
                Text(group.title).font(LeafyTypography.headline)
                Spacer()
                Text("\(nutrients.count)").font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            }
            .frame(minHeight: LeafyTheme.minimumTouchTarget)
        }
        .tint(LeafyTheme.green)
    }

    private func aboutTargets(_ summary: DailyNutritionSummary) -> some View {
        DisclosureGroup("About these targets", isExpanded: $showingTargets) {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("General wellness guidance for \(summary.reference.population.lowercased()). Known totals may be incomplete when foods lack nutrient data.")
                Link("View \(summary.reference.name)", destination: summary.reference.sourceURL)
                    .foregroundStyle(LeafyTheme.green)
            }
            .font(LeafyTypography.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, LeafySpacing.small)
        }
        .font(LeafyTypography.subheadlineSemibold)
        .tint(LeafyTheme.green)
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
                Text("Macros").font(LeafyTypography.title3)
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
                MacroMetric(title: "Protein", nutrient: summary.nutrient("protein_g"), target: plan.map { Double($0.proteinG) })
                MacroMetric(title: "Carbs", nutrient: summary.nutrient("carbohydrate_g"), target: plan.map { Double($0.carbohydrateG) })
                MacroMetric(title: "Fat", nutrient: summary.nutrient("fat_g"), target: plan.map { Double($0.fatG) })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeMacroSummary")
    }
}

private struct MacroMetric: View {
    let title: String
    let nutrient: DailyNutrient?
    let target: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(title).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            Text(nutrient.map { "\(format($0.amount))g" } ?? "—")
                .font(LeafyTypography.metric(26))
                .monospacedDigit()
                .contentTransition(.numericText())
            GeometryReader { proxy in
                Capsule().fill(LeafyTheme.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(LeafyTheme.green).frame(width: proxy.size.width * progress)
                    }
            }
            .frame(height: 5)
            Text(target.map { "of \(format($0)) g" } ?? "No target")
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(nutrient.map { format($0.amount) } ?? "not enough data") grams, target \(target.map(format) ?? "unavailable") grams")
    }

    private var progress: Double {
        guard let target, target > 0, let nutrient else { return 0 }
        return min(max(nutrient.amount / target, 0), 1)
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

private struct NutrientProgressRow: View {
    let nutrient: DailyNutrient
    let onInfo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(nutrient.name).font(LeafyTypography.bodyMedium)
                Button(action: onInfo) {
                    Image(systemName: "info.circle").frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("About \(nutrient.name)")
                Spacer()
                Text(amountAndTarget).font(LeafyTypography.subheadlineSemibold).monospacedDigit()
            }
            if nutrient.targetAmount != nil && hasKnownData {
                GeometryReader { proxy in
                    Capsule().fill(LeafyTheme.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(barColor).frame(width: proxy.size.width * nutrient.progress)
                        }
                }
                .frame(height: 5)
            }
            if !hasKnownData {
                Text("Not enough data").font(LeafyTypography.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, LeafySpacing.small)
    }

    private var hasKnownData: Bool { nutrient.coverage == nil || (nutrient.coverage ?? 0) > 0 }
    private var amountAndTarget: String {
        guard hasKnownData else { return "—" }
        let amount = "\(format(nutrient.amount)) \(nutrient.unit)"
        guard let target = nutrient.targetAmount else { return amount }
        return "\(amount) of \(format(target))"
    }
    private var barColor: Color {
        nutrient.targetKind == .limit && (nutrient.percentOfTarget ?? 0) >= 0.8 ? .orange : LeafyTheme.green
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}

private struct NutrientExplanationSheet: View {
    let nutrient: DailyNutrient

    var body: some View {
        LeafyInfoSheet(
            title: nutrient.name,
            dismissIdentifier: "dismissNutrientExplanation"
        ) {
            Text(targetExplanation)
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Logged amount", value: "\(format(nutrient.amount)) \(nutrient.unit)")
            LabeledContent("Data coverage", value: nutrient.coverage?.formatted(.percent.precision(.fractionLength(0))) ?? "Unavailable")
            if nutrient.hasEstimate {
                LabeledContent("Estimated", value: "\(format(nutrient.estimatedAmount)) \(nutrient.unit)")
            }
        }
    }

    private var targetExplanation: String {
        switch nutrient.targetKind {
        case .goal: "Leafy shows your known intake against a general Daily Value. Progress during a single day is not a diagnosis or a sign of deficiency."
        case .limit: "Leafy shows your known intake against a general daily limit so you can keep the amount in context."
        case .informational: "Leafy tracks this nutrient for context even though it does not have a daily target here."
        }
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}
