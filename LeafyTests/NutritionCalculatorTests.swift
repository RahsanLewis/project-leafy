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

    func testCrossImplementationParitySuccessMatrix() throws {
        enum GoalDateExpectation {
            case none
            case some
            case ymd(String)
        }

        struct SuccessCase {
            let label: String
            let birth: (year: Int, month: Int, day: Int)
            let sex: CalculationSex
            let heightCM: Double
            let currentWeightKG: Double
            let targetWeightKG: Double?
            let activity: ActivityLevel
            let goal: WeightGoal
            let pace: GoalPace
            let unitSystem: UnitSystem
            let bmr: Int
            let tdee: Int
            let calorieTarget: Int
            let proteinG: Int
            let carbohydrateG: Int
            let fatG: Int
            let weeklyChange: Double
            let weeklyAccuracy: Double
            let goalDate: GoalDateExpectation
        }

        // J, K, and L pin sub-1200 calorie targets for maintain and gain. That is current
        // behavior and is under nutrition-policy review — do not change the calculator.
        let cases: [SuccessCase] = [
            SuccessCase(
                label: "A male moderate lose steady metric",
                birth: (1996, 7, 1), sex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 80,
                activity: .moderate, goal: .lose, pace: .steady, unitSystem: .metric,
                bmr: 1880, tdee: 2914, calorieTarget: 2480, proteinG: 128, carbohydrateG: 306, fatG: 83,
                weeklyChange: 0.39454545454545453, weeklyAccuracy: 1e-9, goalDate: .ymd("2027-01-23")
            ),
            SuccessCase(
                label: "B female light maintain steady imperial",
                birth: (1986, 1, 1), sex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: nil,
                activity: .light, goal: .maintain, pace: .steady, unitSystem: .imperial,
                bmr: 1320, tdee: 1815, calorieTarget: 1820, proteinG: 78, carbohydrateG: 241, fatG: 61,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            SuccessCase(
                label: "C male sedentary maintain gentle metric",
                birth: (1990, 3, 15), sex: .male, heightCM: 178, currentWeightKG: 82, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .gentle, unitSystem: .metric,
                bmr: 1758, tdee: 2109, calorieTarget: 2110, proteinG: 98, carbohydrateG: 271, fatG: 70,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            SuccessCase(
                label: "D male moderate gain gentle metric",
                birth: (1996, 7, 1), sex: .male, heightCM: 180, currentWeightKG: 70, targetWeightKG: 78,
                activity: .moderate, goal: .gain, pace: .gentle, unitSystem: .metric,
                bmr: 1680, tdee: 2604, calorieTarget: 2730, proteinG: 125, carbohydrateG: 353, fatG: 91,
                weeklyChange: 0.11454545454545455, weeklyAccuracy: 1e-9, goalDate: .ymd("2027-11-30")
            ),
            SuccessCase(
                label: "E male moderate gain steady metric",
                birth: (1996, 7, 1), sex: .male, heightCM: 180, currentWeightKG: 70, targetWeightKG: 78,
                activity: .moderate, goal: .gain, pace: .steady, unitSystem: .metric,
                bmr: 1680, tdee: 2604, calorieTarget: 2860, proteinG: 125, carbohydrateG: 376, fatG: 95,
                weeklyChange: 0.23272727272727273, weeklyAccuracy: 1e-9, goalDate: .ymd("2027-03-27")
            ),
            SuccessCase(
                label: "F male moderate gain faster metric",
                birth: (1996, 7, 1), sex: .male, heightCM: 180, currentWeightKG: 70, targetWeightKG: 78,
                activity: .moderate, goal: .gain, pace: .faster, unitSystem: .metric,
                bmr: 1680, tdee: 2604, calorieTarget: 2990, proteinG: 125, carbohydrateG: 398, fatG: 100,
                weeklyChange: 0.3509090909090909, weeklyAccuracy: 1e-9, goalDate: .ymd("2027-01-05")
            ),
            SuccessCase(
                label: "G male sedentary lose faster metric (BMR floor dominant)",
                birth: (1996, 7, 1), sex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 80,
                activity: .sedentary, goal: .lose, pace: .faster, unitSystem: .metric,
                bmr: 1880, tdee: 2256, calorieTarget: 1880, proteinG: 128, carbohydrateG: 212, fatG: 58,
                weeklyChange: 0.3418181818181818, weeklyAccuracy: 1e-9, goalDate: .ymd("2027-02-19")
            ),
            SuccessCase(
                label: "H female light lose faster metric (1200 floor dominant)",
                birth: (1976, 7, 1), sex: .female, heightCM: 155, currentWeightKG: 45, targetWeightKG: 44.5,
                activity: .light, goal: .lose, pace: .faster, unitSystem: .metric,
                bmr: 1008, tdee: 1386, calorieTarget: 1200, proteinG: 71, carbohydrateG: 139, fatG: 40,
                weeklyChange: 0.1687784090909091, weeklyAccuracy: 1e-9, goalDate: .ymd("2026-08-19")
            ),
            SuccessCase(
                label: "I male moderate lose gentle metric",
                birth: (1996, 7, 1), sex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 80,
                activity: .moderate, goal: .lose, pace: .gentle, unitSystem: .metric,
                bmr: 1880, tdee: 2914, calorieTarget: 2620, proteinG: 128, carbohydrateG: 331, fatG: 87,
                weeklyChange: 0.2672727272727273, weeklyAccuracy: 1e-9, goalDate: .some
            ),
            SuccessCase(
                label: "J female sedentary maintain steady metric (sub-1200, policy review)",
                birth: (1990, 1, 1), sex: .female, heightCM: 120, currentWeightKG: 40, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, unitSystem: .metric,
                bmr: 809, tdee: 971, calorieTarget: 970, proteinG: 48, carbohydrateG: 122, fatG: 32,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            SuccessCase(
                label: "K female sedentary maintain steady metric (sub-1200, policy review)",
                birth: (1990, 1, 1), sex: .female, heightCM: 150, currentWeightKG: 35, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, unitSystem: .metric,
                bmr: 947, tdee: 1136, calorieTarget: 1140, proteinG: 42, carbohydrateG: 158, fatG: 38,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            SuccessCase(
                label: "L female sedentary gain gentle metric (sub-1200, policy review)",
                birth: (1990, 1, 1), sex: .female, heightCM: 120, currentWeightKG: 35, targetWeightKG: 40,
                activity: .sedentary, goal: .gain, pace: .gentle, unitSystem: .metric,
                bmr: 759, tdee: 911, calorieTarget: 960, proteinG: 64, carbohydrateG: 108, fatG: 30,
                weeklyChange: 0.04472727272727277, weeklyAccuracy: 1e-9, goalDate: .some
            ),
            SuccessCase(
                label: "M female light maintain steady metric (age exactly 18)",
                birth: (2008, 7, 29), sex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: nil,
                activity: .light, goal: .maintain, pace: .steady, unitSystem: .metric,
                bmr: 1430, tdee: 1967, calorieTarget: 1970, proteinG: 78, carbohydrateG: 267, fatG: 66,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            SuccessCase(
                label: "N male sedentary maintain steady metric (age exactly 100)",
                birth: (1926, 7, 29), sex: .male, heightCM: 170, currentWeightKG: 70, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, unitSystem: .metric,
                bmr: 1268, tdee: 1521, calorieTarget: 1520, proteinG: 84, carbohydrateG: 182, fatG: 51,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            SuccessCase(
                label: "O male athlete maintain steady metric (height 230 max)",
                birth: (1990, 1, 1), sex: .male, heightCM: 230, currentWeightKG: 120, targetWeightKG: nil,
                activity: .athlete, goal: .maintain, pace: .steady, unitSystem: .metric,
                bmr: 2463, tdee: 4679, calorieTarget: 4680, proteinG: 144, carbohydrateG: 675, fatG: 156,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            SuccessCase(
                label: "P male sedentary maintain steady metric (weight 350 max)",
                birth: (1990, 1, 1), sex: .male, heightCM: 190, currentWeightKG: 350, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, unitSystem: .metric,
                bmr: 4513, tdee: 5415, calorieTarget: 5420, proteinG: 420, carbohydrateG: 610, fatG: 145,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            SuccessCase(
                label: "Q male very_active maintain steady metric",
                birth: (1990, 1, 1), sex: .male, heightCM: 180, currentWeightKG: 80, targetWeightKG: nil,
                activity: .veryActive, goal: .maintain, pace: .steady, unitSystem: .metric,
                bmr: 1750, tdee: 3019, calorieTarget: 3020, proteinG: 96, carbohydrateG: 433, fatG: 101,
                weeklyChange: 0.0, weeklyAccuracy: 0, goalDate: .none
            ),
            // 1472 * 1.725 = 2539.2 but tdee is 2538 and that is CORRECT — bmr and tdee round
            // independently from raw values (rawBMR exactly 1471.5, rawTDEE 2538.3375).
            // Do not derive tdee from the rounded bmr.
            SuccessCase(
                label: "R female very_active lose steady metric",
                birth: (1990, 1, 1), sex: .female, heightCM: 170, currentWeightKG: 75, targetWeightKG: 68,
                activity: .veryActive, goal: .lose, pace: .steady, unitSystem: .metric,
                bmr: 1472, tdee: 2538, calorieTarget: 2160, proteinG: 109, carbohydrateG: 269, fatG: 72,
                weeklyChange: 0.3439431818181819, weeklyAccuracy: 1e-9, goalDate: .ymd("2026-12-19")
            ),
        ]

        for tc in cases {
            let input = NutritionPlanInput(
                birthDate: utcDate(tc.birth.year, tc.birth.month, tc.birth.day),
                calculationSex: tc.sex,
                heightCM: tc.heightCM,
                currentWeightKG: tc.currentWeightKG,
                targetWeightKG: tc.targetWeightKG,
                activityLevel: tc.activity,
                goal: tc.goal,
                pace: tc.pace,
                unitSystem: tc.unitSystem
            )
            let plan = try NutritionCalculator.calculate(input: input, now: now, calendar: calendar)
            XCTAssertEqual(plan.bmrKcal, tc.bmr, "\(tc.label) bmr")
            XCTAssertEqual(plan.tdeeKcal, tc.tdee, "\(tc.label) tdee")
            XCTAssertEqual(plan.calorieTargetKcal, tc.calorieTarget, "\(tc.label) calorieTarget")
            XCTAssertEqual(plan.proteinG, tc.proteinG, "\(tc.label) proteinG")
            XCTAssertEqual(plan.carbohydrateG, tc.carbohydrateG, "\(tc.label) carbohydrateG")
            XCTAssertEqual(plan.fatG, tc.fatG, "\(tc.label) fatG")
            XCTAssertEqual(plan.projectedWeeklyChangeKG, tc.weeklyChange, accuracy: tc.weeklyAccuracy, "\(tc.label) projectedWeeklyChangeKG")
            switch tc.goalDate {
            case .none:
                XCTAssertNil(plan.estimatedGoalDate, "\(tc.label) estimatedGoalDate")
            case .some:
                XCTAssertNotNil(plan.estimatedGoalDate, "\(tc.label) estimatedGoalDate")
            case .ymd(let expected):
                XCTAssertNotNil(plan.estimatedGoalDate, "\(tc.label) estimatedGoalDate")
                if let goalDate = plan.estimatedGoalDate {
                    XCTAssertEqual(utcYMD(goalDate), expected, "\(tc.label) estimatedGoalDate")
                }
            }
        }
    }

    func testCrossImplementationParityRejectionMatrix() {
        struct RejectionCase {
            let label: String
            let birth: (year: Int, month: Int, day: Int)
            let sex: CalculationSex
            let heightCM: Double
            let currentWeightKG: Double
            let targetWeightKG: Double?
            let activity: ActivityLevel
            let goal: WeightGoal
            let pace: GoalPace
            let expected: PlanValidationError
        }

        let cases: [RejectionCase] = [
            RejectionCase(
                label: "S age 17",
                birth: (2008, 7, 30), sex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: nil,
                activity: .light, goal: .maintain, pace: .steady, expected: .invalidAge
            ),
            RejectionCase(
                label: "T age 101",
                birth: (1925, 7, 28), sex: .male, heightCM: 170, currentWeightKG: 70, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, expected: .invalidAge
            ),
            RejectionCase(
                label: "U height 119",
                birth: (1990, 1, 1), sex: .female, heightCM: 119, currentWeightKG: 40, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, expected: .invalidHeight
            ),
            RejectionCase(
                label: "V height 231",
                birth: (1990, 1, 1), sex: .male, heightCM: 231, currentWeightKG: 120, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, expected: .invalidHeight
            ),
            RejectionCase(
                label: "W weight 34",
                birth: (1990, 1, 1), sex: .female, heightCM: 150, currentWeightKG: 34, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, expected: .invalidWeight
            ),
            RejectionCase(
                label: "X weight 351",
                birth: (1990, 1, 1), sex: .male, heightCM: 190, currentWeightKG: 351, targetWeightKG: nil,
                activity: .sedentary, goal: .maintain, pace: .steady, expected: .invalidWeight
            ),
            RejectionCase(
                label: "Y lose current BMI < 18.5",
                birth: (1990, 1, 1), sex: .female, heightCM: 170, currentWeightKG: 50, targetWeightKG: 45,
                activity: .light, goal: .lose, pace: .steady, expected: .underweightLossGoal
            ),
            RejectionCase(
                label: "Z lose target BMI < 18.5",
                birth: (1990, 1, 1), sex: .female, heightCM: 170, currentWeightKG: 60, targetWeightKG: 50,
                activity: .light, goal: .lose, pace: .steady, expected: .underweightLossGoal
            ),
            RejectionCase(
                label: "AA lose target above current",
                birth: (1990, 1, 1), sex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 95,
                activity: .moderate, goal: .lose, pace: .steady, expected: .conflictingTarget
            ),
            RejectionCase(
                label: "AB gain target below current",
                birth: (1990, 1, 1), sex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 85,
                activity: .moderate, goal: .gain, pace: .steady, expected: .conflictingTarget
            ),
            RejectionCase(
                label: "AC lose target equal to current",
                birth: (1990, 1, 1), sex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 90,
                activity: .moderate, goal: .lose, pace: .steady, expected: .conflictingTarget
            ),
            RejectionCase(
                label: "AD gain target equal to current",
                birth: (1990, 1, 1), sex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 90,
                activity: .moderate, goal: .gain, pace: .steady, expected: .conflictingTarget
            ),
            RejectionCase(
                label: "AE gain missing target",
                birth: (1990, 1, 1), sex: .male, heightCM: 180, currentWeightKG: 70, targetWeightKG: nil,
                activity: .moderate, goal: .gain, pace: .steady, expected: .missingTarget
            ),
            RejectionCase(
                label: "AF no safe deficit",
                birth: (1966, 1, 1), sex: .female, heightCM: 150, currentWeightKG: 50, targetWeightKG: 45,
                activity: .sedentary, goal: .lose, pace: .faster, expected: .noSafeDeficit
            ),
            // Known client/server structural difference, under product review — not a bug to "fix"
            // in this PR. Swift validates target range (NutritionCalculator.swift L17-18) and throws
            // `.invalidWeight` for a 20 kg target. The server collapses this into its missing-target
            // error. Assert Swift's actual case only; do not assert error message strings.
            RejectionCase(
                label: "AG out-of-range target 20kg",
                birth: (1990, 1, 1), sex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 20,
                activity: .moderate, goal: .lose, pace: .steady, expected: .invalidWeight
            ),
        ]

        for tc in cases {
            let input = NutritionPlanInput(
                birthDate: utcDate(tc.birth.year, tc.birth.month, tc.birth.day),
                calculationSex: tc.sex,
                heightCM: tc.heightCM,
                currentWeightKG: tc.currentWeightKG,
                targetWeightKG: tc.targetWeightKG,
                activityLevel: tc.activity,
                goal: tc.goal,
                pace: tc.pace,
                unitSystem: .metric
            )
            XCTAssertThrowsError(
                try NutritionCalculator.calculate(input: input, now: now, calendar: calendar),
                tc.label
            ) { error in
                XCTAssertEqual(error as? PlanValidationError, tc.expected, tc.label)
            }
        }
    }

    func testEligibilityStartsUnanswered() {
        let draft = OnboardingDraft()

        XCTAssertFalse(draft.hasCompletedEligibility)
        XCTAssertFalse(draft.isEligible)
        XCTAssertFalse(draft.isIneligible)
    }

    func testEligibleAnswersCompleteSafetyCheck() {
        let draft = OnboardingDraft()
        draft.confirmsAdult = true
        answerHealthQuestions(draft)

        XCTAssertTrue(draft.hasCompletedEligibility)
        XCTAssertTrue(draft.isEligible)
        XCTAssertFalse(draft.isIneligible)
    }

    func testUnderageAnswerIsIneligible() {
        let draft = OnboardingDraft()
        draft.confirmsAdult = false
        answerHealthQuestions(draft)

        XCTAssertTrue(draft.hasCompletedEligibility)
        XCTAssertFalse(draft.isEligible)
        XCTAssertTrue(draft.isIneligible)
    }

    func testHealthConsiderationIsIneligible() {
        let draft = OnboardingDraft()
        draft.confirmsAdult = true
        answerHealthQuestions(draft, pregnantOrBreastfeeding: true)

        XCTAssertTrue(draft.hasCompletedEligibility)
        XCTAssertFalse(draft.isEligible)
        XCTAssertTrue(draft.isIneligible)
    }

    func testDefaultLossMeasurementsAreValid() {
        let draft = OnboardingDraft()

        XCTAssertTrue(draft.hasValidMeasurements)
        XCTAssertEqual(draft.goalDifferenceKG, 6, accuracy: 0.0001)
    }

    func testHealthQuestionsRemainIncompleteUntilEachIsAnswered() {
        let draft = OnboardingDraft()
        draft.confirmsAdult = true
        draft.isPregnantOrBreastfeeding = false
        draft.isInEatingDisorderRecovery = false

        XCTAssertNil(draft.hasContraindication)
        XCTAssertFalse(draft.hasCompletedEligibility)

        draft.followsClinicianDirectedDiet = false
        XCTAssertEqual(draft.hasContraindication, false)
        XCTAssertTrue(draft.hasCompletedEligibility)
    }

    func testEachHealthConsiderationMakesDraftIneligible() {
        let draft = OnboardingDraft()
        draft.confirmsAdult = true

        answerHealthQuestions(draft, eatingDisorderRecovery: true)
        XCTAssertTrue(draft.isIneligible)

        answerHealthQuestions(draft, clinicianDirectedDiet: true)
        XCTAssertTrue(draft.isIneligible)
    }

    func testImperialHeightFeetAndInchesRemainIndependent() {
        var selection = ImperialHeightSelection(feet: 5, inches: 10)

        selection.feet = 6

        XCTAssertEqual(selection.feet, 6)
        XCTAssertEqual(selection.inches, 10)
        XCTAssertEqual(selection.centimeters, 208.28, accuracy: 0.001)

        selection.inches = 2
        XCTAssertEqual(selection.feet, 6)
        XCTAssertEqual(selection.inches, 2)
    }

    func testImperialHeightRoundTripAndSupportedRange() {
        let selection = ImperialHeightSelection(centimeters: 177.8)

        XCTAssertEqual(selection, ImperialHeightSelection(feet: 5, inches: 10))
        XCTAssertTrue(selection.isSupported)
        XCTAssertFalse(ImperialHeightSelection(feet: 3, inches: 10).isSupported)
        XCTAssertFalse(ImperialHeightSelection(feet: 7, inches: 7).isSupported)
    }

    func testLossTargetMustBeBelowCurrentWeight() {
        let draft = OnboardingDraft()
        draft.targetWeightKG = draft.currentWeightKG

        XCTAssertFalse(draft.hasValidMeasurements)
    }

    func testGainGoalCreatesHigherTarget() {
        let draft = OnboardingDraft()
        draft.goal = .gain

        XCTAssertGreaterThan(draft.targetWeightKG, draft.currentWeightKG)
        XCTAssertTrue(draft.hasValidMeasurements)
    }

    func testMaintainDoesNotRequireTargetWeight() {
        let draft = OnboardingDraft()
        draft.goal = .maintain
        draft.targetWeightKG = 1

        XCTAssertTrue(draft.hasValidMeasurements)
    }

    func testOnboardingStepsUseStableIdentifiers() {
        XCTAssertEqual(OnboardingDraft.Step.welcome.rawValue, "welcome")
        XCTAssertEqual(OnboardingDraft.Step.targetWeight.rawValue, "targetWeight")
        XCTAssertEqual(OnboardingDraft.Step.account.rawValue, "account")
    }

    func testLegacyOnboardingResultsAndAccountRestoreDirectly() {
        let draft = OnboardingDraft()
        XCTAssertEqual(OnboardingDraft.Step.legacy(6, draft: draft), .results)
        XCTAssertEqual(OnboardingDraft.Step.legacy(7, draft: draft), .account)
    }

    func testLegacyEligibilityRestoresFirstIncompleteQuestion() {
        let draft = OnboardingDraft()
        XCTAssertEqual(OnboardingDraft.Step.legacy(1, draft: draft), .adultEligibility)
        draft.confirmsAdult = true
        XCTAssertEqual(OnboardingDraft.Step.legacy(1, draft: draft), .healthConsiderations)
        answerHealthQuestions(draft)
        XCTAssertEqual(OnboardingDraft.Step.legacy(1, draft: draft), .goal)
    }

    /// Birth dates for calculator fixtures. Always uses the injected Gregorian UTC calendar,
    /// never `Calendar.current` (LEAFY-021: production still defaults to current TZ).
    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Format an estimated goal date with the injected UTC calendar so assertions are TZ-independent.
    private func utcYMD(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    private func answerHealthQuestions(
        _ draft: OnboardingDraft,
        pregnantOrBreastfeeding: Bool = false,
        eatingDisorderRecovery: Bool = false,
        clinicianDirectedDiet: Bool = false
    ) {
        draft.isPregnantOrBreastfeeding = pregnantOrBreastfeeding
        draft.isInEatingDisorderRecovery = eatingDisorderRecovery
        draft.followsClinicianDirectedDiet = clinicianDirectedDiet
    }
}
