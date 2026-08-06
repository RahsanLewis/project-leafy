import XCTest
@testable import Leafy

final class AIMealModelsTests: XCTestCase {
    func testReviewedTotalUsesUserEditedItemCalories() {
        let estimate = MealEstimate(
            sessionID: UUID(), status: .ready, totalCalories: 500,
            calorieLow: 400, calorieHigh: 650, confidence: 0.7, assumptions: [],
            items: [item(calories: 280), item(calories: 330)], followUp: nil
        )
        XCTAssertEqual(estimate.reviewedTotal, 610)
    }

    func testConfidenceLabelsAreHumanReadable() {
        XCTAssertEqual(item(calories: 100, confidence: 0.8).confidenceLabel, "High confidence")
        XCTAssertEqual(item(calories: 100, confidence: 0.6).confidenceLabel, "Medium confidence")
        XCTAssertEqual(item(calories: 100, confidence: 0.3).confidenceLabel, "Low confidence")
    }

    func testMealEstimateDecodesStructuredServerResponse() throws {
        let json = """
        {"session_id":"A7C9D51F-C3B4-44E0-B3D9-F41EAAF71D5A","status":"needs_clarification","total_calories":520,"calorie_low":410,"calorie_high":690,"confidence":0.62,"assumptions":["Light oil"],"items":[{"id":"D27DC6DA-CC10-4E55-9CC0-A017C9345521","name":"Chicken","portion":"one breast","estimated_grams":170,"calories":280,"calorie_low":240,"calorie_high":340,"confidence":0.8,"assumptions":[]}],"follow_up":{"id":"47DC0199-6EBF-4B37-B7D9-AEC297A031DD","ordinal":1,"question":"Was oil added?"}}
        """
        let value = try JSONDecoder().decode(MealEstimate.self, from: Data(json.utf8))
        XCTAssertEqual(value.status, .needsClarification)
        XCTAssertEqual(value.followUp?.question, "Was oil added?")
        XCTAssertEqual(value.items.first?.estimatedGrams, 170)
    }

    private func item(calories: Int, confidence: Double = 0.7) -> MealEstimateItem {
        MealEstimateItem(
            id: UUID(), name: "Food", portion: "one serving", estimatedGrams: nil,
            calories: calories, calorieLow: max(0, calories - 50), calorieHigh: calories + 50,
            confidence: confidence, assumptions: []
        )
    }
}
