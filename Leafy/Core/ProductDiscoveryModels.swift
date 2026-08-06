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
    let servingSize: Double?
    let servingUnit: String?
    let caloriesPer100G: Double?
    let imageURL: URL?
    let score: ProductNutritionScore?
    var historyID: UUID? = nil
    var analyzedAt: Date? = nil
    enum CodingKeys: String, CodingKey {
        case id, name, brand, barcode, source, score
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
    let servingSize: Double?
    let servingUnit: String?
    let caloriesPer100G: Double?
    let ingredients: String?
    let allergens: [String]
    let imageURL: URL?
    let verificationStatus: String?
    let nutrients: [ProductNutrient]
    let portions: [ProductPortion]
    let score: ProductNutritionScore?
    enum CodingKeys: String, CodingKey {
        case id, name, brand, barcode, source, ingredients, allergens, nutrients, portions, score
        case fdcID = "fdc_id", foodVersionID = "food_version_id"
        case servingSize = "serving_size", servingUnit = "serving_unit"
        case caloriesPer100G = "calories_per_100g", imageURL = "image_url"
        case verificationStatus = "verification_status"
    }
    var defaultGrams: Double { portions.first?.gramWeight ?? servingSize ?? 100 }
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
    let algorithmVersion: String
    let score: Int?
    let label: String?
    let confidence: Double
    let positiveFactors: [String]
    let limitingFactors: [String]
    let missingFields: [String]
    enum CodingKeys: String, CodingKey {
        case score, label, confidence
        case algorithmVersion = "algorithm_version", positiveFactors = "positive_factors"
        case limitingFactors = "limiting_factors", missingFields = "missing_fields"
    }
}

struct ProductListResponse: Codable, Sendable { let products: [ProductSummary] }
struct ProductSummaryResponse: Codable, Sendable { let product: ProductSummary? }
struct ProductDetailResponse: Codable, Sendable { let product: ProductDetail }
struct ProductLogResponse: Codable, Sendable { let entry: FoodEntry }
