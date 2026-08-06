import Foundation

struct FoodEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    var name: String
    var calories: Int
    var consumedAt: Date
    let localDate: String
    let timeZone: String
    let createdAt: Date
    var updatedAt: Date
    var amount: Double? = nil
    var amountUnit: String? = nil
    var gramWeight: Double? = nil
    var portionDescription: String? = nil
    var mealType: MealType = .unspecified
    var confidence: Double? = nil
    var userConfirmed: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, calories
        case userID = "user_id"
        case consumedAt = "consumed_at"
        case localDate = "local_date"
        case timeZone = "time_zone"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case amount
        case amountUnit = "amount_unit"
        case gramWeight = "gram_weight"
        case portionDescription = "portion_description"
        case mealType = "meal_type"
        case confidence
        case userConfirmed = "user_confirmed"
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack, drink, supplement, unspecified

    var id: String { rawValue }
    var label: String { rawValue == "unspecified" ? "Not specified" : rawValue.capitalized }
}

struct FoodEntryInput: Equatable, Sendable {
    var name: String
    var calories: Int
    var consumedAt: Date
    var amount: Double? = nil
    var amountUnit: String? = nil
    var gramWeight: Double? = nil
    var portionDescription: String? = nil
    var mealType: MealType = .unspecified

    var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !normalizedName.isEmpty && normalizedName.count <= 120 && (1...10_000).contains(calories) }
}

struct DataContributionDocument: Codable, Equatable, Sendable {
    let title: String
    let body: String
    let version: Int
}

struct DataContributionGrant: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let purpose: String
    let jurisdictionCountry: String
    let jurisdictionRegion: String?
    let dataScopes: [String]
    let grantedAt: Date
    let expiresAt: Date?
    let revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, purpose
        case jurisdictionCountry = "jurisdiction_country"
        case jurisdictionRegion = "jurisdiction_region"
        case dataScopes = "data_scopes"
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
    }
}

struct DataContributionStatus: Codable, Equatable, Sendable {
    let isParticipating: Bool
    let grant: DataContributionGrant?
    let document: DataContributionDocument?

    enum CodingKeys: String, CodingKey {
        case isParticipating = "is_participating"
        case grant, document
    }
}

enum IntakeDayStatus: String, Codable, Sendable {
    case pending, confirmed, incomplete, fasted
}

struct DailyIntakeDay: Codable, Equatable, Sendable {
    let userID: UUID
    let localDate: Date
    let status: IntakeDayStatus
    let confirmedCalories: Int?
    let confirmedItemCount: Int?
    let timeZone: String
    let revision: Int
    let confirmedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status, revision
        case userID = "user_id"
        case localDate = "local_date"
        case confirmedCalories = "confirmed_calories"
        case confirmedItemCount = "confirmed_item_count"
        case timeZone = "time_zone"
        case confirmedAt = "confirmed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PlanAdjustmentNotice: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let planID: UUID
    let energyEstimateID: UUID
    let previousCalorieTargetKcal: Int
    let newCalorieTargetKcal: Int
    let explanation: String
    let appliedAt: Date
    let acknowledgedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, explanation
        case userID = "user_id"
        case planID = "plan_id"
        case energyEstimateID = "energy_estimate_id"
        case previousCalorieTargetKcal = "previous_calorie_target_kcal"
        case newCalorieTargetKcal = "new_calorie_target_kcal"
        case appliedAt = "applied_at"
        case acknowledgedAt = "acknowledged_at"
    }
}

struct DailyCheckInResponse: Codable, Sendable {
    let day: DailyIntakeDay?
    let adaptiveOutcome: String
    let plan: NutritionPlan?
    let adjustment: PlanAdjustmentNotice?

    enum CodingKeys: String, CodingKey {
        case day, plan, adjustment
        case adaptiveOutcome = "adaptive_outcome"
    }
}

struct MorningCheckIn: Equatable, Sendable {
    let reviewDate: Date
    let entries: [FoodEntry]
    let intakeDay: DailyIntakeDay?
    let todayWeight: WeightEntry?

    var needsIntakeReview: Bool {
        guard let intakeDay else { return true }
        return intakeDay.status == .pending
    }

    var needsWeight: Bool { todayWeight == nil }
    var calorieTotal: Int { entries.reduce(0) { $0 + $1.calories } }
}

struct DailyCalorieSummary: Equatable, Sendable {
    let budget: Int?
    let consumed: Int

    init(budget: Int?, entries: [FoodEntry]) {
        self.budget = budget
        consumed = entries.reduce(0) { $0 + $1.calories }
    }

    var remaining: Int? { budget.map { $0 - consumed } }
    var overage: Int { max(0, consumed - (budget ?? consumed)) }
    var isOverBudget: Bool { guard let budget else { return false }; return consumed > budget }
    var progress: Double {
        guard let budget, budget > 0 else { return 0 }
        return min(max(Double(consumed) / Double(budget), 0), 1)
    }
}
