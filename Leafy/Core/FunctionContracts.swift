import Foundation

enum FunctionContracts {
    struct SaveNutritionPlan: Codable, Sendable {
        let birthDate: String
        let calculationSex: String
        let heightCM: Double
        let currentWeightKG: Double
        let targetWeightKG: Double?
        let activityLevel: String
        let goal: String
        let pace: String
        let unitSystem: String
        enum CodingKeys: String, CodingKey {
            case birthDate = "birth_date", calculationSex = "calculation_sex"
            case heightCM = "height_cm", currentWeightKG = "current_weight_kg"
            case targetWeightKG = "target_weight_kg", activityLevel = "activity_level"
            case goal, pace, unitSystem = "unit_system"
        }
    }
    struct ActionVersion: Codable, Sendable { let action: String; let version: Int }
    struct LocalDate: Codable, Sendable {
        let localDate: String
        enum CodingKeys: String, CodingKey { case localDate = "local_date" }
    }
    struct ActionAdjustment: Codable, Sendable {
        let action: String; let adjustmentID: UUID
        enum CodingKeys: String, CodingKey { case action; case adjustmentID = "adjustment_id" }
    }
    struct ActionID: Codable, Sendable { let action: String; let id: UUID }
    struct ActionQuery: Codable, Sendable { let action: String; let query: String }
    struct ActionOnly: Codable, Sendable { let action: String }
    struct ActionRequestID: Codable, Sendable {
        let action: String; let requestID: UUID
        enum CodingKeys: String, CodingKey { case action; case requestID = "request_id" }
    }
    struct ActionSessionID: Codable, Sendable {
        let action: String; let sessionID: UUID
        enum CodingKeys: String, CodingKey { case action; case sessionID = "session_id" }
    }
    struct DeleteAccount: Codable, Sendable {
        let appleAuthorizationCode: String?
        enum CodingKeys: String, CodingKey { case appleAuthorizationCode = "apple_authorization_code" }
    }
}
