import XCTest
@testable import Leafy

final class NutritionCalculatorTests: XCTestCase {
    private var now: Date { ISO8601DateFormatter().date(from: "2026-07-29T12:00:00Z")! }

    func testMaleSteadyLossFixture() throws {
        let input = NutritionPlanInput(
            birthDate: try LocalDate(year: 1996, month: 7, day: 1),
            calculationSex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 80,
            activityLevel: .moderate, goal: .lose, pace: .steady, unitSystem: .metric
        )
        let plan = try NutritionCalculator.calculate(input: input, now: now)
        XCTAssertEqual(plan.bmrKcal, 1880)
        XCTAssertEqual(plan.tdeeKcal, 2914)
        XCTAssertEqual(plan.calorieTargetKcal, 2480)
        XCTAssertEqual(plan.proteinG, 128)
        XCTAssertEqual(plan.fatG, 83)
        XCTAssertEqual(plan.carbohydrateG, 306)
        XCTAssertEqual(plan.calculatorVersion, "msj-amdr-v1")
        XCTAssertEqual(plan.estimatedGoalDate, try LocalDate(year: 2027, month: 1, day: 23))
    }

    func testMaintainHasNoDate() throws {
        let input = NutritionPlanInput(
            birthDate: try LocalDate(year: 1986, month: 1, day: 1),
            calculationSex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: nil,
            activityLevel: .light, goal: .maintain, pace: .steady, unitSystem: .imperial
        )
        let plan = try NutritionCalculator.calculate(input: input, now: now)
        XCTAssertNil(plan.estimatedGoalDate)
        XCTAssertEqual(plan.projectedWeeklyChangeKG, 0, accuracy: 0.0001)
    }

    func testRejectsConflictingGoal() {
        let input = NutritionPlanInput(
            birthDate: try! LocalDate(year: 1990, month: 1, day: 1),
            calculationSex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: 70,
            activityLevel: .light, goal: .lose, pace: .steady, unitSystem: .metric
        )
        XCTAssertThrowsError(try NutritionCalculator.calculate(input: input, now: now)) {
            XCTAssertEqual($0 as? PlanValidationError, .conflictingTarget)
        }
    }

    func testRejectsUnderweightLossTarget() {
        let input = NutritionPlanInput(
            birthDate: try! LocalDate(year: 1990, month: 1, day: 1),
            calculationSex: .female, heightCM: 175, currentWeightKG: 60, targetWeightKG: 50,
            activityLevel: .moderate, goal: .lose, pace: .gentle, unitSystem: .metric
        )
        XCTAssertThrowsError(try NutritionCalculator.calculate(input: input, now: now)) {
            XCTAssertEqual($0 as? PlanValidationError, .underweightLossGoal)
        }
    }

    func testProteinAndFatRemainWithinAMDR() throws {
        let input = NutritionPlanInput(
            birthDate: try LocalDate(year: 1980, month: 2, day: 1),
            calculationSex: .male, heightCM: 190, currentWeightKG: 150, targetWeightKG: 130,
            activityLevel: .sedentary, goal: .lose, pace: .faster, unitSystem: .metric
        )
        let plan = try NutritionCalculator.calculate(input: input, now: now)
        let proteinShare = Double(plan.proteinG * 4) / Double(plan.calorieTargetKcal)
        let fatShare = Double(plan.fatG * 9) / Double(plan.calorieTargetKcal)
        let carbShare = Double(plan.carbohydrateG * 4) / Double(plan.calorieTargetKcal)
        XCTAssertTrue((0.10...0.35).contains(proteinShare))
        XCTAssertTrue((0.19...0.31).contains(fatShare))
        XCTAssertGreaterThanOrEqual(carbShare, 0.44)
    }

    func testMissingBirthDateDoesNotCalculate() {
        var input = NutritionPlanInput(
            birthDate: try! LocalDate(year: 1990, month: 1, day: 1),
            calculationSex: .female, heightCM: 168, currentWeightKG: 70, targetWeightKG: 64,
            activityLevel: .moderate, goal: .lose, pace: .steady, unitSystem: .imperial
        )
        input.birthDate = nil
        XCTAssertThrowsError(try NutritionCalculator.calculate(input: input, now: now)) {
            XCTAssertEqual($0 as? PlanValidationError, .invalidAge)
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
