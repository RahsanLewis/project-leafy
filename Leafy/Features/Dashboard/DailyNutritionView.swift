import SwiftUI

enum NutritionPresentation {
    static let groupOrder = NutritionGroup.dailyOrder

    static func group(for nutrient: DailyNutrient) -> NutritionGroup {
        if nutrient.targetKind == .limit,
           ["fat", "carbohydrate", "other"].contains(nutrient.nutrientClass.lowercased()) {
            return .limits
        }
        switch nutrient.nutrientClass.lowercased() {
        case "vitamin": return .vitamins
        case "mineral": return .minerals
        case "amino_acid": return .essentialAminoAcids
        case "essential_fatty_acid": return .essentialFattyAcids
        case "fiber": return .fiber
        case "choline": return .choline
        default: return .other
        }
    }

    static func sorted(_ nutrients: [DailyNutrient], in group: NutritionGroup) -> [DailyNutrient] {
        nutrients.sorted { lhs, rhs in
            if group == .minerals {
                let lhsIsSodium = lhs.code == "sodium_mg"
                let rhsIsSodium = rhs.code == "sodium_mg"
                if lhsIsSodium != rhsIsSodium { return lhsIsSodium }
            }
            let lhsStatus = statusRank(lhs), rhsStatus = statusRank(rhs)
            if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }
            let lhsImportance = NutrientCatalog.importanceRank(for: lhs.code)
            let rhsImportance = NutrientCatalog.importanceRank(for: rhs.code)
            if lhsImportance != rhsImportance { return lhsImportance < rhsImportance }
            return lhs.displayOrder < rhs.displayOrder
        }
    }

    private static func statusRank(_ nutrient: DailyNutrient) -> Int {
        if nutrient.excessFlag == true { return 0 }
        if nutrient.belowTargetFlag == true { return 1 }
        guard let percent = nutrient.percentOfTarget else { return 5 }
        switch nutrient.targetKind {
        case .limit:
            if percent >= 1 { return 0 }
            if percent >= 0.8 { return 1 }
            return 4
        case .goal:
            if percent < 0.5 { return 2 }
            if percent < 0.9 { return 3 }
            return 4
        case .informational:
            return 5
        }
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

    private func allNutrients(_ summary: DailyNutritionSummary) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            if summary.isEnriching {
                Label("Estimating missing nutrient details…", systemImage: "sparkles")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(NutritionPresentation.groupOrder, id: \.self) { group in
                let nutrients = NutritionPresentation.sorted(summary.nutrients
                    .filter {
                        !DailyNutritionSummary.macroCodes.contains($0.code) &&
                        NutritionPresentation.group(for: $0) == group
                    }
                , in: group)
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
        .task(id: summary.nutrients.map(\.code)) {
            let hasUrgentOther = summary.nutrients.contains {
                NutritionPresentation.group(for: $0) == .other &&
                $0.targetKind == .limit && ($0.percentOfTarget ?? 0) >= 0.8
            }
            if hasUrgentOther { expandedGroups.insert(.other) }
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
                .foregroundStyle(status.color)
            GeometryReader { proxy in
                Capsule().fill(LeafyTheme.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(status.color).frame(width: proxy.size.width * progress)
                    }
            }
            .frame(height: 5)
            Text(status.label)
                .font(LeafyTypography.caption)
                .foregroundStyle(status.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(nutrient.map { format($0.amount) } ?? "not enough data") grams, target \(target.map(format) ?? "unavailable") grams")
    }

    private var progress: Double {
        guard let target, target > 0, let nutrient else { return 0 }
        return min(max(nutrient.amount / target, 0), 1)
    }
    private var status: (label: String, color: Color) {
        guard let target, target > 0, let nutrient else { return ("No target", .secondary) }
        let ratio = nutrient.amount / target
        let upper = title == "Protein" ? 1.25 : 1.10
        if ratio < 0.90 { return ("\(format(max(0, target - nutrient.amount))) g to target", LeafyTheme.green) }
        if ratio <= upper { return ("On target", LeafyTheme.green) }
        return ("\(format(nutrient.amount - target)) g above target", .orange)
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
            if let statusText {
                Text(statusText).font(LeafyTypography.caption).foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, LeafySpacing.small)
    }

    private var hasKnownData: Bool { nutrient.coverage == nil || (nutrient.coverage ?? 0) > 0 }
    private var amountAndTarget: String {
        guard hasKnownData else { return "Estimating…" }
        let estimateMark = nutrient.hasEstimate ? "≈" : ""
        let amount = "\(estimateMark)\(format(nutrient.amount)) \(nutrient.unit)"
        guard let target = nutrient.targetAmount else { return amount }
        if nutrient.targetBasisCodes.count > 1, let basis = nutrient.targetBasisAmount {
            return "\(amount) · pair \(format(basis)) of \(format(target))"
        }
        return "\(amount) of \(format(target))"
    }
    private var barColor: Color {
        if nutrient.excessFlag == true { return .red }
        if nutrient.belowTargetFlag == true { return .orange }
        return nutrient.targetKind == .limit && (nutrient.percentOfTarget ?? 0) >= 0.8 ? .orange : LeafyTheme.green
    }
    private var statusText: String? {
        guard hasKnownData else { return nil }
        if nutrient.excessFlag == true { return "Above the 7-day upper limit" }
        if nutrient.belowTargetFlag == true { return "Below the 7-day target" }
        if nutrient.belowTargetFlag == false { return "7-day target met" }
        if nutrient.targetAmount != nil && nutrient.trendQualifyingDays < nutrient.trendRequiredDays {
            return "Need \(nutrient.trendRequiredDays - nutrient.trendQualifyingDays) more covered day\(nutrient.trendRequiredDays - nutrient.trendQualifyingDays == 1 ? "" : "s")"
        }
        guard let target = nutrient.targetAmount else { return nil }
        let difference = target - nutrient.amount
        if nutrient.targetKind == .limit {
            if difference < 0 { return "\(format(abs(difference))) \(nutrient.unit) over limit" }
            if (nutrient.percentOfTarget ?? 0) >= 0.8 { return "Near limit · \(format(difference)) \(nutrient.unit) remaining" }
            return nil
        }
        return nil
    }
    private var statusColor: Color {
        if nutrient.excessFlag == true { return .red }
        if nutrient.belowTargetFlag == true { return .orange }
        return nutrient.targetKind == .limit ? .orange : .secondary
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
            if let education = MicronutrientEducationCatalog.education(for: nutrient.code) {
                educationSection("What it supports", education.healthRole)
                educationSection("Common food sources", education.foodSources.joined(separator: ", "))
            }
            LabeledContent("Logged amount", value: "\(format(nutrient.amount)) \(nutrient.unit)")
                .accessibilityIdentifier("nutrientLoggedAmount")
            if let target = nutrient.targetAmount {
                LabeledContent(targetLabel, value: "\(format(target)) \(nutrient.unit)")
                LabeledContent("Daily target", value: nutrient.percentOfTarget?.formatted(.percent.precision(.fractionLength(0))) ?? "Unavailable")
            } else {
                LabeledContent("Recommended amount", value: "No established target")
            }
            LabeledContent("Upper limit", value: upperLimitText)
                .accessibilityIdentifier("nutrientUpperLimit")
            LabeledContent("7-day status", value: trendStatus)
                .accessibilityIdentifier("nutrientSevenDayStatus")
            LabeledContent("Data coverage", value: nutrient.coverage?.formatted(.percent.precision(.fractionLength(0))) ?? "Unavailable")
                .accessibilityIdentifier("nutrientDataCoverage")
            if nutrient.hasEstimate {
                LabeledContent("Estimated", value: "\(format(nutrient.estimatedAmount)) \(nutrient.unit)")
            }
            if let note = nutrient.referenceNote {
                educationSection("How this target works", note)
            }
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("Your logged sources").font(LeafyTypography.headline)
                if nutrient.foodSources.isEmpty {
                    Text("No contributing foods with known data.")
                        .font(LeafyTypography.body).foregroundStyle(.secondary)
                } else {
                    ForEach(nutrient.foodSources) { source in
                        HStack(alignment: .firstTextBaseline) {
                            Text(source.name).font(LeafyTypography.body)
                            Spacer()
                            Text("\(format(source.amount)) \(nutrient.unit)")
                                .font(LeafyTypography.subheadlineSemibold).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func educationSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text(title)
                .font(LeafyTypography.headline)
            Text(text)
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var targetExplanation: String {
        switch nutrient.targetKind {
        case .goal: "The amount and percentage describe this day. Low and high status use up to seven days and are general guidance—not a diagnosis."
        case .limit: "Leafy shows your known intake against a general daily limit so you can keep the amount in context."
        case .informational: "Leafy tracks this nutrient for context even though it does not have a daily target here."
        }
    }
    private var targetLabel: String {
        switch nutrient.targetType {
        case "rda": "Recommended amount (RDA)"
        case "ai": "Recommended amount (AI)"
        case "weight_based_rda": "Weight-based RDA"
        case "legacy_ai": "Historical AI"
        default: "Recommended amount"
        }
    }
    private var upperLimitText: String {
        guard let upper = nutrient.upperLimitAmount else { return "No established upper limit" }
        let amount = "\(format(upper)) \(nutrient.unit)"
        switch nutrient.upperLimitScope {
        case .preformedOnly: return amount + " · preformed only"
        case .syntheticOnly: return amount + " · synthetic only"
        case .supplementalOnly: return amount + " · supplements only"
        default: return amount
        }
    }
    private var trendStatus: String {
        if nutrient.excessFlag == true { return "Above upper limit" }
        if nutrient.belowTargetFlag == true { return "Below target" }
        if nutrient.belowTargetFlag == false { return "Target met" }
        if nutrient.targetAmount == nil { return "Not assessable" }
        return "Need \(max(0, nutrient.trendRequiredDays - nutrient.trendQualifyingDays)) more covered days"
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}
