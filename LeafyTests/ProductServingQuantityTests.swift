import XCTest
@testable import Leafy

final class ProductServingQuantityTests: XCTestCase {
    func testParsesWholeAndFractionalServings() {
        XCTAssertEqual(ProductServingQuantity.count(from: "1"), 1)
        XCTAssertEqual(ProductServingQuantity.count(from: "1.5"), 1.5)
        XCTAssertEqual(ProductServingQuantity.count(from: "0,75"), 0.75)
    }

    func testRejectsMissingAndOutOfRangeServings() {
        XCTAssertNil(ProductServingQuantity.count(from: ""))
        XCTAssertNil(ProductServingQuantity.count(from: "0"))
        XCTAssertNil(ProductServingQuantity.count(from: "0.1"))
        XCTAssertNil(ProductServingQuantity.count(from: "101"))
        XCTAssertNil(ProductServingQuantity.count(from: "two"))
    }

    func testConvertsServingsToGrams() {
        XCTAssertEqual(ProductServingQuantity.grams(servings: 1.5, servingGrams: 28), 42)
    }
}
