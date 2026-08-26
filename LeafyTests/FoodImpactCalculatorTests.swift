import XCTest
@testable import Leafy

final class FoodImpactCalculatorTests: XCTestCase {
    func testCarbohydrateImpactUsesServingAdjustedAvailableCarbohydrate() {
        let input = food(
            calories: 240,
            nutrients: [
                .init(code: "carbohydrate_g", amount: 32),
                .init(code: "fiber_g", amount: 4),
                .init(code: "protein_g", amount: 8),
                .init(code: "fat_g", amount: 6),
            ]
        )

        let base = FoodImpactCalculator.calculate(input: input, scale: 1, dailyNutrition: nil, calorieBudget: nil)
        let half = FoodImpactCalculator.calculate(input: input, scale: 0.5, dailyNutrition: nil, calorieBudget: nil)

        XCTAssertEqual(try XCTUnwrap(base.availableCarbohydrate), 28, accuracy: 0.001)
        XCTAssertEqual(base.carbohydrateImpact, .moderate)
        XCTAssertEqual(try XCTUnwrap(half.availableCarbohydrate), 14, accuracy: 0.001)
        XCTAssertEqual(half.carbohydrateImpact, .lower)
    }

    func testMissingCarbohydrateIsUnavailableInsteadOfZero() {
        let input = food(calories: 160, nutrients: [.init(code: "protein_g", amount: 20)])

        let result = FoodImpactCalculator.calculate(input: input, scale: 1, dailyNutrition: nil, calorieBudget: 2_000)

        XCTAssertNil(result.availableCarbohydrate)
        XCTAssertEqual(result.carbohydrateImpact, .unavailable)
        XCTAssertFalse(result.hasCompleteCoreNutrition)
    }

    func testProspectiveServingIsAddedButLoggedServingIsNotDoubleCounted() {
        let daily = summary(totalCalories: 700)
        let prospective = FoodImpactCalculator.calculate(
            input: food(calories: 300, context: .prospective), scale: 1,
            dailyNutrition: daily, calorieBudget: 1_800
        )
        let logged = FoodImpactCalculator.calculate(
            input: food(calories: 300, context: .logged), scale: 1,
            dailyNutrition: daily, calorieBudget: 1_800
        )

        XCTAssertEqual(prospective.projectedCaloriesRemaining, 800)
        XCTAssertEqual(logged.projectedCaloriesRemaining, 1_100)
    }

    func testDailyValueCalloutsRequireTwentyPercent() {
        let daily = summary(
            totalCalories: 700,
            nutrients: [
                dailyNutrient(code: "fiber_g", name: "Dietary fiber", kind: .goal, amount: 4, target: 28),
                dailyNutrient(code: "sodium_mg", name: "Sodium", kind: .limit, amount: 1_000, target: 2_300),
            ]
        )
        let input = food(
            calories: 300,
            nutrients: [
                .init(code: "fiber_g", amount: 7),
                .init(code: "sodium_mg", amount: 500),
            ]
        )

        let result = FoodImpactCalculator.calculate(input: input, scale: 1, dailyNutrition: daily, calorieBudget: 1_800)

        XCTAssertEqual(result.strengths.map(\.code), ["fiber_g"])
        XCTAssertEqual(result.tradeoffs.map(\.code), ["sodium_mg"])
    }

    private func food(
        calories: Double,
        nutrients: [NutrientAmountInput] = [],
        context: FoodImpactContext = .prospective
    ) -> FoodImpactInput {
        FoodImpactInput(
            name: "Test food", baseCalories: calories, nutrients: nutrients,
            provenance: "Test", confidence: 1, context: context
        )
    }

    private func summary(totalCalories: Int, nutrients: [DailyNutrient] = []) -> DailyNutritionSummary {
        DailyNutritionSummary(
            localDate: "2026-08-07", totalCalories: totalCalories, macroCoverage: 1,
            reference: NutrientReference(
                code: "test", name: "Test", population: "Adults",
                sourceURL: URL(string: "https://example.com")!
            ),
            nutrients: nutrients
        )
    }

    private func dailyNutrient(
        code: String,
        name: String,
        kind: NutrientTargetKind,
        amount: Double,
        target: Double
    ) -> DailyNutrient {
        DailyNutrient(
            code: code, name: name, unit: code.hasSuffix("_mg") ? "mg" : "g",
            nutrientClass: "test", displayOrder: 1, targetKind: kind,
            amount: amount, targetAmount: target, percentOfTarget: amount / target,
            coverage: 1, estimatedAmount: 0, verifiedAmount: amount, confidence: 1
        )
    }
}
