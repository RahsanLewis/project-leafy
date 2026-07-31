import XCTest

final class LeafyUITests: XCTestCase {
    @MainActor
    func testWelcomeAndEligibilityGate() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your nutrition, made clear"].waitForExistence(timeout: 3))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["A quick safety check"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["Yes, Are you 18 or older?"].tap()
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["No, Do any of these apply to you?"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
    }
}
