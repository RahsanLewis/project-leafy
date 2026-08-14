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

    func testChatMessageDecodesInlineMealSuggestion() throws {
        let json = """
        {"id":"A7C9D51F-C3B4-44E0-B3D9-F41EAAF71D5A","role":"assistant","content":"Here’s an estimate.","sources":[],"suggested_log_description":null,"meal_suggestion":{"session_id":"47DC0199-6EBF-4B37-B7D9-AEC297A031DD","status":"ready","total_calories":520,"calorie_low":410,"calorie_high":690,"confidence":0.62,"assumptions":[],"items":[{"id":"D27DC6DA-CC10-4E55-9CC0-A017C9345521","name":"Chicken","portion":"one breast","estimated_grams":170,"calories":280,"calorie_low":240,"calorie_high":340,"confidence":0.8,"assumptions":[],"nutrients":[{"code":"protein_g","amount":45,"confidence":0.8}]}]},"created_at":"2026-08-07T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(NutritionChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.mealSuggestion?.status, .ready)
        XCTAssertEqual(message.mealSuggestion?.reviewedTotal, 280)
        XCTAssertEqual(message.mealSuggestion?.items.first?.nutrients?.first?.code, "protein_g")
    }

    func testChatMealReviewedTotalUsesEdits() {
        var suggestion = NutritionChatMealSuggestion(
            sessionID: UUID(), status: .ready, totalCalories: 500,
            calorieLow: 400, calorieHigh: 650, confidence: 0.7,
            assumptions: [], items: [item(calories: 280), item(calories: 330)]
        )
        suggestion.items[0].calories = 300
        XCTAssertEqual(suggestion.reviewedTotal, 630)
    }

    func testChatMealReviewSupportsPredictedAndUserAddedItems() {
        let prediction = item(calories: 280)
        var draft = ChatMealReviewDraft(
            messageID: UUID(), sessionID: UUID(),
            items: [ChatMealReviewItem(prediction: prediction)], consumedAt: .now
        )
        draft.items.append(ChatMealReviewItem(name: "Avocado", portion: "half", calories: 120))

        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.totalCalories, 400)
        XCTAssertEqual(draft.items[0].origin, .prediction)
        XCTAssertEqual(draft.items[1].origin, .userAdded)
        XCTAssertNil(draft.items[1].predictionID)
    }

    func testChatMealReviewRejectsIncompleteAddedFood() {
        let draft = ChatMealReviewDraft(
            messageID: UUID(), sessionID: UUID(),
            items: [ChatMealReviewItem(name: "", portion: "one", calories: 100)], consumedAt: .now
        )
        XCTAssertFalse(draft.isValid)
    }

    private func item(calories: Int, confidence: Double = 0.7) -> MealEstimateItem {
        MealEstimateItem(
            id: UUID(), name: "Food", portion: "one serving", estimatedGrams: nil,
            calories: calories, calorieLow: max(0, calories - 50), calorieHigh: calories + 50,
            confidence: confidence, assumptions: []
        )
    }
}

final class AIMealWaitEstimatorTests: XCTestCase {
    func testUsesModalitySpecificDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertEqual(AIMealWaitEstimator.estimatedSeconds(hasPhoto: false, defaults: defaults), 12)
        XCTAssertEqual(AIMealWaitEstimator.estimatedSeconds(hasPhoto: true, defaults: defaults), 20)
    }

    func testRecordedTimingUsesRollingAverageAndClamp() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        AIMealWaitEstimator.record(22, hasPhoto: false, defaults: defaults)
        XCTAssertEqual(AIMealWaitEstimator.estimatedSeconds(hasPhoto: false, defaults: defaults), 15, accuracy: 0.001)
        AIMealWaitEstimator.record(500, hasPhoto: true, defaults: defaults)
        XCTAssertEqual(AIMealWaitEstimator.estimatedSeconds(hasPhoto: true, defaults: defaults), 45)
    }
}
