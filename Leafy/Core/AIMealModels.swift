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
    var estimatedGrams: Double?
    var calories: Int
    let calorieLow: Int
    let calorieHigh: Int
    let confidence: Double
    let assumptions: [String]
    var nutrients: [NutrientAmountInput]?
    var resolutionSource: String? = nil
    var foodVersionID: UUID? = nil
    var catalogEligible: Bool? = nil
    var nutritionBasis: String? = nil
    var marketCountry: String? = nil
    var sourceTitle: String? = nil
    var sourceURL: URL? = nil
    var sourceKind: String? = nil
    var exactSourceMatch: Bool? = nil
    var retrievedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, portion, calories, confidence, assumptions, nutrients
        case estimatedGrams = "estimated_grams"
        case calorieLow = "calorie_low"
        case calorieHigh = "calorie_high"
        case resolutionSource = "resolution_source"
        case foodVersionID = "food_version_id"
        case catalogEligible = "catalog_eligible"
        case nutritionBasis = "nutrition_basis"
        case marketCountry = "market_country"
        case sourceTitle = "source_title"
        case sourceURL = "source_url"
        case sourceKind = "source_kind"
        case exactSourceMatch = "exact_source_match"
        case retrievedAt = "retrieved_at"
    }

    var confidenceLabel: String {
        switch confidence {
        case 0.75...: "High confidence"
        case 0.5...: "Medium confidence"
        default: "Low confidence"
        }
    }

    var sourceLabel: String? {
        if let sourceTitle, !sourceTitle.isEmpty {
            let suffix = nutritionBasis == "official" ? "Official" : sourceKindLabel
            return suffix.map { "\(sourceTitle) · \($0)" } ?? sourceTitle
        }
        switch nutritionBasis ?? resolutionSource {
        case "usda": return "USDA"
        case "leafy_catalog": return "Leafy catalog"
        default: return nil
        }
    }

    private var sourceKindLabel: String? {
        switch sourceKind {
        case "restaurant", "manufacturer": return "Official"
        case "usda": return "USDA"
        case "database": return "Nutrition database"
        case "retailer": return "Retailer"
        default: return nil
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
    let marketCountry: String
}

struct MealConfirmationItem: Encodable, Equatable, Sendable {
    let id: UUID
    let name: String
    let portion: String
    let calories: Int
    let estimatedGrams: Double?
    let nutrients: [NutrientAmountInput]

    enum CodingKeys: String, CodingKey {
        case id, name, portion, calories, nutrients
        case estimatedGrams = "estimated_grams"
    }
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
