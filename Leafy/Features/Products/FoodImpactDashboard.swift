import SwiftUI

struct FoodImpactDashboard: View {
    @Environment(AppCoordinator.self) private var app
    let input: FoodImpactInput
    @Binding var servingScale: Double
    let servingDescription: (Double) -> String
    var showsHeader = true

    private var summary: FoodImpactSummary {
        FoodImpactCalculator.calculate(
            input: input,
            scale: servingScale,
            dailyNutrition: app.dailyNutrition,
            calorieBudget: app.dailyPlan?.calorieTargetKcal,
            proteinTarget: app.dailyPlan.map { Double($0.proteinG) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            if showsHeader { header }
            carbohydrateImpact
            Divider()
            dailyFit
            if !summary.strengths.isEmpty || !summary.tradeoffs.isEmpty {
                Divider()
                standouts
            }
            Divider()
            servingSimulator
            methodology
        }
        .padding(.vertical, LeafySpacing.small)
        .accessibilityIdentifier("foodImpactDashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text("Food impact")
                .font(LeafyTypography.title2)
            Text(input.context == .logged ? "How this serving contributed to your day" : "How this serving may fit your day")
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var carbohydrateImpact: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carbohydrate impact")
                        .font(LeafyTypography.headline)
                    Text("Relative estimate—not blood glucose")
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(summary.carbohydrateImpact.rawValue)
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(summary.carbohydrateImpact == .higher ? .orange : LeafyTheme.green)
            }

            CarbImpactCurve(impact: summary.carbohydrateImpact)
                .frame(height: 116)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Relative carbohydrate impact: \(summary.carbohydrateImpact.rawValue)")

            HStack {
                if let carbs = summary.availableCarbohydrate {
                    Text("About \(format(carbs)) g available carbohydrate")
                } else {
                    Text("Carbohydrate data is unavailable")
                }
                Spacer()
                if let protein = summary.protein, protein >= 10 {
                    Label("Protein present", systemImage: "checkmark")
                } else if let fiber = summary.fiber, fiber >= 3 {
                    Label("Fiber present", systemImage: "checkmark")
                }
            }
            .font(LeafyTypography.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var dailyFit: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            Text(input.context == .logged ? "Contribution today" : "How it fits today")
                .font(LeafyTypography.headline)
            HStack(alignment: .top, spacing: LeafySpacing.compact) {
                metric("Calories", value: "\(summary.calories)", unit: "Cal")
                metric(
                    input.context == .logged ? "Day remaining" : "After serving",
                    value: summary.projectedCaloriesRemaining.map { String($0) } ?? "—",
                    unit: "Cal"
                )
                metric(
                    "Protein",
                    value: summary.protein.map(format) ?? "—",
                    unit: summary.protein.map { "g" + targetSuffix(amount: $0, target: summary.proteinTarget) } ?? "g"
                )
            }
            if let fiber = summary.fiber {
                Text("Adds \(format(fiber)) g fiber" + targetSuffix(amount: fiber, target: summary.fiberTarget))
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var standouts: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            Text("What stands out")
                .font(LeafyTypography.headline)
            ForEach(summary.strengths) { callout in
                calloutRow(callout, symbol: "plus", color: LeafyTheme.green)
            }
            ForEach(summary.tradeoffs) { callout in
                calloutRow(callout, symbol: "exclamationmark", color: .orange)
            }
        }
    }

    private var servingSimulator: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            HStack {
                Text(input.context == .logged ? "What-if serving" : "Serving")
                    .font(LeafyTypography.headline)
                Spacer()
                Text(servingDescription(servingScale))
                    .font(LeafyTypography.subheadlineSemibold)
            }
            Slider(value: $servingScale, in: 0.25...3, step: 0.25)
                .tint(LeafyTheme.green)
                .accessibilityLabel("Serving amount")
                .accessibilityValue(servingDescription(servingScale))
            HStack {
                Text("¼×")
                Spacer()
                Text("1×")
                Spacer()
                Text("3×")
            }
            .font(LeafyTypography.caption)
            .foregroundStyle(.secondary)
            if input.context == .logged && servingScale != 1 {
                Text("This preview does not change your saved food log.")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var methodology: some View {
        DisclosureGroup("How Leafy estimated this") {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("Leafy uses serving-adjusted carbohydrate minus fiber to show relative carbohydrate load. Protein and fiber are context, not a predicted change in blood glucose.")
                Text("Source: \(input.provenance) · Method: \(FoodImpactSummary.algorithmVersion)")
                if !summary.hasCompleteCoreNutrition {
                    Text("Core nutrition coverage: \(summary.knownCoreNutrientCount) of 4 values. Missing values reduce what Leafy can explain.")
                        .foregroundStyle(.orange)
                }
                if let confidence = summary.confidence {
                    Text("Source confidence: \(confidence.formatted(.percent.precision(.fractionLength(0))))")
                }
                Text("General wellness estimate—not a prediction of your blood sugar or medical advice.")
            }
            .font(LeafyTypography.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, LeafySpacing.small)
        }
        .font(LeafyTypography.subheadlineSemibold)
        .tint(LeafyTheme.green)
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(LeafyTypography.caption).foregroundStyle(.secondary)
            Text(value).font(LeafyTypography.title3)
            Text(unit).font(LeafyTypography.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calloutRow(_ callout: FoodImpactCallout, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: LeafySpacing.compact) {
            Image(systemName: symbol)
                .font(LeafyTypography.icon(13))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(callout.title).font(LeafyTypography.subheadlineSemibold)
                Text(callout.detail).font(LeafyTypography.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func targetSuffix(amount: Double, target: Double?) -> String {
        guard let target, target > 0 else { return "" }
        return " · \((amount / target).formatted(.percent.precision(.fractionLength(0)))) of target"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct CarbImpactCurve: View {
    let impact: CarbohydrateImpact

    private var amplitude: CGFloat {
        switch impact {
        case .lower: 0.30
        case .moderate: 0.55
        case .higher: 0.82
        case .unavailable: 0.12
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let baseline = size.height * 0.84
            let peak = baseline - size.height * amplitude
            let line = Path { path in
                path.move(to: CGPoint(x: 0, y: baseline))
                path.addCurve(
                    to: CGPoint(x: size.width, y: baseline),
                    control1: CGPoint(x: size.width * 0.25, y: peak),
                    control2: CGPoint(x: size.width * 0.48, y: peak)
                )
            }
            let band = Path { path in
                path.move(to: CGPoint(x: 0, y: baseline + 8))
                path.addCurve(
                    to: CGPoint(x: size.width, y: baseline + 8),
                    control1: CGPoint(x: size.width * 0.25, y: peak + 11),
                    control2: CGPoint(x: size.width * 0.48, y: peak + 11)
                )
                path.addLine(to: CGPoint(x: size.width, y: baseline - 8))
                path.addCurve(
                    to: CGPoint(x: 0, y: baseline - 8),
                    control1: CGPoint(x: size.width * 0.48, y: peak - 11),
                    control2: CGPoint(x: size.width * 0.25, y: peak - 11)
                )
                path.closeSubpath()
            }
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: baseline))
                    path.addLine(to: CGPoint(x: size.width, y: baseline))
                }
                .stroke(LeafyTheme.hairline, style: .init(lineWidth: 1, dash: [4, 5]))
                band.fill(LeafyTheme.green.opacity(0.10))
                line.stroke(LeafyTheme.green, style: .init(lineWidth: 3, lineCap: .round))
            }
        }
    }
}
