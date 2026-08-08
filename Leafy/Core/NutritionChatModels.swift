import Foundation

struct NutritionChatThread: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let lastMessageAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
    }
}

struct NutritionChatSource: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(kind):\(label)" }
    let kind: String
    let label: String
}

enum NutritionChatMealStatus: String, Codable, Equatable, Sendable {
    case ready
    case logged
    case unavailable
}

struct NutritionChatMealSuggestion: Codable, Equatable, Sendable {
    let sessionID: UUID
    var status: NutritionChatMealStatus
    let totalCalories: Int
    let calorieLow: Int
    let calorieHigh: Int
    let confidence: Double
    let assumptions: [String]
    var items: [MealEstimateItem]

    enum CodingKeys: String, CodingKey {
        case status, confidence, assumptions, items
        case sessionID = "session_id"
        case totalCalories = "total_calories"
        case calorieLow = "calorie_low"
        case calorieHigh = "calorie_high"
    }

    var reviewedTotal: Int { items.reduce(0) { $0 + $1.calories } }
}

struct NutritionChatMessage: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let role: String
    let content: String
    let sources: [NutritionChatSource]
    let suggestedLogDescription: String?
    var mealSuggestion: NutritionChatMealSuggestion? = nil
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content, sources
        case suggestedLogDescription = "suggested_log_description"
        case mealSuggestion = "meal_suggestion"
        case createdAt = "created_at"
    }
}

struct NutritionChatThreadListResponse: Codable, Sendable { let threads: [NutritionChatThread] }
struct NutritionChatLoadResponse: Codable, Sendable {
    let thread: NutritionChatThread
    let messages: [NutritionChatMessage]
}
struct NutritionChatSendResponse: Codable, Sendable {
    let thread: NutritionChatThread
    let userMessage: NutritionChatMessage
    let assistantMessage: NutritionChatMessage

    enum CodingKeys: String, CodingKey {
        case thread
        case userMessage = "user_message"
        case assistantMessage = "assistant_message"
    }
}
