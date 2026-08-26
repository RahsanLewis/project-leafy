import Foundation

enum FoodImpactContext: Equatable, Sendable {
    case prospective
    case logged
}

enum CarbohydrateImpact: String, Equatable, Sendable {
    case lower = "Lower"
    case moderate = "Moderate"
    case higher = "Higher"
    case unavailable = "Not available"
}

struct FoodImpactInput: Equatable, Sendable {
    let name: String
    let baseCalories: Double
    let nutrients: [NutrientAmountInput]
    let provenance: String
    let confidence: Double?
    let context: FoodImpactContext

    func nutrient(_ code: String, scale: Double = 1) -> Double? {
        nutrients.first(where: { $0.code == code }).map { $0.amount * scale }
    }
}

struct FoodImpactCallout: Identifiable, Equatable, Sendable {
    let code: String
    let title: String
    let detail: String
    var id: String { code }
}

struct FoodImpactSummary: Equatable, Sendable {
    static let algorithmVersion = "food-impact-v1"

    let carbohydrateImpact: CarbohydrateImpact
    let availableCarbohydrate: Double?
    let calories: Int
    let projectedCaloriesRemaining: Int?
    let protein: Double?
    let proteinTarget: Double?
    let fiber: Double?
    let fiberTarget: Double?
    let strengths: [FoodImpactCallout]
    let tradeoffs: [FoodImpactCallout]
    let confidence: Double?
    let knownCoreNutrientCount: Int

    var hasCompleteCoreNutrition: Bool { knownCoreNutrientCount == 4 }
}

enum FoodImpactCalculator {
    private static let coreCodes = ["carbohydrate_g", "fiber_g", "protein_g", "fat_g"]
    private static let excludedStrengthCodes = Set(["carbohydrate_g", "fat_g"])

    static func calculate(
        input: FoodImpactInput,
        scale: Double,
        dailyNutrition: DailyNutritionSummary?,
        calorieBudget: Int?,
        proteinTarget: Double? = nil
    ) -> FoodImpactSummary {
        let safeScale = min(max(scale, 0.25), 3)
        let calories = Int((input.baseCalories * safeScale).rounded())
        let carbs = input.nutrient("carbohydrate_g", scale: safeScale)
        let fiber = input.nutrient("fiber_g", scale: safeScale)
        let availableCarbs = carbs.map { max(0, $0 - (fiber ?? 0)) }
        let impact: CarbohydrateImpact = switch availableCarbs {
        case .none: .unavailable
        case .some(let value) where value < 15: .lower
        case .some(let value) where value <= 30: .moderate
        default: .higher
        }

        let dailyCalories = dailyNutrition?.totalCalories ?? 0
        let projectedCalories = input.context == .logged ? dailyCalories : dailyCalories + calories
        let remaining = calorieBudget.map { $0 - projectedCalories }
        let protein = input.nutrient("protein_g", scale: safeScale)
        let proteinTarget = proteinTarget ?? dailyNutrition?.nutrient("protein_g")?.targetAmount
        let fiberTarget = dailyNutrition?.nutrient("fiber_g")?.targetAmount

        let callouts = nutrientCallouts(input: input, scale: safeScale, dailyNutrition: dailyNutrition)
        let knownCoreCount = coreCodes.filter { input.nutrient($0) != nil }.count

        return FoodImpactSummary(
            carbohydrateImpact: impact,
            availableCarbohydrate: availableCarbs,
            calories: calories,
            projectedCaloriesRemaining: remaining,
            protein: protein,
            proteinTarget: proteinTarget,
            fiber: fiber,
            fiberTarget: fiberTarget,
            strengths: callouts.strengths,
            tradeoffs: callouts.tradeoffs,
            confidence: input.confidence,
            knownCoreNutrientCount: knownCoreCount
        )
    }

    private static func nutrientCallouts(
        input: FoodImpactInput,
        scale: Double,
        dailyNutrition: DailyNutritionSummary?
    ) -> (strengths: [FoodImpactCallout], tradeoffs: [FoodImpactCallout]) {
        guard let dailyNutrition else { return ([], []) }

        let candidates = dailyNutrition.nutrients.compactMap { reference -> (DailyNutrient, Double, Double)? in
            guard let target = reference.targetAmount, target > 0,
                  let amount = input.nutrient(reference.code, scale: scale) else { return nil }
            return (reference, amount, amount / target)
        }

        let strengths = candidates
            .filter { $0.0.targetKind == .goal && !excludedStrengthCodes.contains($0.0.code) && $0.2 >= 0.2 }
            .sorted { lhs, rhs in
                let lhsGap = max((lhs.0.targetAmount ?? 0) - lhs.0.amount, 0)
                let rhsGap = max((rhs.0.targetAmount ?? 0) - rhs.0.amount, 0)
                let lhsFit = min(lhs.1, lhsGap) / max(lhs.0.targetAmount ?? 1, 1)
                let rhsFit = min(rhs.1, rhsGap) / max(rhs.0.targetAmount ?? 1, 1)
                return lhsFit == rhsFit ? lhs.2 > rhs.2 : lhsFit > rhsFit
            }
            .prefix(2)
            .map { reference, _, percent in
                FoodImpactCallout(
                    code: reference.code,
                    title: "High in \(reference.name.lowercased())",
                    detail: "\(percent.formatted(.percent.precision(.fractionLength(0)))) of the general Daily Value"
                )
            }

        let tradeoffs = candidates
            .filter { $0.0.targetKind == .limit && $0.2 >= 0.2 }
            .sorted { $0.2 > $1.2 }
            .prefix(2)
            .map { reference, amount, percent in
                let remaining = max((reference.targetAmount ?? 0) - reference.amount, 0)
                let remainingText = remaining > 0
                    ? "Uses \((amount / remaining).formatted(.percent.precision(.fractionLength(0)))) of today’s remaining allowance"
                    : "Today’s general limit has already been reached"
                return FoodImpactCallout(
                    code: reference.code,
                    title: "Notable \(reference.name.lowercased())",
                    detail: percent >= 0.2 ? remainingText : "\(percent.formatted(.percent.precision(.fractionLength(0)))) of the general Daily Value"
                )
            }

        return (Array(strengths), Array(tradeoffs))
    }
}
