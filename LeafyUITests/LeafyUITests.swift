import XCTest

final class LeafyUITests: XCTestCase {
    @MainActor
    func testWelcomeAndEligibilityGate() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your nutrition, made clear"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["welcomeSignInButton"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["A quick safety check"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["Yes, Are you 18 or older?"].tap()
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["No, Do any of these apply to you?"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
    }

    @MainActor
    func testReturningUserCanOpenSignInBeforeOnboarding() {
        let app = XCUIApplication()
        app.launch()

        let signIn = app.buttons["welcomeSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 3))
        signIn.tap()

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sign in to access your saved nutrition plan."].exists)
        XCTAssertTrue(app.buttons["Sign in with Apple"].exists)
        XCTAssertTrue(app.buttons["Sign in"].exists)
        XCTAssertEqual(app.segmentedControls.count, 0)
    }

    @MainActor
    func testMorningCheckInPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Morning check-in"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1,030 Cal"].exists)
        XCTAssertTrue(app.buttons["Yes, this is complete"].exists)
        XCTAssertTrue(app.buttons["Review food log"].exists)
        XCTAssertTrue(app.buttons["I didn’t finish logging"].exists)

        app.buttons["Yes, this is complete"].tap()
        XCTAssertTrue(app.staticTexts["Today’s weight"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Log weight"].exists)
        XCTAssertTrue(app.buttons["Skip for today"].exists)

        app.buttons["Skip for today"].tap()
        let calorieBudget = app.descendants(matching: .any)["calorieBudgetCard"]
        XCTAssertTrue(calorieBudget.waitForExistence(timeout: 2))
        XCTAssertEqual(calorieBudget.label, "1,320 calories remaining. 530 of 1,850 calories eaten.")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["morningReminderToggle"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testAIMealTextReviewAndConfirmationPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.tabBars.buttons["AI"].tap()
        let description = app.textViews["aiMealDescription"]
        XCTAssertTrue(description.waitForExistence(timeout: 3))
        description.tap()
        description.typeText("Chicken, rice, and vegetables")
        app.buttons["Done"].tap()
        app.buttons["analyzeMealButton"].tap()

        XCTAssertTrue(app.staticTexts["One detail would help"].waitForExistence(timeout: 3))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.buttons["confirmMealEstimateButton"].waitForExistence(timeout: 3))
        app.buttons["confirmMealEstimateButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testBorderlessListScreensRemainNavigablePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Weight"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["weightSummaryCard"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["weightChart"].exists)

        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["morningReminderToggle"].exists)
    }
}
