import Foundation

enum ProductDiscoveryIntent: Sendable { case analyze, log }

struct ProductSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let fdcID: Int?
    let foodVersionID: UUID?
    let name: String
    let brand: String?
    let barcode: String?
    let source: String
    let foodKind: String?
    let resolutionSource: String?
    let servingSize: Double?
    let servingUnit: String?
    let caloriesPer100G: Double?
    let imageURL: URL?
    let score: ProductNutritionScore?
    var historyID: UUID? = nil
    var analyzedAt: Date? = nil
    enum CodingKeys: String, CodingKey {
        case id, name, brand, barcode, source, score
        case foodKind = "food_kind", resolutionSource = "resolution_source"
        case fdcID = "fdc_id", foodVersionID = "food_version_id"
        case servingSize = "serving_size", servingUnit = "serving_unit"
        case caloriesPer100G = "calories_per_100g", imageURL = "image_url"
        case historyID = "history_id", analyzedAt = "analyzed_at"
    }
}

struct ProductDetail: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let fdcID: Int?
    let foodVersionID: UUID
    let name: String
    let brand: String?
    let barcode: String?
    let source: String
    let foodKind: String?
    let resolutionSource: String?
    let servingSize: Double?
    let servingUnit: String?
    let servingsPerContainer: String?
    let metricServingSize: Double?
    let metricServingUnit: String?
    let nutritionFootnote: String?
    let caloriesPer100G: Double?
    let ingredients: String?
    let allergens: [String]
    let imageURL: URL?
    let verificationStatus: String?
    let nutrients: [ProductNutrient]
    let portions: [ProductPortion]
    let labelNutrients: [ProductLabelNutrient]?
    let score: ProductNutritionScore?
    enum CodingKeys: String, CodingKey {
        case id, name, brand, barcode, source, ingredients, allergens, nutrients, portions, score
        case labelNutrients = "label_nutrients"
        case foodKind = "food_kind", resolutionSource = "resolution_source"
        case fdcID = "fdc_id", foodVersionID = "food_version_id"
        case servingSize = "serving_size", servingUnit = "serving_unit"
        case servingsPerContainer = "servings_per_container"
        case metricServingSize = "metric_serving_size", metricServingUnit = "metric_serving_unit"
        case nutritionFootnote = "nutrition_footnote"
        case caloriesPer100G = "calories_per_100g", imageURL = "image_url"
        case verificationStatus = "verification_status"
    }
    var defaultGrams: Double {
        if let grams = portions.first?.gramWeight, grams > 0 { return grams }
        if let servingSize, servingSize > 0,
           ["g", "gram", "grams"].contains(servingUnit?.lowercased() ?? "") {
            return servingSize
        }
        return 100
    }
}

struct ProductLabelNutrient: Codable, Hashable, Sendable {
    let code: String
    let amountPerServing: Double
    let unit: String
    let percentDailyValue: Double?
    let declarationType: String
    let printedText: String?
    let evidenceSection: String?
    let valueSource: String

    enum CodingKeys: String, CodingKey {
        case code, unit
        case amountPerServing = "amount_per_serving"
        case percentDailyValue = "percent_daily_value"
        case declarationType = "declaration_type"
        case printedText = "printed_text"
        case evidenceSection = "evidence_section"
        case valueSource = "value_source"
    }

    var isDerived: Bool { valueSource == "source_derived" || declarationType == "derived" }
}

enum ProductServingQuantity {
    static let allowedRange = 0.25...100.0
    static let step = 0.5

    static func count(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), allowedRange.contains(value) else { return nil }
        return value
    }

    static func grams(servings: Double, servingGrams: Double) -> Double {
        servings * servingGrams
    }

    static func formatted(_ servings: Double) -> String {
        servings.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct ProductNutrient: Codable, Hashable, Sendable {
    let code: String
    let amountPer100G: Double
    enum CodingKeys: String, CodingKey { case code; case amountPer100G = "amount_per_100g" }
}

struct ProductPortion: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let amount: Double
    let unit: String
    let description: String?
    let gramWeight: Double
    enum CodingKeys: String, CodingKey { case id, amount, unit, description; case gramWeight = "gram_weight" }
}

struct ProductNutritionScore: Codable, Hashable, Sendable {
    let modelVersion: String
    let ingredientTaxonomyVersion: String
    let additiveDatabaseVersion: String
    let score: Int?
    let rating: String?
    let scoreStatus: String
    let baseScore: Int?
    let additivePenalty: Int
    let components: [String: ProductScoreComponent]
    let additives: [ProductScoreAdditive]
    let flags: ProductScoreFlags
    let strengths: [String]
    let weaknesses: [String]
    let explanation: [String]
    let missingFields: [String]
    let unavailableReasons: [String]
    let evidenceCoverage: Double
    let evidenceConfidence: Double
    let confidenceLevel: String
    let includedComponents: [String]
    let jurisdiction: String
    let assessmentDate: String
    enum CodingKeys: String, CodingKey {
        case score, rating, components, additives, flags, strengths, weaknesses, explanation, jurisdiction
        case modelVersion = "model_version", ingredientTaxonomyVersion = "ingredient_taxonomy_version"
        case additiveDatabaseVersion = "additive_database_version", scoreStatus = "score_status"
        case baseScore = "base_score", additivePenalty = "additive_penalty"
        case missingFields = "missing_fields", unavailableReasons = "unavailable_reasons"
        case evidenceCoverage = "evidence_coverage", evidenceConfidence = "evidence_confidence"
        case confidenceLevel = "confidence_level", includedComponents = "included_components"
        case assessmentDate = "assessment_date"
        case legacyAlgorithmVersion = "algorithm_version"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        modelVersion = try values.decodeIfPresent(String.self, forKey: .modelVersion)
            ?? values.decodeIfPresent(String.self, forKey: .legacyAlgorithmVersion)
            ?? "legacy"
        ingredientTaxonomyVersion = try values.decodeIfPresent(String.self, forKey: .ingredientTaxonomyVersion) ?? ""
        additiveDatabaseVersion = try values.decodeIfPresent(String.self, forKey: .additiveDatabaseVersion) ?? ""
        score = try values.decodeIfPresent(Int.self, forKey: .score)
        rating = try values.decodeIfPresent(String.self, forKey: .rating)
        scoreStatus = try values.decodeIfPresent(String.self, forKey: .scoreStatus) ?? "legacy"
        baseScore = try values.decodeIfPresent(Int.self, forKey: .baseScore)
        additivePenalty = try values.decodeIfPresent(Int.self, forKey: .additivePenalty) ?? 0
        components = try values.decodeIfPresent([String: ProductScoreComponent].self, forKey: .components) ?? [:]
        additives = try values.decodeIfPresent([ProductScoreAdditive].self, forKey: .additives) ?? []
        flags = try values.decodeIfPresent(ProductScoreFlags.self, forKey: .flags) ?? .empty
        strengths = try values.decodeIfPresent([String].self, forKey: .strengths) ?? []
        weaknesses = try values.decodeIfPresent([String].self, forKey: .weaknesses) ?? []
        explanation = try values.decodeIfPresent([String].self, forKey: .explanation) ?? []
        missingFields = try values.decodeIfPresent([String].self, forKey: .missingFields) ?? []
        unavailableReasons = try values.decodeIfPresent([String].self, forKey: .unavailableReasons) ?? []
        evidenceCoverage = try values.decodeIfPresent(Double.self, forKey: .evidenceCoverage) ?? (scoreStatus == "complete" ? 1 : 0)
        evidenceConfidence = try values.decodeIfPresent(Double.self, forKey: .evidenceConfidence) ?? (scoreStatus == "complete" ? 1 : 0)
        confidenceLevel = try values.decodeIfPresent(String.self, forKey: .confidenceLevel) ?? (scoreStatus == "complete" ? "high" : "none")
        includedComponents = try values.decodeIfPresent([String].self, forKey: .includedComponents) ?? Array(components.keys)
        jurisdiction = try values.decodeIfPresent(String.self, forKey: .jurisdiction) ?? ""
        assessmentDate = try values.decodeIfPresent(String.self, forKey: .assessmentDate) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(modelVersion, forKey: .modelVersion)
        try values.encode(ingredientTaxonomyVersion, forKey: .ingredientTaxonomyVersion)
        try values.encode(additiveDatabaseVersion, forKey: .additiveDatabaseVersion)
        try values.encodeIfPresent(score, forKey: .score)
        try values.encodeIfPresent(rating, forKey: .rating)
        try values.encode(scoreStatus, forKey: .scoreStatus)
        try values.encodeIfPresent(baseScore, forKey: .baseScore)
        try values.encode(additivePenalty, forKey: .additivePenalty)
        try values.encode(components, forKey: .components)
        try values.encode(additives, forKey: .additives)
        try values.encode(flags, forKey: .flags)
        try values.encode(strengths, forKey: .strengths)
        try values.encode(weaknesses, forKey: .weaknesses)
        try values.encode(explanation, forKey: .explanation)
        try values.encode(missingFields, forKey: .missingFields)
        try values.encode(unavailableReasons, forKey: .unavailableReasons)
        try values.encode(evidenceCoverage, forKey: .evidenceCoverage)
        try values.encode(evidenceConfidence, forKey: .evidenceConfidence)
        try values.encode(confidenceLevel, forKey: .confidenceLevel)
        try values.encode(includedComponents, forKey: .includedComponents)
        try values.encode(jurisdiction, forKey: .jurisdiction)
        try values.encode(assessmentDate, forKey: .assessmentDate)
    }

    var isAvailable: Bool { modelVersion.hasPrefix("PFQS-1.") && ["complete", "provisional"].contains(scoreStatus) && score != nil }
    var isProvisional: Bool { scoreStatus == "provisional" }
}

struct ProductScoreComponent: Codable, Hashable, Sendable {
    let score: Int
    let max: Int
    let normalizedValue: Double?
    let unit: String?
    let method: String?
    enum CodingKeys: String, CodingKey {
        case score, max, unit, method
        case normalizedValue = "normalized_value"
    }
}

struct ProductScoreAdditive: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let canonicalID: String
    let family: String?
    let tier: Int?
    let penalty: Int
    let status: String
    let reason: String
    let matchedAlias: String
    var id: String { canonicalID }
    enum CodingKeys: String, CodingKey {
        case name, family, tier, penalty, status, reason
        case canonicalID = "canonical_id", matchedAlias = "matched_alias"
    }
}

struct ProductScoreFlags: Codable, Hashable, Sendable {
    let tier4AdditivePresent: Bool
    let scoreCeilingApplied: Bool
    let regulatoryFlag: Bool
    enum CodingKeys: String, CodingKey {
        case tier4AdditivePresent = "tier_4_additive_present"
        case scoreCeilingApplied = "score_ceiling_applied"
        case regulatoryFlag = "regulatory_flag"
    }
    static let empty = ProductScoreFlags(tier4AdditivePresent: false, scoreCeilingApplied: false, regulatoryFlag: false)
}

struct ProductListResponse: Codable, Sendable { let products: [ProductSummary] }
struct ProductSummaryResponse: Codable, Sendable { let product: ProductSummary? }
struct ProductDetailResponse: Codable, Sendable { let product: ProductDetail }
struct ProductLogResponse: Codable, Sendable { let entry: FoodEntry }
