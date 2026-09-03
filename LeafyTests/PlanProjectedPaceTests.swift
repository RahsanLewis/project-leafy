import XCTest
@testable import Leafy

/// LEAFY-016: Projected pace is gated on the saved plan's snapshot goal, not the live draft.
///
/// Fallback when `input_snapshot` is absent (pre-upgrade PlanCache): decode succeeds
/// with `inputSnapshot == nil`, and pace is omitted because the plan's own goal
/// cannot be confirmed. Goal is never inferred from target presence or absence.
final class PlanProjectedPaceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    // MARK: - Required pace-gate cases

    func testSnapshotMaintainDraftMaintainOmitsPace() {
        let plan = makePlan(snapshotGoal: .maintain, targetWeightKG: nil, weeklyChange: 0)
        let draft = makeInput(goal: .maintain, targetWeightKG: nil)

        XCTAssertFalse(plan.showsProjectedPace(draftGoal: draft.goal))
        XCTAssertNil(plan.projectedPaceLabel(draftGoal: draft.goal, unitSystem: .metric))
    }

    func testSnapshotMaintainDraftLoseOmitsPace() {
        let plan = makePlan(snapshotGoal: .maintain, targetWeightKG: nil, weeklyChange: 0)
        let draft = makeInput(goal: .lose, targetWeightKG: 80)

        XCTAssertFalse(plan.showsProjectedPace(draftGoal: draft.goal))
        XCTAssertNil(plan.projectedPaceLabel(draftGoal: draft.goal, unitSystem: .metric))
    }

    func testSnapshotMaintainWithResidualWeeklyChangeDraftLoseOmitsPace() {
        let plan = makePlan(snapshotGoal: .maintain, targetWeightKG: nil, weeklyChange: 0.004233)
        let draft = makeInput(goal: .lose, targetWeightKG: 80)

        XCTAssertFalse(plan.showsProjectedPace(draftGoal: draft.goal))
        XCTAssertNil(plan.projectedPaceLabel(draftGoal: draft.goal, unitSystem: .metric))
    }

    func testSnapshotLoseDraftLoseShowsStoredMetricPace() {
        let weeklyChange = 0.50
        let plan = makePlan(snapshotGoal: .lose, targetWeightKG: 80, weeklyChange: weeklyChange)
        let draft = makeInput(goal: .lose, targetWeightKG: 80)

        XCTAssertTrue(plan.showsProjectedPace(draftGoal: draft.goal))
        XCTAssertEqual(
            plan.projectedPaceLabel(draftGoal: draft.goal, unitSystem: .metric),
            "0.50 kg per week"
        )
        XCTAssertEqual(plan.projectedWeeklyChangeKG, weeklyChange, accuracy: 0.0000001)
    }

    func testSnapshotLoseDraftLoseShowsUnchangedImperialFormatting() {
        let weeklyChange = 0.50
        let plan = makePlan(snapshotGoal: .lose, targetWeightKG: 80, weeklyChange: weeklyChange)
        let draft = makeInput(goal: .lose, targetWeightKG: 80, unitSystem: .imperial)

        XCTAssertEqual(
            plan.projectedPaceLabel(draftGoal: draft.goal, unitSystem: draft.unitSystem),
            "1.1 lb per week"
        )
        XCTAssertEqual(plan.projectedWeeklyChangeKG, weeklyChange, accuracy: 0.0000001)
    }

    func testCachedPlanWithoutInputSnapshotDoesNotCrashAndOmitsPace() throws {
        let json = planJSON(snapshot: nil, weeklyChange: 0.50, omitSnapshotKey: true)
        let plan = try decodePlan(json)

        XCTAssertNil(plan.inputSnapshot, "pre-upgrade cache has no input_snapshot key")
        XCTAssertNil(plan.snapshotGoal)
        XCTAssertFalse(
            plan.showsProjectedPace(draftGoal: .lose),
            "fallback: missing snapshot suppresses pace; do not use the live draft goal"
        )
        XCTAssertNil(plan.projectedPaceLabel(draftGoal: .lose, unitSystem: .metric))

        let cached = """
        {
          "plan": \(planJSON(snapshot: nil, weeklyChange: 0.50, omitSnapshotKey: true)),
          "input": \(snapshotJSON(goal: "lose", target: 80))
        }
        """
        let state = try planDecoder().decode(PlanCache.State.self, from: Data(cached.utf8))
        XCTAssertNil(state.plan.inputSnapshot)
        XCTAssertEqual(state.input.goal, .lose)
        XCTAssertFalse(state.plan.showsProjectedPace(draftGoal: state.input.goal))
    }

    // MARK: - N-02 pairing mismatches (legal on nutrition_plans.input_snapshot)

    func testSnapshotMaintainWithTarget80DraftMaintainOmitsPace() {
        let plan = makePlan(snapshotGoal: .maintain, targetWeightKG: 80, weeklyChange: 0)
        let draft = makeInput(goal: .maintain, targetWeightKG: nil)

        XCTAssertEqual(plan.snapshotGoal, .maintain)
        XCTAssertFalse(plan.showsProjectedPace(draftGoal: draft.goal))
        XCTAssertNil(plan.projectedPaceLabel(draftGoal: draft.goal, unitSystem: .metric))
    }

    func testSnapshotMaintainWithTargetPresentDraftLoseOmitsPace() {
        let plan = makePlan(snapshotGoal: .maintain, targetWeightKG: 80, weeklyChange: 0.004233)
        let draft = makeInput(goal: .lose, targetWeightKG: 80)

        XCTAssertEqual(plan.snapshotGoal, .maintain)
        XCTAssertNotEqual(plan.snapshotGoal, draft.goal)
        XCTAssertFalse(plan.showsProjectedPace(draftGoal: draft.goal))
        XCTAssertNil(plan.projectedPaceLabel(draftGoal: draft.goal, unitSystem: .metric))
    }

    func testSnapshotLoseWithMissingTargetDraftLoseUsesStoredPace() {
        let weeklyChange = 0.39
        let plan = makePlan(snapshotGoal: .lose, targetWeightKG: nil, weeklyChange: weeklyChange)
        let draft = makeInput(goal: .lose, targetWeightKG: nil)

        XCTAssertEqual(plan.snapshotGoal, .lose, "do not infer maintain from a missing target")
        XCTAssertTrue(plan.showsProjectedPace(draftGoal: draft.goal))
        XCTAssertEqual(
            plan.projectedPaceLabel(draftGoal: draft.goal, unitSystem: .metric),
            "0.39 kg per week"
        )
        XCTAssertEqual(plan.projectedWeeklyChangeKG, weeklyChange, accuracy: 0.0000001)
    }

    func testDecodeSucceedsForPairingMismatchesAndKeepsSnapshotGoal() throws {
        let maintainWithTarget = try decodePlan(
            planJSON(snapshot: snapshotJSON(goal: "maintain", target: 80), weeklyChange: 0)
        )
        XCTAssertEqual(maintainWithTarget.snapshotGoal, .maintain)
        XCTAssertEqual(maintainWithTarget.inputSnapshot?.targetWeightKG, 80)

        let maintainWithTargetDraftLose = try decodePlan(
            planJSON(snapshot: snapshotJSON(goal: "maintain", target: 72.5), weeklyChange: 0)
        )
        XCTAssertEqual(maintainWithTargetDraftLose.snapshotGoal, .maintain)
        XCTAssertEqual(maintainWithTargetDraftLose.inputSnapshot?.targetWeightKG, 72.5)

        let loseMissingTarget = try decodePlan(
            planJSON(snapshot: snapshotJSON(goal: "lose", target: nil), weeklyChange: 0.39)
        )
        XCTAssertEqual(loseMissingTarget.snapshotGoal, .lose)
        XCTAssertNil(loseMissingTarget.inputSnapshot?.targetWeightKG)
    }

    // MARK: - Fixtures

    private func makeInput(
        goal: WeightGoal,
        targetWeightKG: Double?,
        unitSystem: UnitSystem = .metric
    ) -> NutritionPlanInput {
        NutritionPlanInput(
            birthDate: calendar.date(from: DateComponents(year: 1996, month: 7, day: 1))!,
            calculationSex: .female,
            heightCM: 165,
            currentWeightKG: 65,
            targetWeightKG: targetWeightKG,
            activityLevel: .light,
            goal: goal,
            pace: .steady,
            unitSystem: unitSystem
        )
    }

    private func makePlan(
        snapshotGoal: WeightGoal,
        targetWeightKG: Double?,
        weeklyChange: Double
    ) -> NutritionPlan {
        NutritionPlan(
            id: UUID(),
            revision: 1,
            calculatorVersion: "msj-amdr-v1",
            bmrKcal: 1_400,
            tdeeKcal: 2_000,
            calorieTargetKcal: 2_000,
            proteinG: 90,
            carbohydrateG: 220,
            fatG: 70,
            projectedWeeklyChangeKG: weeklyChange,
            estimatedGoalDate: nil,
            createdAt: Date(timeIntervalSince1970: 1_753_790_400),
            inputSnapshot: makeInput(goal: snapshotGoal, targetWeightKG: targetWeightKG)
        )
    }

    private func snapshotJSON(goal: String, target: Double?) -> String {
        let targetField = target.map { String($0) } ?? "null"
        return """
        {
          "birth_date": "1996-07-01",
          "calculation_sex": "female",
          "height_cm": 165,
          "current_weight_kg": 65,
          "target_weight_kg": \(targetField),
          "activity_level": "light",
          "goal": "\(goal)",
          "pace": "steady",
          "unit_system": "metric"
        }
        """
    }

    private func planJSON(
        snapshot: String?,
        weeklyChange: Double,
        omitSnapshotKey: Bool = false,
        createdAt: String = "2026-07-29T12:00:00Z"
    ) -> String {
        var fields = """
          "id": "11111111-1111-1111-1111-111111111111",
          "revision": 1,
          "calculator_version": "msj-amdr-v1",
          "bmr_kcal": 1400,
          "tdee_kcal": 2000,
          "calorie_target_kcal": 2000,
          "protein_g": 90,
          "carbohydrate_g": 220,
          "fat_g": 70,
          "projected_weekly_change_kg": \(weeklyChange),
          "estimated_goal_date": null,
          "created_at": "\(createdAt)"
        """
        if !omitSnapshotKey {
            fields += ",\n          \"input_snapshot\": \(snapshot ?? "null")"
        }
        return "{\n\(fields)\n        }"
    }

    private func decodePlan(_ json: String) throws -> NutritionPlan {
        try planDecoder().decode(NutritionPlan.self, from: Data(json.utf8))
    }

    private func planDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = PlanService.dayFormatter.date(from: value) { return date }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: value) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid date: \(value)"
            )
        }
        return decoder
    }
}
