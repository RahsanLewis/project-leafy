import Foundation
import Testing
@testable import Leafy

struct ProductDetailLabelTests {
    @Test func decodesPackageServingFactsAndProvisionalScore() throws {
        let json = #"""
        {
          "product": {
            "id": "food-1",
            "fdc_id": 123,
            "food_version_id": "A7C9D51F-C3B4-44E0-B3D9-F41EAAF71D5A",
            "name": "Hot Corn Snack",
            "brand": "Example",
            "barcode": "012345678905",
            "source": "USDA FoodData Central",
            "food_kind": "packaged",
            "resolution_source": "usda",
            "serving_size": 28,
            "serving_unit": "g",
            "servings_per_container": "About 8",
            "metric_serving_size": 28,
            "metric_serving_unit": "g",
            "nutrition_footnote": null,
            "calories_per_100g": 535.714,
            "ingredients": "Corn meal, oil, seasoning",
            "allergens": ["Milk"],
            "image_url": null,
            "verification_status": "verified",
            "nutrients": [{"code":"energy_kcal","amount_per_100g":535.714}],
            "portions": [],
            "label_nutrients": [
              {"code":"energy_kcal","amount_per_serving":150,"unit":"kcal","percent_daily_value":null,"declaration_type":"derived","printed_text":null,"evidence_section":"usda_fdc","value_source":"source_derived"},
              {"code":"sodium_mg","amount_per_serving":250,"unit":"mg","percent_daily_value":11,"declaration_type":"derived","printed_text":null,"evidence_section":"usda_fdc","value_source":"source_derived"}
            ],
            "score": {
              "model_version":"PFQS-1.1",
              "score":72,
              "rating":"Good",
              "score_status":"provisional",
              "evidence_coverage":0.85,
              "evidence_confidence":0.72,
              "confidence_level":"moderate",
              "included_components":["sodium","protein"],
              "missing_fields":["added_sugars_g"],
              "unavailable_reasons":[]
            }
          }
        }
        """#

        let response = try JSONDecoder().decode(ProductDetailResponse.self, from: Data(json.utf8))
        #expect(response.product.servingsPerContainer == "About 8")
        #expect(response.product.labelNutrients?.first?.amountPerServing == 150)
        #expect(response.product.labelNutrients?.last?.percentDailyValue == 11)
        #expect(response.product.labelNutrients?.first?.isDerived == true)
        #expect(response.product.score?.scoreStatus == "provisional")
        #expect(response.product.score?.isAvailable == true)
        #expect(response.product.score?.evidenceCoverage == 0.85)
        #expect(response.product.score?.missingFields == ["added_sugars_g"])
    }

    @Test func ingredientPresentationCleansPrefixWithoutRewritingTheList() {
        let value = " INGREDIENTS: Corn meal, seasoning (salt, whey, spices), vegetable oil; color "
        let cleaned = IngredientPresentation.cleaned(value)
        #expect(cleaned == "Corn meal, seasoning (salt, whey, spices), vegetable oil; color")
    }

    @Test func scoreBandsUseRatingAlignedBoundaries() {
        #expect(LeafyScoreBand(score: 0) == .red)
        #expect(LeafyScoreBand(score: 24) == .red)
        #expect(LeafyScoreBand(score: 25) == .orange)
        #expect(LeafyScoreBand(score: 49) == .orange)
        #expect(LeafyScoreBand(score: 50) == .yellow)
        #expect(LeafyScoreBand(score: 69) == .yellow)
        #expect(LeafyScoreBand(score: 70) == .green)
        #expect(LeafyScoreBand(score: 89) == .green)
        #expect(LeafyScoreBand(score: 90) == .blue)
        #expect(LeafyScoreBand(score: 100) == .blue)
    }

    @Test func optionalPackageFieldsRemainBackwardCompatible() throws {
        let json = #"""
        {"product":{"id":"food-1","fdc_id":null,"food_version_id":"A7C9D51F-C3B4-44E0-B3D9-F41EAAF71D5A","name":"Food","brand":null,"barcode":null,"source":"Leafy catalog","food_kind":"packaged","resolution_source":"leafy_catalog","serving_size":28,"serving_unit":"g","calories_per_100g":100,"ingredients":null,"allergens":[],"image_url":null,"verification_status":"verified","nutrients":[],"portions":[],"score":null}}
        """#
        let response = try JSONDecoder().decode(ProductDetailResponse.self, from: Data(json.utf8))
        #expect(response.product.labelNutrients == nil)
        #expect(response.product.servingsPerContainer == nil)
    }
}
