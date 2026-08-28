import XCTest
@testable import Leafy

final class FunctionContractTests: XCTestCase {
    func testEveryAppFunctionFixtureDecodesAsItsSwiftCodableRequest() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "function-request-fixtures", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let decoder = JSONDecoder()

        func decode<T: Decodable>(_ function: String, as type: T.Type) throws {
            let payload = try XCTUnwrap(root[function], "Missing contract fixture for \(function)")
            _ = try decoder.decode(type, from: JSONSerialization.data(withJSONObject: payload))
        }

        try decode("save-nutrition-plan", as: FunctionContracts.SaveNutritionPlan.self)
        try decode("manage-legal-acceptance", as: FunctionContracts.ActionVersion.self)
        try decode("daily-nutrition", as: FunctionContracts.LocalDate.self)
        try decode("manage-daily-checkin", as: FunctionContracts.ActionAdjustment.self)
        try decode("manage-weight-entry", as: FunctionContracts.ActionID.self)
        try decode("manage-food-entry", as: FunctionContracts.ActionID.self)
        try decode("discover-food-product", as: FunctionContracts.ActionQuery.self)
        try decode("manage-catalog-contribution", as: FunctionContracts.ActionOnly.self)
        try decode("estimate-meal", as: FunctionContracts.ActionSessionID.self)
        try decode("nutrition-chat", as: FunctionContracts.ActionOnly.self)
        try decode("delete-account", as: FunctionContracts.DeleteAccount.self)
        XCTAssertEqual(root.count, 11, "Add a typed contract whenever the app adds an Edge Function")
    }
}
