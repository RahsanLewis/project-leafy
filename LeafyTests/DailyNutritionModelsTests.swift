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
