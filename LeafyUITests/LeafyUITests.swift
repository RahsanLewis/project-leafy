import XCTest

final class LeafyUITests: XCTestCase {
    @MainActor
    func testWelcomeAndEligibilityGate() {
        let app = XCUIApplication()
        app.launchArguments = ["-SkipBrandSplash"]
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
        app.launchArguments = ["-SkipBrandSplash"]
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
        app.launchArguments = ["-CICOPreview", "-SkipBrandSplash"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        app.segmentedControls["foodLoggingMethodPicker"].buttons["AI"].tap()
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
    func testAskLeafyCanReviewAndLogAnEatenMealInlinePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Ask"].tap()
        let field = app.textFields["askLeafyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("I ate a chicken rice bowl")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatMealSuggestion"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["logChatMealButton"].exists)
        app.buttons["logChatMealButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatMealLoggedLabel"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAskLeafyKeyboardCanDismissWithoutLosingDraftPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Ask"].tap()
        let field = app.textFields["askLeafyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        field.typeText("What should I eat for dinner?")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        let dismissButton = app.buttons["dismissAskLeafyKeyboardButton"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 2))
        dismissButton.tap()

        XCTAssertEqual(field.value as? String, "What should I eat for dinner?")
        XCTAssertEqual(app.keyboards.count, 0)
        XCTAssertTrue(app.tabBars.buttons["Weight"].isHittable)
        app.tabBars.buttons["Weight"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["weightSummaryCard"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAIMealLoadingCanBeCancelledWithoutLosingDraftPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash", "-HoldAIMealEstimate"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        app.segmentedControls["foodLoggingMethodPicker"].buttons["AI"].tap()
        let description = app.textViews["aiMealDescription"]
        XCTAssertTrue(description.waitForExistence(timeout: 3))
        description.tap()
        description.typeText("Chicken and rice")
        app.buttons["Done"].tap()
        app.buttons["analyzeMealButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["aiMealLoadingScreen"].waitForExistence(timeout: 2))
        app.buttons["cancelMealAnalysisButton"].tap()
        XCTAssertTrue(description.waitForExistence(timeout: 2))
        XCTAssertEqual(description.value as? String, "Chicken and rice")
    }

    @MainActor
    func testUnifiedFoodLoggingPreservesDraftAcrossMethodsPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        XCTAssertTrue(app.navigationBars["Log Food"].waitForExistence(timeout: 3))

        let methods = app.segmentedControls["foodLoggingMethodPicker"]
        XCTAssertTrue(methods.waitForExistence(timeout: 2))
        XCTAssertTrue(methods.buttons["Search"].isSelected)
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        let scan = app.buttons["scanBarcodeButton"]
        XCTAssertTrue(scan.exists)
        scan.tap()
        XCTAssertTrue(app.navigationBars["Scan barcode"].waitForExistence(timeout: 3))
        app.navigationBars["Scan barcode"].buttons["Cancel"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 2))

        methods.buttons["Manual"].tap()
        let name = app.textFields["foodNameField"]
        let calories = app.textFields["foodCaloriesField"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap()
        name.typeText("Apple")
        calories.tap()
        calories.typeText("95")

        methods.buttons["AI"].tap()
        XCTAssertTrue(app.textViews["aiMealDescription"].waitForExistence(timeout: 2))
        methods.buttons["Manual"].tap()
        XCTAssertEqual(name.value as? String, "Apple")
        XCTAssertEqual(calories.value as? String, "95")

        app.buttons["saveFoodButton"].tap()
        XCTAssertTrue(app.buttons["logFoodButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Apple"].exists)
    }

    @MainActor
    func testFoodEntryOpensNutritionAndOffersEditAndDeleteActionsPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        app.segmentedControls["foodLoggingMethodPicker"].buttons["Manual"].tap()
        app.textFields["foodNameField"].tap()
        app.textFields["foodNameField"].typeText("Apple")
        app.textFields["foodCaloriesField"].tap()
        app.textFields["foodCaloriesField"].typeText("95")
        app.buttons["saveFoodButton"].tap()

        let apple = app.staticTexts["Apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 3))
        apple.tap()
        XCTAssertTrue(app.descendants(matching: .any)["limitedFoodNutritionView"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Nutrition data incomplete"].exists)
        app.buttons["Back"].tap()

        XCTAssertTrue(app.buttons["logFoodButton"].waitForExistence(timeout: 2))
        XCTAssertTrue(apple.waitForExistence(timeout: 2))
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'foodEntryRow-'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Delete"].exists)
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["foodNameField"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()

        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["Apple"].exists)
    }

    @MainActor
    func testBorderlessListScreensRemainNavigablePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Weight"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["weightSummaryCard"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Scan barcode"].exists)
        app.buttons["scanBarcodeButton"].tap()
        XCTAssertTrue(app.navigationBars["Scan barcode"].waitForExistence(timeout: 3))
        app.navigationBars["Scan barcode"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["morningReminderToggle"].exists)

        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.buttons["scanBarcodeButton"].waitForExistence(timeout: 3))
        app.buttons["scanBarcodeButton"].tap()
        XCTAssertTrue(app.navigationBars["Scan barcode"].waitForExistence(timeout: 3))
        app.navigationBars["Scan barcode"].buttons["Cancel"].tap()
    }

    @MainActor
    func testLeafySplashAppearsOnlyDuringColdLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-HoldBrandSplash"]
        app.launch()

        let splash = app.descendants(matching: .any)["leafySplash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 4))
        XCTAssertFalse(splash.exists)
    }

    @MainActor
    func testHomeDayNavigationFinishesOnThePreviousDay() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        XCTAssertTrue(app.staticTexts["selectedLogDayTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["selectedLogDayTitle"].label, "Today")
        app.buttons["previousDayButton"].tap()
        XCTAssertTrue(app.staticTexts["selectedLogDayTitle"].waitForExistence(timeout: 2))
        XCTAssertNotEqual(app.staticTexts["selectedLogDayTitle"].label, "Today")
        XCTAssertTrue(app.buttons["nextDayButton"].isEnabled)
    }

    @MainActor
    func testCalorieRingSupportsCalendarSwipeNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        let ring = app.descendants(matching: .any)["calorieBudgetCard"]
        XCTAssertTrue(ring.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["selectedLogDayTitle"].label, "Today")

        ring.swipeRight()
        XCTAssertNotEqual(app.staticTexts["selectedLogDayTitle"].label, "Today")
        ring.swipeLeft()
        XCTAssertEqual(app.staticTexts["selectedLogDayTitle"].label, "Today")
    }

    @MainActor
    func testDailyNutritionSummaryOpensFullNutrientView() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        let summary = app.descendants(matching: .any)["homeMacroSummary"]
        for _ in 0..<2 where !summary.exists { app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 3))

        app.buttons["openDailyNutrition"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dailyNutritionView"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Build toward"].exists)
        XCTAssertTrue(app.staticTexts["Keep within"].exists)
        XCTAssertTrue(app.staticTexts["Sodium"].exists)
        XCTAssertTrue(app.staticTexts["Vitamin D"].exists)
    }

    @MainActor
    func testWeightInsightsUseCompactExplanationsPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Weight"].tap()
        let info = app.buttons["weightInsightInfo-weeklyTrend"]
        for _ in 0..<3 where !info.exists { app.swipeUp() }
        XCTAssertTrue(info.waitForExistence(timeout: 2))

        XCTAssertTrue(app.staticTexts["Weekly trend"].exists)
        XCTAssertFalse(app.staticTexts["Observed trend"].exists)
        info.tap()
        let explanation = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Your estimated weekly rate of weight change.")
        ).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Add at least three weigh-ins spanning seven days to estimate your weekly trend."].exists)
    }
}
