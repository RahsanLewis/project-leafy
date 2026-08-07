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

struct NutritionChatMessage: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let role: String
    let content: String
    let sources: [NutritionChatSource]
    let suggestedLogDescription: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content, sources
        case suggestedLogDescription = "suggested_log_description"
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
