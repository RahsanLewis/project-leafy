import XCTest
@testable import Leafy

final class PlanCacheDateOnlyTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
    private let honolulu = TimeZone(identifier: "Pacific/Honolulu")!
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    func testV1MigratesToV2UsingDisplayedLocalCivilDate() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try v1PlanJSON(birthInstant: "1990-07-29T10:00:00Z", estimatedInstant: "2027-02-19T12:00:00Z")
            .write(to: url, atomically: true, encoding: .utf8)

        let cache = PlanCache(fileURL: url)
        let migrated = await cache.load(timeZone: newYork)
        let state = try XCTUnwrap(migrated)
        XCTAssertEqual(state.input.birthDate, try LocalDate(year: 1990, month: 7, day: 29) as LocalDate?)
        XCTAssertEqual(state.plan.estimatedGoalDate, try LocalDate(year: 2027, month: 2, day: 19))
        XCTAssertEqual(state.plan.calorieTargetKcal, 1840)

        let rewritten = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(rewritten.contains("\"version\":2") || rewritten.contains("\"version\": 2"))
        XCTAssertTrue(rewritten.contains("\"1990-07-29\""))
        XCTAssertTrue(rewritten.contains("\"2027-02-19\""))
        XCTAssertFalse(rewritten.contains("1990-07-29T"))
    }

    func testV2RoundTripsCivilYMD() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = PlanCache(fileURL: url)
        let input = try maintainInput(birth: LocalDate(year: 1990, month: 7, day: 29))
        let plan = try NutritionCalculator.calculate(
            input: input,
            now: ISO8601DateFormatter().date(from: "2026-07-29T12:00:00Z")!
        )
        try await cache.save(plan, input: input)

        let loadedState = await cache.load(timeZone: honolulu)
        let loaded = try XCTUnwrap(loadedState)
        XCTAssertEqual(loaded.input.birthDate, try LocalDate(year: 1990, month: 7, day: 29) as LocalDate?)
        XCTAssertEqual(loaded.plan.estimatedGoalDate, plan.estimatedGoalDate)
        XCTAssertEqual(loaded.plan.calorieTargetKcal, plan.calorieTargetKcal)
        XCTAssertEqual(loaded.plan.proteinG, plan.proteinG)
        XCTAssertEqual(loaded.plan.createdAt, plan.createdAt)
    }

    func testTimezoneChangeDoesNotRecomputeCachedPlan() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = PlanCache(fileURL: url)
        let input = try maintainInput(birth: LocalDate(year: 1990, month: 7, day: 29))
        let plan = try NutritionCalculator.calculate(
            input: input,
            now: ISO8601DateFormatter().date(from: "2026-07-29T12:00:00Z")!
        )
        try await cache.save(plan, input: input)

        for timeZone in [utc, newYork, losAngeles, kiritimati, honolulu] {
            let loadedState = await cache.load(timeZone: timeZone)
            let loaded = try XCTUnwrap(loadedState)
            XCTAssertEqual(loaded.plan.bmrKcal, plan.bmrKcal, timeZone.identifier)
            XCTAssertEqual(loaded.plan.tdeeKcal, plan.tdeeKcal)
            XCTAssertEqual(loaded.plan.calorieTargetKcal, plan.calorieTargetKcal)
            XCTAssertEqual(loaded.plan.proteinG, plan.proteinG)
            XCTAssertEqual(loaded.plan.carbohydrateG, plan.carbohydrateG)
            XCTAssertEqual(loaded.plan.fatG, plan.fatG)
            XCTAssertEqual(loaded.input.birthDate, input.birthDate)
        }
    }

    func testCorruptPlanCacheIsDroppedWithoutCrashing() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let cache = PlanCache(fileURL: url)
        let dropped = await cache.load(timeZone: utc)
        XCTAssertNil(dropped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPendingV1RequiresBirthDateConfirmation() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try v1PendingJSON(birthInstant: "1990-07-29T10:00:00Z")
            .write(to: url, atomically: true, encoding: .utf8)

        let cache = PendingOnboardingCache(fileURL: url)
        let pending = await cache.load(timeZone: newYork)
        let state = try XCTUnwrap(pending)
        XCTAssertTrue(state.requiresBirthDateConfirmation)
        XCTAssertEqual(state.stepID, OnboardingDraft.Step.birthDate.rawValue)
        XCTAssertTrue(state.termsAccepted)
        XCTAssertTrue(state.privacyAccepted)
        XCTAssertEqual(state.input?.birthDate, try LocalDate(year: 1990, month: 7, day: 29) as LocalDate?)
    }

    func testPendingV2RoundTripAndConfirmationFlag() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = PendingOnboardingCache(fileURL: url)
        let original = PendingOnboardingState(
            input: try maintainInput(birth: LocalDate(year: 1976, month: 7, day: 1)),
            stepID: OnboardingDraft.Step.results.rawValue,
            termsAccepted: true,
            privacyAccepted: true,
            coreDataAccepted: true,
            requiresBirthDateConfirmation: false
        )
        try await cache.save(original)
        let loadedState = await cache.load(timeZone: kiritimati)
        let loaded = try XCTUnwrap(loadedState)
        XCTAssertEqual(loaded.input?.birthDate, try LocalDate(year: 1976, month: 7, day: 1) as LocalDate?)
        XCTAssertFalse(loaded.requiresBirthDateConfirmation)
        XCTAssertEqual(loaded.stepID, OnboardingDraft.Step.results.rawValue)

        let unconfirmed = PendingOnboardingState(
            input: original.input,
            stepID: OnboardingDraft.Step.birthDate.rawValue,
            termsAccepted: true,
            privacyAccepted: true,
            coreDataAccepted: true,
            requiresBirthDateConfirmation: true
        )
        try await cache.save(unconfirmed)
        let flaggedState = await cache.load(timeZone: honolulu)
        let flagged = try XCTUnwrap(flaggedState)
        XCTAssertTrue(flagged.requiresBirthDateConfirmation)
        XCTAssertEqual(flagged.stepID, OnboardingDraft.Step.birthDate.rawValue)
    }

    @MainActor
    func testPendingMalformedDateKeepsConsentsAndRequiresReentry() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        {
          "input": { "birth_date": "not-a-date" },
          "stepID": "results",
          "termsAccepted": true,
          "privacyAccepted": false,
          "coreDataAccepted": true
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let cache = PendingOnboardingCache(fileURL: url)
        let recovered = await cache.load(timeZone: utc)
        let state = try XCTUnwrap(recovered)
        XCTAssertTrue(state.requiresBirthDateConfirmation)
        XCTAssertEqual(state.stepID, OnboardingDraft.Step.birthDate.rawValue)
        XCTAssertTrue(state.termsAccepted)
        XCTAssertFalse(state.privacyAccepted)
        XCTAssertTrue(state.coreDataAccepted)
        XCTAssertNil(state.input)
        XCTAssertNil(state.input?.birthDate)
        XCTAssertNotEqual(state.input?.birthDate, LocalDate.yearsBeforeNow(30, timeZone: utc) as LocalDate?)

        let app = AppCoordinator()
        app.applyPendingOnboarding(state)
        XCTAssertTrue(app.requiresBirthDateConfirmation)
        XCTAssertEqual(app.draft.step, .birthDate)
        XCTAssertFalse(app.draft.birthDateChosen)
        XCTAssertNil(app.draft.input.birthDate)

        app.confirmOnboardingBirthDate()
        XCTAssertTrue(app.requiresBirthDateConfirmation)
        XCTAssertFalse(app.calculatePreview())
        XCTAssertNil(app.preview)

        app.draft.selectBirthDate(try LocalDate(year: 1994, month: 3, day: 15))
        app.confirmOnboardingBirthDate()
        XCTAssertFalse(app.requiresBirthDateConfirmation)
        XCTAssertEqual(app.draft.input.birthDate, try LocalDate(year: 1994, month: 3, day: 15) as LocalDate?)
        XCTAssertTrue(app.calculatePreview())
    }

    @MainActor
    func testPendingUndecodableBirthInstantDoesNotInventDate() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try v1PendingJSON(birthInstant: "not-a-date")
            .write(to: url, atomically: true, encoding: .utf8)

        let cache = PendingOnboardingCache(fileURL: url)
        let recovered = await cache.load(timeZone: utc)
        let state = try XCTUnwrap(recovered)
        XCTAssertTrue(state.requiresBirthDateConfirmation)
        XCTAssertEqual(state.stepID, OnboardingDraft.Step.birthDate.rawValue)
        XCTAssertTrue(state.termsAccepted)
        XCTAssertTrue(state.privacyAccepted)
        XCTAssertNil(state.input?.birthDate)
        XCTAssertEqual(state.input?.heightCM, 165)
        XCTAssertEqual(state.input?.currentWeightKG, 65)
        XCTAssertNotEqual(state.input?.birthDate, LocalDate.yearsBeforeNow(30, timeZone: utc) as LocalDate?)

        let app = AppCoordinator()
        app.applyPendingOnboarding(state)
        app.confirmOnboardingBirthDate()
        XCTAssertTrue(app.requiresBirthDateConfirmation)
        XCTAssertFalse(app.calculatePreview())
        XCTAssertNil(app.preview)

        app.draft.selectBirthDate(try LocalDate(year: 1988, month: 11, day: 2))
        app.confirmOnboardingBirthDate()
        XCTAssertFalse(app.requiresBirthDateConfirmation)
        XCTAssertTrue(app.calculatePreview())
    }

    @MainActor
    func testPendingDisplayedMigrationAllowsConfirmWithoutPickerChange() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try v1PendingJSON(birthInstant: "1990-07-29T10:00:00Z")
            .write(to: url, atomically: true, encoding: .utf8)

        let cache = PendingOnboardingCache(fileURL: url)
        let pending = await cache.load(timeZone: newYork)
        let state = try XCTUnwrap(pending)
        XCTAssertEqual(state.input?.birthDate, try LocalDate(year: 1990, month: 7, day: 29) as LocalDate?)
        XCTAssertTrue(state.requiresBirthDateConfirmation)

        let app = AppCoordinator()
        app.applyPendingOnboarding(state)
        XCTAssertTrue(app.draft.birthDateChosen)
        XCTAssertEqual(app.draft.input.birthDate, try LocalDate(year: 1990, month: 7, day: 29) as LocalDate?)

        app.confirmOnboardingBirthDate()
        XCTAssertFalse(app.requiresBirthDateConfirmation)
        XCTAssertTrue(app.calculatePreview())
    }

    private func maintainInput(birth: LocalDate) -> NutritionPlanInput {
        NutritionPlanInput(
            birthDate: birth,
            calculationSex: .female, heightCM: 165, currentWeightKG: 65, targetWeightKG: nil,
            activityLevel: .light, goal: .maintain, pace: .steady, unitSystem: .metric
        )
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "leafy-021-\(UUID().uuidString).json")
    }

    private func v1PlanJSON(birthInstant: String, estimatedInstant: String) -> String {
        """
        {
          "plan": {
            "id": "11111111-1111-1111-1111-111111111111",
            "revision": 1,
            "calculator_version": "msj-amdr-v1",
            "bmr_kcal": 1340,
            "tdee_kcal": 1843,
            "calorie_target_kcal": 1840,
            "protein_g": 78,
            "carbohydrate_g": 244,
            "fat_g": 61,
            "projected_weekly_change_kg": 0,
            "estimated_goal_date": "\(estimatedInstant)",
            "created_at": "2026-07-29T12:00:00Z"
          },
          "input": {
            "birth_date": "\(birthInstant)",
            "calculation_sex": "female",
            "height_cm": 165,
            "current_weight_kg": 65,
            "target_weight_kg": null,
            "activity_level": "light",
            "goal": "maintain",
            "pace": "steady",
            "unit_system": "metric"
          }
        }
        """
    }

    private func v1PendingJSON(birthInstant: String) -> String {
        """
        {
          "input": {
            "birth_date": "\(birthInstant)",
            "calculation_sex": "female",
            "height_cm": 165,
            "current_weight_kg": 65,
            "target_weight_kg": null,
            "activity_level": "light",
            "goal": "maintain",
            "pace": "steady",
            "unit_system": "metric"
          },
          "stepID": "results",
          "termsAccepted": true,
          "privacyAccepted": true,
          "coreDataAccepted": false
        }
        """
    }
}
