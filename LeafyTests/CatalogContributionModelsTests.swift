import XCTest
@testable import Leafy

final class CatalogContributionModelsTests: XCTestCase {
    func testCatalogWaitEstimatorLearnsAndClampsDurations() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertEqual(CatalogContributionWaitEstimator.estimatedSeconds(defaults: defaults), 25)
        CatalogContributionWaitEstimator.record(35, defaults: defaults)
        XCTAssertEqual(CatalogContributionWaitEstimator.estimatedSeconds(defaults: defaults), 28, accuracy: 0.001)
        CatalogContributionWaitEstimator.record(500, defaults: defaults)
        XCTAssertEqual(CatalogContributionWaitEstimator.estimatedSeconds(defaults: defaults), 60)
    }

    func testDraftContributionDecodesEmptyServerFields() throws {
        let json = """
        {"id":"A7C9D51F-C3B4-44E0-B3D9-F41EAAF71D5A","gtin":"012345678905","market_country":"US","status":"draft","revision":1,"extracted_fields":{},"confirmed_fields":{},"validation_results":{},"review_reason":null,"accepted_food_version_id":null,"assets":[],"nutrients":[],"created_at":"2026-08-08T12:00:00Z","updated_at":"2026-08-08T12:00:00Z"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let contribution = try decoder.decode(CatalogContribution.self, from: Data(json.utf8))
        XCTAssertEqual(contribution.status, .draft)
        XCTAssertEqual(contribution.displayName, "Barcode 012345678905")
        XCTAssertTrue(contribution.status.isEditable)
    }

    func testExtractedLabelAndNutrientsDecode() throws {
        let json = """
        {"id":"A7C9D51F-C3B4-44E0-B3D9-F41EAAF71D5A","gtin":"012345678905","market_country":"US","status":"needs_review","revision":2,"extracted_fields":{"product_name":"Sea Salt Chips","brand_name":"Leafy Foods","brand_not_shown":false,"serving_description":"About 15 chips","serving_grams":28,"servings_per_container":"8","ingredients":"Potatoes, oil, salt","allergens":[],"nutrients":[{"code":"energy_kcal","amount_per_serving":160,"unit":"kcal","percent_daily_value":null,"confidence":0.98}],"evidence":{"front_legible":true,"nutrition_facts_legible":true,"ingredients_legible":true},"field_confidence":0.96},"confirmed_fields":{},"validation_results":{"missing_fields":["iron_mg"],"reason":"Missing iron"},"review_reason":"Missing iron","accepted_food_version_id":null,"assets":[],"nutrients":[],"created_at":"2026-08-08T12:00:00Z","updated_at":"2026-08-08T12:00:00Z"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let contribution = try decoder.decode(CatalogContribution.self, from: Data(json.utf8))
        XCTAssertEqual(contribution.displayName, "Sea Salt Chips")
        XCTAssertEqual(contribution.extractedFields?.servingGrams, 28)
        XCTAssertEqual(contribution.extractedFields?.nutrients?.first?.amountPerServing, 160)
        XCTAssertEqual(contribution.validationResults?.missingFields, ["iron_mg"])
    }

    func testContributionStatusLabelsAreUserFacing() {
        XCTAssertEqual(CatalogContributionStatus.pendingReview.title, "Under Review")
        XCTAssertEqual(CatalogContributionStatus.needsReview.title, "Needs Attention")
        XCTAssertFalse(CatalogContributionStatus.accepted.isEditable)
    }

    func testExtractionDiagnosticsDecodeFocusedPhotoRequests() throws {
        let json = """
        {"id":"A7C9D51F-C3B4-44E0-B3D9-F41EAAF71D5A","gtin":"012345678905","market_country":"US","status":"draft","revision":1,"extracted_fields":{},"confirmed_fields":null,"validation_results":{"missing_fields":["Ingredients"]},"extraction_diagnostics":{"status":"needs_photos","missing_fields":["Ingredients"],"requested_assets":["ingredients"],"message":"Leafy needs a clearer photo of the ingredients list."},"review_reason":null,"accepted_food_version_id":null,"assets":[],"nutrients":[],"created_at":"2026-08-08T12:00:00Z","updated_at":"2026-08-08T12:00:00Z"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let contribution = try decoder.decode(CatalogContribution.self, from: Data(json.utf8))
        XCTAssertEqual(contribution.extractionDiagnostics?.status, .needsPhotos)
        XCTAssertEqual(contribution.extractionDiagnostics?.requestedAssets, ["ingredients"])
        XCTAssertEqual(contribution.extractionDiagnostics?.missingFields, ["Ingredients"])
    }
}
