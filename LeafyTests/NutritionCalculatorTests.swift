import XCTest
@testable import Leafy

final class NutritionCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var now: Date { ISO8601DateFormatter().date(from: "2026-07-29T12:00:00Z")! }

    func testMaleSteadyLossFixture() throws {
        let input = NutritionPlanInput(
            birthDate: calendar.date(from: DateComponents(year: 1996, month: 7, day: 1))!,
            calculationSex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 80,
            activityLevel: .moderate, goal: .lose, pace: .steady, unitSystem: .metric
        )
        let plan = try NutritionCalculator.calculate(input: input, now: now, calendar: calendar)
        XCTAssertEqual(plan.bmrKcal, 1880)
        XCTAssertEqual(plan.tdeeKcal, 2914)
        XCTAssertEqual(plan.calorieTargetKcal, 2480)
        XCTAssertEqual(plan.proteinG, 128)
        XCTAssertEqual(plan.fatG, 83)
        XCTAssertEqual(plan.carbohydrateG, 306)
        XCTAssertEqual(plan.calculatorVersion, "msj-amdr-v1")
        XCTAssertNotNil(plan.estimatedGoalDate)
    }

    func testMaintainHasNoDate() throws {
        let input = NutritionPlanInput(
            birthDate: calendar.date(from: DateComponents(year: 1986, month: 1, day: 1))!,
            calculationSex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: nil,
            activityLevel: .light, goal: .maintain, pace: .steady, unitSystem: .imperial
        )
        let plan = try NutritionCalculator.calculate(input: input, now: now, calendar: calendar)
        XCTAssertNil(plan.estimatedGoalDate)
        XCTAssertEqual(plan.projectedWeeklyChangeKG, 0, accuracy: 0.0001)
    }

    func testRejectsConflictingGoal() {
        let input = NutritionPlanInput(
            birthDate: calendar.date(from: DateComponents(year: 1990, month: 1, day: 1))!,
            calculationSex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: 70,
            activityLevel: .light, goal: .lose, pace: .steady, unitSystem: .metric
        )
        XCTAssertThrowsError(try NutritionCalculator.calculate(input: input, now: now, calendar: calendar)) {
            XCTAssertEqual($0 as? PlanValidationError, .conflictingTarget)
        }
    }

    func testRejectsUnderweightLossTarget() {
        let input = NutritionPlanInput(
            birthDate: calendar.date(from: DateComponents(year: 1990, month: 1, day: 1))!,
            calculationSex: .female, heightCM: 175, currentWeightKG: 60, targetWeightKG: 50,
            activityLevel: .moderate, goal: .lose, pace: .gentle, unitSystem: .metric
        )
        XCTAssertThrowsError(try NutritionCalculator.calculate(input: input, now: now, calendar: calendar)) {
            XCTAssertEqual($0 as? PlanValidationError, .underweightLossGoal)
        }
    }

    func testProteinAndFatRemainWithinAMDR() throws {
        let input = NutritionPlanInput(
            birthDate: calendar.date(from: DateComponents(year: 1980, month: 2, day: 1))!,
            calculationSex: .male, heightCM: 190, currentWeightKG: 150, targetWeightKG: 130,
            activityLevel: .sedentary, goal: .lose, pace: .faster, unitSystem: .metric
        )
        let plan = try NutritionCalculator.calculate(input: input, now: now, calendar: calendar)
        let proteinShare = Double(plan.proteinG * 4) / Double(plan.calorieTargetKcal)
        let fatShare = Double(plan.fatG * 9) / Double(plan.calorieTargetKcal)
        let carbShare = Double(plan.carbohydrateG * 4) / Double(plan.calorieTargetKcal)
        XCTAssertTrue((0.10...0.35).contains(proteinShare))
        XCTAssertTrue((0.19...0.31).contains(fatShare))
        XCTAssertGreaterThanOrEqual(carbShare, 0.44)
    }
}
