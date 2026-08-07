import XCTest
@testable import Leafy

final class DailyNutritionModelsTests: XCTestCase {
    func testSummaryTreatsCaloriesLikeABudget() {
        let summary = DailyCalorieSummary(budget: 2_000, entries: [entry(calories: 420), entry(calories: 380)])

        XCTAssertEqual(summary.consumed, 800)
        XCTAssertEqual(summary.remaining, 1_200)
        XCTAssertFalse(summary.isOverBudget)
        XCTAssertEqual(summary.progress, 0.4, accuracy: 0.001)
    }

    func testSummaryReportsOverageAndClampsRing() {
        let summary = DailyCalorieSummary(budget: 1_800, entries: [entry(calories: 2_050)])

        XCTAssertEqual(summary.remaining, -250)
        XCTAssertEqual(summary.overage, 250)
        XCTAssertTrue(summary.isOverBudget)
        XCTAssertEqual(summary.progress, 1)
    }

    func testSummaryHandlesMissingHistoricalBudget() {
        let summary = DailyCalorieSummary(budget: nil, entries: [entry(calories: 300)])

        XCTAssertEqual(summary.consumed, 300)
        XCTAssertNil(summary.remaining)
        XCTAssertEqual(summary.progress, 0)
    }

    func testFoodEntryInputValidation() {
        XCTAssertTrue(FoodEntryInput(name: "Greek yogurt", calories: 140, consumedAt: .now).isValid)
        XCTAssertFalse(FoodEntryInput(name: "   ", calories: 140, consumedAt: .now).isValid)
        XCTAssertFalse(FoodEntryInput(name: "Food", calories: 0, consumedAt: .now).isValid)
        XCTAssertFalse(FoodEntryInput(name: "Food", calories: 10_001, consumedAt: .now).isValid)
    }

    func testFoodEntryInputCarriesOptionalServingProvenance() {
        let input = FoodEntryInput(
            name: "Greek yogurt", calories: 140, consumedAt: .now,
            amount: 170, amountUnit: "g", gramWeight: 170,
            portionDescription: "170 g", mealType: .breakfast
        )

        XCTAssertTrue(input.isValid)
        XCTAssertEqual(input.gramWeight, 170)
        XCTAssertEqual(input.mealType, .breakfast)
    }

    func testNutrientProgressUsesReferenceTarget() {
        let nutrient = DailyNutrient(
            code: "protein_g", name: "Protein", unit: "g", nutrientClass: "macro",
            displayOrder: 10, targetKind: .goal, amount: 75, targetAmount: 100,
            percentOfTarget: 0.75, coverage: 0.9, estimatedAmount: 25,
            verifiedAmount: 50, confidence: 0.8
        )

        XCTAssertEqual(nutrient.progress, 0.75, accuracy: 0.001)
        XCTAssertTrue(nutrient.hasSufficientCoverage)
    }

    func testLimitNutrientDoesNotReportRemainingAsAGoal() {
        let nutrient = DailyNutrient(
            code: "sodium_mg", name: "Sodium", unit: "mg", nutrientClass: "mineral",
            displayOrder: 230, targetKind: .limit, amount: 2_400, targetAmount: 2_300,
            percentOfTarget: 2400.0 / 2300.0, coverage: 1, estimatedAmount: 0,
            verifiedAmount: 2_400, confidence: nil
        )

        XCTAssertEqual(nutrient.progress, 1)
        XCTAssertGreaterThan(nutrient.percentOfTarget ?? 0, 1)
    }

    func testFoodEntryDecodesLinkedCatalogVersion() throws {
        let versionID = UUID(uuidString: "FCE5542D-F6AA-44DA-A61B-A254B823A72A")!
        let json = """
        {
          "id":"52A16EE5-22DB-47EB-81D5-D9FA231D0D5B",
          "user_id":"D11C9E3C-043E-46F3-BA7C-FD4C7030CB99",
          "name":"Greek yogurt",
          "calories":140,
          "consumed_at":"2026-08-07T12:00:00Z",
          "local_date":"2026-08-07",
          "time_zone":"America/New_York",
          "meal_type":"unspecified",
          "user_confirmed":false,
          "created_at":"2026-08-07T12:00:00Z",
          "updated_at":"2026-08-07T12:00:00Z",
          "canonical_food_version_id":"\(versionID.uuidString)"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(FoodEntry.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.canonicalFoodVersionID, versionID)
    }

    private func entry(calories: Int) -> FoodEntry {
        FoodEntry(
            id: UUID(),
            userID: UUID(),
            name: "Test food",
            calories: calories,
            consumedAt: .now,
            localDate: "2026-08-01",
            timeZone: "America/New_York",
            createdAt: .now,
            updatedAt: .now
        )
    }
}

final class MorningCheckInModelTests: XCTestCase {
    func testPendingOrMissingDayRequiresReview() {
        let state = MorningCheckIn(reviewDate: .now, entries: [], intakeDay: nil, todayWeight: nil)
        XCTAssertTrue(state.needsIntakeReview)
        XCTAssertTrue(state.needsWeight)
    }

    func testConfirmedDayDoesNotRequireReview() {
        let now = Date()
        let day = DailyIntakeDay(
            userID: UUID(), localDate: now, status: .confirmed,
            confirmedCalories: 1_800, confirmedItemCount: 4, timeZone: "America/New_York",
            revision: 1, confirmedAt: now, createdAt: now, updatedAt: now
        )
        let state = MorningCheckIn(reviewDate: now, entries: [], intakeDay: day, todayWeight: nil)
        XCTAssertFalse(state.needsIntakeReview)
    }
}
