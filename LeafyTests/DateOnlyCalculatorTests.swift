import XCTest
@testable import Leafy

/// LEAFY-021: production calculator uses Gregorian UTC civil Y/M/D.
/// Timezones are pinned explicitly. These numbers match calculator.ts; they do
/// not ratify the 18/100 eligibility cutoff as a product policy.
final class DateOnlyCalculatorTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
    private let honolulu = TimeZone(identifier: "Pacific/Honolulu")!

    private var surroundingZones: [TimeZone] {
        [utc, newYork, losAngeles, kiritimati, honolulu]
    }

    private let beforeUTC = ISO8601DateFormatter().date(from: "2026-07-28T23:59:59Z")!
    private let atUTC = ISO8601DateFormatter().date(from: "2026-07-29T00:00:00Z")!
    private let afterUTC = ISO8601DateFormatter().date(from: "2026-07-29T00:00:01Z")!
    private let noonUTC = ISO8601DateFormatter().date(from: "2026-07-29T12:00:00Z")!

    func testBirthdayProfileSameOutcomeAcrossSurroundingZones() throws {
        let cases: [(LocalDate, Date, Result<ExpectedPlan, PlanValidationError>)] = [
            (try civil(2008, 7, 29), beforeUTC, .failure(.invalidAge)),
            (try civil(2008, 7, 29), atUTC, .success(ExpectedPlan(bmr: 1430, tdee: 1967, calories: 1970, protein: 78, carbs: 267, fat: 66, weekly: 0, date: nil))),
            (try civil(2008, 7, 29), afterUTC, .success(ExpectedPlan(bmr: 1430, tdee: 1967, calories: 1970, protein: 78, carbs: 267, fat: 66, weekly: 0, date: nil))),
            (try civil(1926, 7, 29), beforeUTC, .success(ExpectedPlan(bmr: 1025, tdee: 1410, calories: 1410, protein: 78, carbs: 169, fat: 47, weekly: 0, date: nil))),
            (try civil(1926, 7, 29), atUTC, .success(ExpectedPlan(bmr: 1020, tdee: 1403, calories: 1400, protein: 78, carbs: 167, fat: 47, weekly: 0, date: nil))),
            (try civil(1926, 7, 29), afterUTC, .success(ExpectedPlan(bmr: 1020, tdee: 1403, calories: 1400, protein: 78, carbs: 167, fat: 47, weekly: 0, date: nil))),
            (try civil(1925, 7, 29), beforeUTC, .success(ExpectedPlan(bmr: 1020, tdee: 1403, calories: 1400, protein: 78, carbs: 167, fat: 47, weekly: 0, date: nil))),
            (try civil(1925, 7, 29), atUTC, .failure(.invalidAge)),
            (try civil(1925, 7, 29), afterUTC, .failure(.invalidAge)),
            (try civil(1990, 7, 29), beforeUTC, .success(ExpectedPlan(bmr: 1345, tdee: 1850, calories: 1850, protein: 78, carbs: 246, fat: 62, weekly: 0, date: nil))),
            (try civil(1990, 7, 29), atUTC, .success(ExpectedPlan(bmr: 1340, tdee: 1843, calories: 1840, protein: 78, carbs: 244, fat: 61, weekly: 0, date: nil))),
            (try civil(1990, 7, 29), afterUTC, .success(ExpectedPlan(bmr: 1340, tdee: 1843, calories: 1840, protein: 78, carbs: 244, fat: 61, weekly: 0, date: nil))),
        ]

        for timeZone in surroundingZones {
            for testCase in cases {
                let pickerDate = localMidnight(year: testCase.0.year, month: testCase.0.month, day: testCase.0.day, timeZone: timeZone)
                let extracted = try XCTUnwrap(LocalDate(localCivilFrom: pickerDate, timeZone: timeZone))
                XCTAssertEqual(extracted, testCase.0, "DatePicker boundary in \(timeZone.identifier)")
                assertCalculate(birth: extracted, now: testCase.1, expected: testCase.2, zone: timeZone)
            }
        }
    }

    func testLocalMidnightDoesNotMoveUTCBoundary() throws {
        let birth = try civil(2008, 7, 29)
        for timeZone in surroundingZones {
            let atLocalMidnight = localMidnight(year: 2026, month: 7, day: 29, timeZone: timeZone)
            let beforeLocalMidnight = atLocalMidnight.addingTimeInterval(-1)
            let beforePlan = Result { try NutritionCalculator.calculate(input: maintainFemale(birth), now: beforeLocalMidnight) }
            let atPlan = Result { try NutritionCalculator.calculate(input: maintainFemale(birth), now: atLocalMidnight) }

            if timeZone.secondsFromGMT() == 0 {
                XCTAssertThrowsError(try beforePlan.get()) { XCTAssertEqual($0 as? PlanValidationError, .invalidAge) }
                let plan = try atPlan.get()
                XCTAssertEqual(plan.calorieTargetKcal, 1970)
            } else {
                switch (beforePlan, atPlan) {
                case (.success(let left), .success(let right)):
                    XCTAssertEqual(left.bmrKcal, right.bmrKcal)
                    XCTAssertEqual(left.calorieTargetKcal, right.calorieTargetKcal)
                    XCTAssertEqual(left.proteinG, right.proteinG)
                    XCTAssertEqual(left.carbohydrateG, right.carbohydrateG)
                    XCTAssertEqual(left.fatG, right.fatG)
                case (.failure(let left), .failure(let right)):
                    XCTAssertEqual(left as? PlanValidationError, right as? PlanValidationError)
                default:
                    XCTFail("local midnight flipped the outcome in \(timeZone.identifier)")
                }
            }
        }
    }

    func testC5GoalDateUsesCivilUTCDaysNotClockTime() throws {
        let input = NutritionPlanInput(
            birthDate: try civil(1996, 7, 1),
            calculationSex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 80,
            activityLevel: .sedentary, goal: .lose, pace: .faster, unitSystem: .metric
        )
        let july = try NutritionCalculator.calculate(input: input, now: noonUTC)
        XCTAssertEqual(july.bmrKcal, 1880)
        XCTAssertEqual(july.tdeeKcal, 2256)
        XCTAssertEqual(july.calorieTargetKcal, 1880)
        XCTAssertEqual(july.projectedWeeklyChangeKG, 0.3418181818181818, accuracy: 1e-12)
        XCTAssertEqual(july.estimatedGoalDate, try civil(2027, 2, 19))

        let fallDST = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
        let springDST = ISO8601DateFormatter().date(from: "2027-03-13T12:00:00Z")!
        XCTAssertEqual(try NutritionCalculator.calculate(input: input, now: fallDST).estimatedGoalDate, try civil(2027, 5, 24))
        let springPlan = try NutritionCalculator.calculate(input: input, now: springDST)
        XCTAssertEqual(springPlan.estimatedGoalDate, try civil(2027, 10, 4))
        XCTAssertEqual(springPlan.bmrKcal, 1880)
        XCTAssertEqual(springPlan.tdeeKcal, 2256)
        XCTAssertEqual(springPlan.calorieTargetKcal, 1880)
    }

    func testC6FloorAndCivilGoalDate() throws {
        let input = NutritionPlanInput(
            birthDate: try civil(1976, 7, 1),
            calculationSex: .female, heightCM: 155, currentWeightKG: 45, targetWeightKG: 44.5,
            activityLevel: .light, goal: .lose, pace: .faster, unitSystem: .metric
        )
        let plan = try NutritionCalculator.calculate(input: input, now: noonUTC)
        XCTAssertEqual(plan.bmrKcal, 1008)
        XCTAssertEqual(plan.tdeeKcal, 1386)
        XCTAssertEqual(plan.calorieTargetKcal, 1200)
        XCTAssertEqual(plan.projectedWeeklyChangeKG, 0.1687784090909091, accuracy: 1e-12)
        XCTAssertEqual(plan.estimatedGoalDate, try civil(2026, 8, 19))
    }

    func testPlanInputEqualityUsesCivilYMD() throws {
        let first = maintainFemale(try civil(1990, 7, 29))
        var second = first
        XCTAssertEqual(first, second)
        second.birthDate = try civil(1990, 7, 28)
        XCTAssertNotEqual(first, second)
        second.birthDate = try civil(1990, 7, 29)
        XCTAssertEqual(first, second)
    }

    private func assertCalculate(
        birth: LocalDate,
        now: Date,
        expected: Result<ExpectedPlan, PlanValidationError>,
        zone: TimeZone
    ) {
        let result = Result { try NutritionCalculator.calculate(input: maintainFemale(birth), now: now) }
        switch (result, expected) {
        case (.success(let plan), .success(let want)):
            XCTAssertEqual(plan.bmrKcal, want.bmr, "\(birth) @ \(now) in \(zone.identifier)")
            XCTAssertEqual(plan.tdeeKcal, want.tdee)
            XCTAssertEqual(plan.calorieTargetKcal, want.calories)
            XCTAssertEqual(plan.proteinG, want.protein)
            XCTAssertEqual(plan.carbohydrateG, want.carbs)
            XCTAssertEqual(plan.fatG, want.fat)
            XCTAssertEqual(plan.projectedWeeklyChangeKG, want.weekly, accuracy: 0.0001)
            XCTAssertEqual(plan.estimatedGoalDate, want.date)
        case (.failure(let error), .failure(let want)):
            XCTAssertEqual(error as? PlanValidationError, want, "\(birth) @ \(now) in \(zone.identifier)")
        default:
            XCTFail("outcome mismatch for \(birth) @ \(now) in \(zone.identifier): \(result)")
        }
    }

    private func maintainFemale(_ birth: LocalDate) -> NutritionPlanInput {
        NutritionPlanInput(
            birthDate: birth,
            calculationSex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: nil,
            activityLevel: .light, goal: .maintain, pace: .steady, unitSystem: .metric
        )
    }

    private func civil(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
        try LocalDate(year: year, month: month, day: day)
    }

    private func localMidnight(year: Int, month: Int, day: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private struct ExpectedPlan {
    var bmr: Int
    var tdee: Int
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var weekly: Double
    var date: LocalDate?
}
