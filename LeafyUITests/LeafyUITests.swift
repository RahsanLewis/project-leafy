import XCTest

final class LeafyUITests: XCTestCase {
    @MainActor
    func testWelcomeAndEligibilityGate() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Meet Leafy"].waitForExistence(timeout: 3))
        app.buttons["Build my plan"].tap()
        XCTAssertTrue(app.staticTexts["Before we begin"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.switches["I am 18 or older"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
    }
}
