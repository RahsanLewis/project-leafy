import Foundation

struct FoodEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
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
    var occasionID: UUID? = nil
    var entrySource: String? = nil
    var calorieMethod: String? = nil
    var canonicalFoodVersionID: UUID? = nil
    var score: ProductNutritionScore? = nil

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
        case occasionID = "occasion_id"
        case entrySource = "entry_source"
        case calorieMethod = "calorie_method"
        case canonicalFoodVersionID = "canonical_food_version_id"
        case score
    }

    var isAIEstimate: Bool { entrySource == "photo_ai" || entrySource == "text_ai" }
}

enum MealType: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
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
    var nutrients: [NutrientAmountInput] = []

    var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !normalizedName.isEmpty && normalizedName.count <= 120 && (0...10_000).contains(calories) }
}

enum NutrientTargetKind: String, Codable, Sendable { case goal, limit, informational }
enum NutrientUpperLimitScope: String, Codable, Sendable {
    case total
    case preformedOnly = "preformed_only"
    case syntheticOnly = "synthetic_only"
    case supplementalOnly = "supplemental_only"
}
enum NutrientDerivationMethod: String, Codable, Sendable {
    case laboratory, label, calculated, estimated
    case userEntered = "user_entered"
}

struct NutrientAmountInput: Codable, Equatable, Hashable, Identifiable, Sendable {
    var code: String
    var amount: Double
    var derivationMethod: NutrientDerivationMethod = .userEntered
    var sourceVersion: String? = nil
    var confidence: Double? = nil
    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, amount, confidence
        case derivationMethod = "derivation_method"
        case sourceVersion = "source_version"
    }

    init(
        code: String,
        amount: Double,
        derivationMethod: NutrientDerivationMethod = .userEntered,
        sourceVersion: String? = nil,
        confidence: Double? = nil
    ) {
        self.code = code
        self.amount = amount
        self.derivationMethod = derivationMethod
        self.sourceVersion = sourceVersion
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        amount = try container.decode(Double.self, forKey: .amount)
        derivationMethod = try container.decodeIfPresent(NutrientDerivationMethod.self, forKey: .derivationMethod) ?? .estimated
        sourceVersion = try container.decodeIfPresent(String.self, forKey: .sourceVersion)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
    }
}

struct DailyNutrient: Codable, Equatable, Identifiable, Sendable {
    let code: String
    let name: String
    let unit: String
    let nutrientClass: String
    let displayOrder: Int
    let targetKind: NutrientTargetKind
    let amount: Double
    let targetAmount: Double?
    let percentOfTarget: Double?
    let coverage: Double?
    let estimatedAmount: Double
    let verifiedAmount: Double
    let confidence: Double?
    let targetBasisAmount: Double?
    let targetBasisCodes: [String]
    let targetType: String?
    let upperLimitAmount: Double?
    let upperLimitScope: NutrientUpperLimitScope?
    let guidanceLimitAmount: Double?
    let guidanceLimitType: String?
    let belowTargetFlag: Bool?
    let excessFlag: Bool?
    let trendQualifyingDays: Int
    let trendRequiredDays: Int
    let trendPercentOfTarget: Double?
    let trendPercentOfUpperLimit: Double?
    let referenceURL: URL?
    let referenceNote: String?
    let foodSources: [NutrientSourceContribution]
    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, name, unit, amount, coverage, confidence
        case nutrientClass = "nutrient_class"
        case displayOrder = "display_order"
        case targetKind = "target_kind"
        case targetAmount = "target_amount"
        case percentOfTarget = "percent_of_target"
        case estimatedAmount = "estimated_amount"
        case verifiedAmount = "verified_amount"
        case targetBasisAmount = "target_basis_amount"
        case targetBasisCodes = "target_basis_codes"
        case targetType = "target_type"
        case upperLimitAmount = "upper_limit_amount"
        case upperLimitScope = "upper_limit_scope"
        case guidanceLimitAmount = "guidance_limit_amount"
        case guidanceLimitType = "guidance_limit_type"
        case belowTargetFlag = "below_target_flag"
        case excessFlag = "excess_flag"
        case trendQualifyingDays = "trend_qualifying_days"
        case trendRequiredDays = "trend_required_days"
        case trendPercentOfTarget = "trend_percent_of_target"
        case trendPercentOfUpperLimit = "trend_percent_of_upper_limit"
        case referenceURL = "reference_url"
        case referenceNote = "reference_note"
        case foodSources = "food_sources"
    }

    init(
        code: String, name: String, unit: String, nutrientClass: String,
        displayOrder: Int, targetKind: NutrientTargetKind, amount: Double,
        targetAmount: Double?, percentOfTarget: Double?, coverage: Double?,
        estimatedAmount: Double, verifiedAmount: Double, confidence: Double?,
        targetBasisAmount: Double? = nil, targetBasisCodes: [String] = [], targetType: String? = nil,
        upperLimitAmount: Double? = nil, upperLimitScope: NutrientUpperLimitScope? = nil,
        guidanceLimitAmount: Double? = nil, guidanceLimitType: String? = nil,
        belowTargetFlag: Bool? = nil, excessFlag: Bool? = nil,
        trendQualifyingDays: Int = 0, trendRequiredDays: Int = 4,
        trendPercentOfTarget: Double? = nil, trendPercentOfUpperLimit: Double? = nil,
        referenceURL: URL? = nil, referenceNote: String? = nil,
        foodSources: [NutrientSourceContribution] = []
    ) {
        self.code = code; self.name = name; self.unit = unit; self.nutrientClass = nutrientClass
        self.displayOrder = displayOrder; self.targetKind = targetKind; self.amount = amount
        self.targetAmount = targetAmount; self.percentOfTarget = percentOfTarget; self.coverage = coverage
        self.estimatedAmount = estimatedAmount; self.verifiedAmount = verifiedAmount; self.confidence = confidence
        self.targetBasisAmount = targetBasisAmount; self.targetBasisCodes = targetBasisCodes; self.targetType = targetType
        self.upperLimitAmount = upperLimitAmount; self.upperLimitScope = upperLimitScope
        self.guidanceLimitAmount = guidanceLimitAmount; self.guidanceLimitType = guidanceLimitType
        self.belowTargetFlag = belowTargetFlag; self.excessFlag = excessFlag
        self.trendQualifyingDays = trendQualifyingDays; self.trendRequiredDays = trendRequiredDays
        self.trendPercentOfTarget = trendPercentOfTarget; self.trendPercentOfUpperLimit = trendPercentOfUpperLimit
        self.referenceURL = referenceURL; self.referenceNote = referenceNote; self.foodSources = foodSources
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            code: try values.decode(String.self, forKey: .code),
            name: try values.decode(String.self, forKey: .name),
            unit: try values.decode(String.self, forKey: .unit),
            nutrientClass: try values.decode(String.self, forKey: .nutrientClass),
            displayOrder: try values.decode(Int.self, forKey: .displayOrder),
            targetKind: try values.decode(NutrientTargetKind.self, forKey: .targetKind),
            amount: try values.decode(Double.self, forKey: .amount),
            targetAmount: try values.decodeIfPresent(Double.self, forKey: .targetAmount),
            percentOfTarget: try values.decodeIfPresent(Double.self, forKey: .percentOfTarget),
            coverage: try values.decodeIfPresent(Double.self, forKey: .coverage),
            estimatedAmount: try values.decode(Double.self, forKey: .estimatedAmount),
            verifiedAmount: try values.decode(Double.self, forKey: .verifiedAmount),
            confidence: try values.decodeIfPresent(Double.self, forKey: .confidence),
            targetBasisAmount: try values.decodeIfPresent(Double.self, forKey: .targetBasisAmount),
            targetBasisCodes: try values.decodeIfPresent([String].self, forKey: .targetBasisCodes) ?? [],
            targetType: try values.decodeIfPresent(String.self, forKey: .targetType),
            upperLimitAmount: try values.decodeIfPresent(Double.self, forKey: .upperLimitAmount),
            upperLimitScope: try values.decodeIfPresent(NutrientUpperLimitScope.self, forKey: .upperLimitScope),
            guidanceLimitAmount: try values.decodeIfPresent(Double.self, forKey: .guidanceLimitAmount),
            guidanceLimitType: try values.decodeIfPresent(String.self, forKey: .guidanceLimitType),
            belowTargetFlag: try values.decodeIfPresent(Bool.self, forKey: .belowTargetFlag),
            excessFlag: try values.decodeIfPresent(Bool.self, forKey: .excessFlag),
            trendQualifyingDays: try values.decodeIfPresent(Int.self, forKey: .trendQualifyingDays) ?? 0,
            trendRequiredDays: try values.decodeIfPresent(Int.self, forKey: .trendRequiredDays) ?? 4,
            trendPercentOfTarget: try values.decodeIfPresent(Double.self, forKey: .trendPercentOfTarget),
            trendPercentOfUpperLimit: try values.decodeIfPresent(Double.self, forKey: .trendPercentOfUpperLimit),
            referenceURL: try values.decodeIfPresent(URL.self, forKey: .referenceURL),
            referenceNote: try values.decodeIfPresent(String.self, forKey: .referenceNote),
            foodSources: try values.decodeIfPresent([NutrientSourceContribution].self, forKey: .foodSources) ?? []
        )
    }

    var progress: Double { min(max(percentOfTarget ?? 0, 0), 1) }
    var hasEstimate: Bool { estimatedAmount > 0 }
    var hasSufficientCoverage: Bool { (coverage ?? 0) >= 0.8 }
}

struct NutrientSourceContribution: Codable, Equatable, Identifiable, Sendable {
    let consumptionItemID: UUID
    let foodEntryID: UUID?
    let name: String
    let amount: Double
    let percentOfDailyAmount: Double?
    let derivationMethod: NutrientDerivationMethod
    let confidence: Double?
    var id: UUID { consumptionItemID }

    enum CodingKeys: String, CodingKey {
        case name, amount, confidence
        case consumptionItemID = "consumption_item_id"
        case foodEntryID = "food_entry_id"
        case percentOfDailyAmount = "percent_of_daily_amount"
        case derivationMethod = "derivation_method"
    }
}

struct NutrientReference: Codable, Equatable, Sendable {
    let code: String
    let name: String
    let population: String
    let sourceURL: URL
    enum CodingKeys: String, CodingKey { case code, name, population; case sourceURL = "source_url" }
}

struct DailyNutritionSummary: Codable, Equatable, Sendable {
    let localDate: String
    let totalCalories: Int
    let macroCoverage: Double?
    let reference: NutrientReference
    let nutrients: [DailyNutrient]
    let enrichmentStatus: String? = nil
    let pendingItemCount: Int? = nil

    enum CodingKeys: String, CodingKey {
        case reference, nutrients
        case localDate = "local_date"
        case totalCalories = "total_calories"
        case macroCoverage = "macro_coverage"
        case enrichmentStatus = "enrichment_status"
        case pendingItemCount = "pending_item_count"
    }

    func nutrient(_ code: String) -> DailyNutrient? { nutrients.first { $0.code == code } }
    static let macroCodes = ["protein_g", "carbohydrate_g", "fat_g"]
    var isEnriching: Bool { enrichmentStatus == "processing" || (pendingItemCount ?? 0) > 0 }
}

struct NutrientAutoFillResponse: Codable, Sendable {
    let nutrients: [NutrientAmountInput]
    let modelID: String?
    let providerResponseID: String?
    enum CodingKeys: String, CodingKey {
        case nutrients
        case modelID = "model_id"
        case providerResponseID = "provider_response_id"
    }
}

enum NutritionGroup: String, CaseIterable, Hashable, Sendable {
    case macros
    case vitamins
    case minerals
    case essentialAminoAcids
    case essentialFattyAcids
    case fiber
    case choline
    case limits
    case other

    static let detailOrder: [Self] = [
        .macros, .vitamins, .minerals, .essentialAminoAcids, .essentialFattyAcids,
        .fiber, .choline, .limits, .other
    ]
    static let dailyOrder: [Self] = [
        .vitamins, .minerals, .essentialAminoAcids, .essentialFattyAcids,
        .fiber, .choline, .limits, .other
    ]

    var title: String {
        switch self {
        case .macros: "Macros"
        case .vitamins: "Vitamins"
        case .minerals: "Minerals"
        case .essentialAminoAcids: "Essential amino acids"
        case .essentialFattyAcids: "Essential fatty acids"
        case .fiber: "Fiber"
        case .choline: "Choline"
        case .limits: "Nutrients to limit"
        case .other: "Other nutrients"
        }
    }
}

enum NutrientCatalog {
    struct Item: Identifiable, Hashable, Sendable {
        let code: String
        let name: String
        let unit: String
        let group: NutritionGroup
        var id: String { code }
    }

    static let items: [Item] = [
        .init(code: "protein_g", name: "Protein", unit: "g", group: .macros),
        .init(code: "carbohydrate_g", name: "Carbohydrate", unit: "g", group: .macros),
        .init(code: "fat_g", name: "Fat", unit: "g", group: .macros),
        .init(code: "fiber_g", name: "Dietary fiber", unit: "g", group: .fiber),
        .init(code: "vitamin_a_mcg_rae", name: "Vitamin A", unit: "mcg RAE", group: .vitamins),
        .init(code: "vitamin_c_mg", name: "Vitamin C", unit: "mg", group: .vitamins),
        .init(code: "vitamin_d_mcg", name: "Vitamin D", unit: "mcg", group: .vitamins),
        .init(code: "vitamin_e_mg", name: "Vitamin E", unit: "mg", group: .vitamins),
        .init(code: "vitamin_k_mcg", name: "Vitamin K", unit: "mcg", group: .vitamins),
        .init(code: "thiamin_mg", name: "Thiamin", unit: "mg", group: .vitamins),
        .init(code: "riboflavin_mg", name: "Riboflavin", unit: "mg", group: .vitamins),
        .init(code: "niacin_mg_ne", name: "Niacin", unit: "mg NE", group: .vitamins),
        .init(code: "vitamin_b6_mg", name: "Vitamin B6", unit: "mg", group: .vitamins),
        .init(code: "folate_mcg_dfe", name: "Folate", unit: "mcg DFE", group: .vitamins),
        .init(code: "vitamin_b12_mcg", name: "Vitamin B12", unit: "mcg", group: .vitamins),
        .init(code: "biotin_mcg", name: "Biotin", unit: "mcg", group: .vitamins),
        .init(code: "pantothenic_acid_mg", name: "Pantothenic acid", unit: "mg", group: .vitamins),
        .init(code: "calcium_mg", name: "Calcium", unit: "mg", group: .minerals),
        .init(code: "iron_mg", name: "Iron", unit: "mg", group: .minerals),
        .init(code: "magnesium_mg", name: "Magnesium", unit: "mg", group: .minerals),
        .init(code: "phosphorus_mg", name: "Phosphorus", unit: "mg", group: .minerals),
        .init(code: "iodine_mcg", name: "Iodine", unit: "mcg", group: .minerals),
        .init(code: "potassium_mg", name: "Potassium", unit: "mg", group: .minerals),
        .init(code: "zinc_mg", name: "Zinc", unit: "mg", group: .minerals),
        .init(code: "selenium_mcg", name: "Selenium", unit: "mcg", group: .minerals),
        .init(code: "copper_mg", name: "Copper", unit: "mg", group: .minerals),
        .init(code: "manganese_mg", name: "Manganese", unit: "mg", group: .minerals),
        .init(code: "chromium_mcg", name: "Chromium", unit: "mcg", group: .minerals),
        .init(code: "molybdenum_mcg", name: "Molybdenum", unit: "mcg", group: .minerals),
        .init(code: "chloride_mg", name: "Chloride", unit: "mg", group: .minerals),
        .init(code: "sulfur_mg", name: "Sulfur", unit: "mg", group: .minerals),
        .init(code: "histidine_g", name: "Histidine", unit: "g", group: .essentialAminoAcids),
        .init(code: "isoleucine_g", name: "Isoleucine", unit: "g", group: .essentialAminoAcids),
        .init(code: "leucine_g", name: "Leucine", unit: "g", group: .essentialAminoAcids),
        .init(code: "lysine_g", name: "Lysine", unit: "g", group: .essentialAminoAcids),
        .init(code: "methionine_g", name: "Methionine", unit: "g", group: .essentialAminoAcids),
        .init(code: "phenylalanine_g", name: "Phenylalanine", unit: "g", group: .essentialAminoAcids),
        .init(code: "threonine_g", name: "Threonine", unit: "g", group: .essentialAminoAcids),
        .init(code: "tryptophan_g", name: "Tryptophan", unit: "g", group: .essentialAminoAcids),
        .init(code: "valine_g", name: "Valine", unit: "g", group: .essentialAminoAcids),
        .init(code: "linoleic_acid_g", name: "Linoleic acid (LA, omega-6)", unit: "g", group: .essentialFattyAcids),
        .init(code: "alpha_linolenic_acid_g", name: "Alpha-linolenic acid (ALA, omega-3)", unit: "g", group: .essentialFattyAcids),
        .init(code: "choline_mg", name: "Choline", unit: "mg", group: .choline),
        .init(code: "saturated_fat_g", name: "Saturated fat", unit: "g", group: .limits),
        .init(code: "sodium_mg", name: "Sodium", unit: "mg", group: .minerals),
        .init(code: "added_sugars_g", name: "Added sugars", unit: "g", group: .limits),
        .init(code: "cholesterol_mg", name: "Cholesterol", unit: "mg", group: .limits),
        .init(code: "sugars_g", name: "Total sugars", unit: "g", group: .other),
        .init(code: "trans_fat_g", name: "Trans fat", unit: "g", group: .other),
        .init(code: "caffeine_mg", name: "Caffeine", unit: "mg", group: .other),
    ]

    private static let importanceOrder: [String] = [
        // Macros
        "protein_g", "carbohydrate_g", "fat_g",
        // Vitamins
        "vitamin_d_mcg", "folate_mcg_dfe", "vitamin_b12_mcg", "vitamin_a_mcg_rae",
        "vitamin_c_mg", "vitamin_e_mg", "vitamin_k_mcg", "vitamin_b6_mg",
        "thiamin_mg", "riboflavin_mg", "niacin_mg_ne", "pantothenic_acid_mg", "biotin_mcg",
        // Minerals
        "sodium_mg", "potassium_mg", "calcium_mg", "iron_mg", "magnesium_mg",
        "zinc_mg", "iodine_mcg", "phosphorus_mg", "selenium_mcg", "copper_mg",
        "manganese_mg", "chloride_mg", "chromium_mcg", "molybdenum_mcg",
        "sulfur_mg",
        // Essential amino acids
        "histidine_g", "isoleucine_g", "leucine_g", "lysine_g", "methionine_g",
        "phenylalanine_g", "threonine_g", "tryptophan_g", "valine_g",
        // Essential fatty acids
        "linoleic_acid_g", "alpha_linolenic_acid_g",
        // Other nutrients
        "fiber_g", "saturated_fat_g", "added_sugars_g", "trans_fat_g",
        "cholesterol_mg", "sugars_g", "choline_mg", "caffeine_mg",
    ]

    private static let importanceRanks = Dictionary(
        uniqueKeysWithValues: importanceOrder.enumerated().map { ($0.element, $0.offset) }
    )

    static func importanceRank(for code: String) -> Int {
        importanceRanks[code] ?? Int.max
    }

    static func items(in group: NutritionGroup) -> [Item] {
        items.filter { $0.group == group }.sorted {
            importanceRank(for: $0.code) < importanceRank(for: $1.code)
        }
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
