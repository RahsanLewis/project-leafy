import Foundation

enum MealEstimateStatus: String, Codable, Sendable {
    case needsClarification = "needs_clarification"
    case ready
}

struct MealFollowUp: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let ordinal: Int
    let question: String
}

struct MealEstimateItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var portion: String
    let estimatedGrams: Double?
    var calories: Int
    let calorieLow: Int
    let calorieHigh: Int
    let confidence: Double
    let assumptions: [String]
    var nutrients: [NutrientAmountInput]?

    enum CodingKeys: String, CodingKey {
        case id, name, portion, calories, confidence, assumptions, nutrients
        case estimatedGrams = "estimated_grams"
        case calorieLow = "calorie_low"
        case calorieHigh = "calorie_high"
    }

    var confidenceLabel: String {
        switch confidence {
        case 0.75...: "High confidence"
        case 0.5...: "Medium confidence"
        default: "Low confidence"
        }
    }
}

struct MealEstimate: Codable, Equatable, Sendable {
    let sessionID: UUID
    let status: MealEstimateStatus
    let totalCalories: Int
    let calorieLow: Int
    let calorieHigh: Int
    let confidence: Double
    let assumptions: [String]
    var items: [MealEstimateItem]
    let followUp: MealFollowUp?

    enum CodingKeys: String, CodingKey {
        case status, confidence, assumptions, items
        case sessionID = "session_id"
        case totalCalories = "total_calories"
        case calorieLow = "calorie_low"
        case calorieHigh = "calorie_high"
        case followUp = "follow_up"
    }

    var reviewedTotal: Int { items.reduce(0) { $0 + $1.calories } }
}

struct MealEstimateInput: Sendable {
    let sessionID: UUID
    let description: String
    let consumedAt: Date
    let localDate: Date
    let mealType: MealType
}

struct MealConfirmationItem: Encodable, Equatable, Sendable {
    let id: UUID
    let name: String
    let portion: String
    let calories: Int
    let nutrients: [NutrientAmountInput]
}

struct MealConfirmationResponse: Codable, Sendable { let entries: [FoodEntry] }

struct ChatMealConfirmationItem: Equatable, Sendable {
    let clientItemID: UUID
    let predictionID: UUID?
    let name: String
    let portion: String
    let calories: Int
    let nutrients: [NutrientAmountInput]
    let origin: ChatMealReviewOrigin
}
