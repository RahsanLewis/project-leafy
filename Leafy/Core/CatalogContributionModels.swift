import Foundation

enum CatalogContributionStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case processing
    case pendingReview = "pending_review"
    case accepted
    case needsReview = "needs_review"
    case rejected

    var title: String {
        switch self {
        case .draft: "Draft"
        case .processing: "Processing"
        case .pendingReview: "Under Review"
        case .accepted: "Accepted"
        case .needsReview: "Needs Attention"
        case .rejected: "Rejected"
        }
    }

    var isEditable: Bool { self == .draft || self == .needsReview }
}

struct CatalogContributionAsset: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let assetKind: String
    let objectPath: String
    enum CodingKeys: String, CodingKey {
        case id
        case assetKind = "asset_kind"
        case objectPath = "object_path"
    }
}

struct CatalogEvidence: Codable, Hashable, Sendable {
    var frontLegible: Bool
    var nutritionFactsLegible: Bool
    var ingredientsLegible: Bool
    enum CodingKeys: String, CodingKey {
        case frontLegible = "front_legible"
        case nutritionFactsLegible = "nutrition_facts_legible"
        case ingredientsLegible = "ingredients_legible"
    }
}

struct CatalogContributionFields: Codable, Hashable, Sendable {
    var productName: String
    var brandName: String
    var brandNotShown: Bool
    var servingDescription: String
    var servingGrams: Double
    var servingsPerContainer: String
    var ingredients: String
    var allergens: [String]
    var nutrients: [CatalogContributionNutrient]?
    var evidence: CatalogEvidence?
    var fieldConfidence: Double?
    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brandName = "brand_name"
        case brandNotShown = "brand_not_shown"
        case servingDescription = "serving_description"
        case servingGrams = "serving_grams"
        case servingsPerContainer = "servings_per_container"
        case ingredients, allergens, nutrients, evidence
        case fieldConfidence = "field_confidence"
    }

    static let empty = Self(
        productName: "", brandName: "", brandNotShown: false,
        servingDescription: "", servingGrams: 0, servingsPerContainer: "",
        ingredients: "", allergens: [], nutrients: nil, evidence: nil, fieldConfidence: nil
    )

    init(productName: String, brandName: String, brandNotShown: Bool, servingDescription: String, servingGrams: Double, servingsPerContainer: String, ingredients: String, allergens: [String], nutrients: [CatalogContributionNutrient]?, evidence: CatalogEvidence?, fieldConfidence: Double?) {
        self.productName = productName; self.brandName = brandName; self.brandNotShown = brandNotShown
        self.servingDescription = servingDescription; self.servingGrams = servingGrams
        self.servingsPerContainer = servingsPerContainer; self.ingredients = ingredients; self.allergens = allergens
        self.nutrients = nutrients; self.evidence = evidence; self.fieldConfidence = fieldConfidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        productName = try values.decodeIfPresent(String.self, forKey: .productName) ?? ""
        brandName = try values.decodeIfPresent(String.self, forKey: .brandName) ?? ""
        brandNotShown = try values.decodeIfPresent(Bool.self, forKey: .brandNotShown) ?? false
        servingDescription = try values.decodeIfPresent(String.self, forKey: .servingDescription) ?? ""
        servingGrams = try values.decodeIfPresent(Double.self, forKey: .servingGrams) ?? 0
        servingsPerContainer = try values.decodeIfPresent(String.self, forKey: .servingsPerContainer) ?? ""
        ingredients = try values.decodeIfPresent(String.self, forKey: .ingredients) ?? ""
        allergens = try values.decodeIfPresent([String].self, forKey: .allergens) ?? []
        nutrients = try values.decodeIfPresent([CatalogContributionNutrient].self, forKey: .nutrients)
        evidence = try values.decodeIfPresent(CatalogEvidence.self, forKey: .evidence)
        fieldConfidence = try values.decodeIfPresent(Double.self, forKey: .fieldConfidence)
    }
}

struct CatalogContributionNutrient: Codable, Hashable, Sendable {
    var code: String
    var amountPerServing: Double
    var unit: String
    var percentDailyValue: Double?
    var confidence: Double?
    enum CodingKeys: String, CodingKey {
        case code
        case amountPerServing = "amount_per_serving"
        case unit
        case percentDailyValue = "percent_daily_value"
        case confidence
        case nutrientCode = "nutrient_code"
    }

    init(code: String, amountPerServing: Double, unit: String, percentDailyValue: Double? = nil, confidence: Double? = nil) {
        self.code = code; self.amountPerServing = amountPerServing; self.unit = unit
        self.percentDailyValue = percentDailyValue; self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        code = try values.decodeIfPresent(String.self, forKey: .code) ?? values.decode(String.self, forKey: .nutrientCode)
        amountPerServing = try values.decode(Double.self, forKey: .amountPerServing)
        unit = try values.decode(String.self, forKey: .unit)
        percentDailyValue = try values.decodeIfPresent(Double.self, forKey: .percentDailyValue)
        confidence = try values.decodeIfPresent(Double.self, forKey: .confidence)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(code, forKey: .code)
        try values.encode(amountPerServing, forKey: .amountPerServing)
        try values.encode(unit, forKey: .unit)
        try values.encodeIfPresent(percentDailyValue, forKey: .percentDailyValue)
        try values.encodeIfPresent(confidence, forKey: .confidence)
    }
}

struct CatalogValidationResults: Codable, Hashable, Sendable {
    let missingFields: [String]
    let evidenceComplete: Bool?
    let calorieConsistent: Bool?
    let confidence: Double?
    let autoApprove: Bool?
    let reason: String?
    enum CodingKeys: String, CodingKey {
        case missingFields = "missing_fields"
        case evidenceComplete = "evidence_complete"
        case calorieConsistent = "calorie_consistent"
        case confidence
        case autoApprove = "auto_approve"
        case reason
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        missingFields = try values.decodeIfPresent([String].self, forKey: .missingFields) ?? []
        evidenceComplete = try values.decodeIfPresent(Bool.self, forKey: .evidenceComplete)
        calorieConsistent = try values.decodeIfPresent(Bool.self, forKey: .calorieConsistent)
        confidence = try values.decodeIfPresent(Double.self, forKey: .confidence)
        autoApprove = try values.decodeIfPresent(Bool.self, forKey: .autoApprove)
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
    }
}

enum CatalogExtractionStatus: String, Codable, Sendable {
    case complete
    case needsPhotos = "needs_photos"
}

struct CatalogExtractionDiagnostics: Codable, Hashable, Sendable {
    let status: CatalogExtractionStatus
    let missingFields: [String]
    let requestedAssets: [String]
    let message: String

    enum CodingKeys: String, CodingKey {
        case status, message
        case missingFields = "missing_fields"
        case requestedAssets = "requested_assets"
    }
}

struct CatalogContribution: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let gtin: String
    let marketCountry: String
    let status: CatalogContributionStatus
    let revision: Int
    let extractedFields: CatalogContributionFields?
    let confirmedFields: CatalogContributionFields?
    let validationResults: CatalogValidationResults?
    let extractionDiagnostics: CatalogExtractionDiagnostics?
    let processingStage: String?
    let reviewReason: String?
    let acceptedFoodVersionID: UUID?
    let assets: [CatalogContributionAsset]?
    let nutrients: [CatalogContributionNutrient]?
    let createdAt: Date
    let updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, gtin, status, revision, assets, nutrients
        case marketCountry = "market_country"
        case extractedFields = "extracted_fields"
        case confirmedFields = "confirmed_fields"
        case validationResults = "validation_results"
        case extractionDiagnostics = "extraction_diagnostics"
        case processingStage = "processing_stage"
        case reviewReason = "review_reason"
        case acceptedFoodVersionID = "accepted_food_version_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayName: String {
        confirmedFields?.productName.nonempty ?? extractedFields?.productName.nonempty ?? "Barcode \(gtin)"
    }
}

struct CatalogContributionStartResponse: Codable, Sendable {
    let outcome: String
    let foodVersionID: UUID?
    let contribution: CatalogContribution?
    enum CodingKeys: String, CodingKey { case outcome, contribution; case foodVersionID = "food_version_id" }
}
struct CatalogContributionEnvelope: Codable, Sendable { let contribution: CatalogContribution }
struct CatalogContributionListResponse: Codable, Sendable { let contributions: [CatalogContribution] }
struct CatalogContributionSubmitResponse: Codable, Sendable {
    let outcome: String
    let contribution: CatalogContribution
    let foodVersionID: UUID?
    let pendingLog: PendingCatalogLog?
    enum CodingKeys: String, CodingKey {
        case outcome, contribution
        case foodVersionID = "food_version_id"
        case pendingLog = "pending_log"
    }
}

enum PendingCatalogLogStatus: String, Codable, Sendable {
    case pending, processing, needsAction = "needs_action", failed
}

struct PendingCatalogLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let contributionID: UUID
    let name: String
    let barcode: String
    let servingCount: Double
    let consumedAt: Date
    let localDate: String
    let timeZone: String
    let mealType: MealType
    let status: PendingCatalogLogStatus
    let message: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, barcode, status, message
        case contributionID = "contribution_id"
        case servingCount = "serving_count"
        case consumedAt = "consumed_at"
        case localDate = "local_date"
        case timeZone = "time_zone"
        case mealType = "meal_type"
        case updatedAt = "updated_at"
    }
}

struct PendingCatalogLogListResponse: Codable, Sendable {
    let pendingLogs: [PendingCatalogLog]
    enum CodingKeys: String, CodingKey { case pendingLogs = "pending_logs" }
}

private extension String {
    var nonempty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
