import XCTest

final class LeafyUITests: XCTestCase {
    @MainActor
    func testWelcomeAndEligibilityGate() {
        let app = XCUIApplication()
        app.launchArguments = ["-SkipBrandSplash", "-ForceOnboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your nutrition, made clear"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["welcomeSignInButton"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Are you 18 or older?"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["Yes"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Do any of these apply to you?"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["No"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
    }

    @MainActor
    func testReturningUserCanOpenSignInBeforeOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-SkipBrandSplash", "-ForceOnboarding"]
        app.launch()

        let signIn = app.buttons["welcomeSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 3))
        signIn.tap()

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sign in to access your saved nutrition plan, food log, and weight history."].exists)
        XCTAssertTrue(app.buttons["Sign in with Apple"].exists)
        XCTAssertTrue(app.buttons["Sign in with Google"].exists)
        XCTAssertTrue(app.buttons["Sign in"].exists)
        XCTAssertEqual(app.segmentedControls.count, 0)
    }

    @MainActor
    func testImperialHeightWheelsChangeIndependently() {
        let app = XCUIApplication()
        app.launchArguments = ["-SkipBrandSplash", "-ForceOnboarding"]
        app.launch()

        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Are you 18 or older?"].waitForExistence(timeout: 2))
        app.buttons["Yes"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Do any of these apply to you?"].waitForExistence(timeout: 2))
        app.buttons["No"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["What’s your goal?"].waitForExistence(timeout: 2))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["When were you born?"].waitForExistence(timeout: 2))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Which calculation should Leafy use?"].waitForExistence(timeout: 2))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.pickerWheels.count, 2)
        let feet = app.pickerWheels.element(boundBy: 0)
        let inches = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(feet.waitForExistence(timeout: 2))
        XCTAssertTrue(inches.waitForExistence(timeout: 2))

        inches.adjust(toPickerWheelValue: "10 in")
        feet.adjust(toPickerWheelValue: "6 ft")

        XCTAssertEqual(inches.value as? String, "10 in")
        XCTAssertEqual(feet.value as? String, "6 ft")
    }

    @MainActor
    func testMorningCheckInPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipBrandSplash"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Is yesterday’s food log complete?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Add anything that’s missing, or continue."].exists)
        XCTAssertTrue(app.staticTexts["1,030 Cal"].exists)
        let complete = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Everything is logged")
        ).firstMatch
        let incomplete = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continue without adding more")
        ).firstMatch
        XCTAssertTrue(complete.exists)
        XCTAssertTrue(app.buttons["Review food log"].exists)
        XCTAssertTrue(incomplete.exists)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Add missing food")
        ).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Add anything you missed now.")
        ).firstMatch.exists)
        XCTAssertTrue(complete.label.contains("Continue to today’s weight."))
        XCTAssertTrue(incomplete.label.contains("Move on to today’s weight."))

        complete.tap()
        let continueButton = app.buttons["continueMorningIntakeButton"]
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Today’s weight"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Log weight"].exists)
        XCTAssertTrue(app.buttons["Skip for today"].exists)

        app.buttons["Skip for today"].tap()
        let calorieBudget = app.descendants(matching: .any)["calorieBudgetCard"]
        XCTAssertTrue(calorieBudget.waitForExistence(timeout: 2))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["morningReminderToggle"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEmptyMorningCheckInExplainsFastingAndMissingLogs() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-EmptyMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Did you eat yesterday?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Choose what best describes yesterday."].exists)
        XCTAssertTrue(app.staticTexts["No food logged"].exists)
        let fasted = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "I fasted")
        ).firstMatch
        let incomplete = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Skip yesterday")
        ).firstMatch
        XCTAssertTrue(fasted.exists)
        XCTAssertTrue(incomplete.exists)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Log what I ate")
        ).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Add yesterday’s food now.")
        ).firstMatch.exists)
        XCTAssertTrue(fasted.label.contains("Continue to today’s weight."))
        XCTAssertTrue(incomplete.label.contains("Move on without adding food."))

        fasted.tap()
        XCTAssertTrue(app.buttons["continueMorningIntakeButton"].isEnabled)
    }

    @MainActor
    func testMorningCheckInCanOpenYesterdayLoggerAndReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-EmptyMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Did you eat yesterday?"].waitForExistence(timeout: 3))
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Log what I ate")
        ).firstMatch.tap()
        let action = app.buttons["continueMorningIntakeButton"]
        XCTAssertEqual(action.label, "Log yesterday’s food")
        action.tap()

        XCTAssertTrue(app.navigationBars["Log Food"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Did you eat yesterday?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No food logged"].exists)
    }

    @MainActor
    func testWeightEntryUsesSharedWheelPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Actual weight"].waitForExistence(timeout: 3))
        app.buttons["Log Weight"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["entryWeightWholePicker"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["entryWeightDecimalPicker"].exists)
        XCTAssertTrue(app.datePickers["weightEntryDate"].exists)
        XCTAssertTrue(app.buttons["saveWeightEntryButton"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["foodLogSuccessMessage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["aiMealDescription"].exists)
        app.navigationBars["Log Food"].buttons["Done"].tap()
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
        XCTAssertTrue(app.buttons["reviewChatMealButton"].exists)
        app.buttons["reviewChatMealButton"].tap()
        XCTAssertTrue(app.navigationBars["Review meal"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["logChatMealButton"].waitForExistence(timeout: 3))
        app.buttons["logChatMealButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatMealLoggedLabel"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAskLeafyResponseCanBeCancelledWithoutLosingDraftPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash", "-HoldChatResponse"]
        app.launch()

        app.tabBars.buttons["Ask"].tap()
        let field = app.textFields["askLeafyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("What should I eat for dinner?")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["stopAskLeafyButton"].waitForExistence(timeout: 2))
        app.buttons["stopAskLeafyButton"].tap()
        XCTAssertEqual(field.value as? String, "What should I eat for dinner?")
        XCTAssertFalse(app.buttons["stopAskLeafyButton"].exists)
    }

    @MainActor
    func testAskLeafyWarmlyRedirectsOffTopicRequestsPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Ask"].tap()
        let field = app.textFields["askLeafyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Write code for a stock portfolio")
        app.buttons["Send"].tap()

        let redirect = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "I’m focused on nutrition and health")
        ).firstMatch
        XCTAssertTrue(redirect.waitForExistence(timeout: 3))
        XCTAssertTrue(field.exists)
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
        XCTAssertFalse(app.buttons["dismissAskLeafyKeyboardButton"].exists)

        app.staticTexts["General wellness guidance only—not medical advice."].tap()

        XCTAssertEqual(field.value as? String, "What should I eat for dinner?")
        let keyboardDismissed = NSPredicate(format: "count == 0")
        expectation(for: keyboardDismissed, evaluatedWith: app.keyboards)
        waitForExpectations(timeout: 2)
        XCTAssertTrue(app.tabBars.buttons["Progress"].isHittable)
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Actual weight"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(methods.buttons["Scan"].isSelected)
        XCTAssertTrue(app.buttons["scanBarcodeButton"].exists)
        app.searchFields.firstMatch.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()
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
        XCTAssertTrue(app.descendants(matching: .any)["foodLogSuccessMessage"].waitForExistence(timeout: 3))
        XCTAssertEqual(name.value as? String, "Food or meal")
        XCTAssertEqual(calories.value as? String, "0")
        app.navigationBars["Log Food"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["logFoodButton"].waitForExistence(timeout: 3))
        for _ in 0..<3 where !app.staticTexts["Apple"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Apple"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLogFoodConfirmsBeforeDiscardingManualDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        app.segmentedControls["foodLoggingMethodPicker"].buttons["Manual"].tap()
        let name = app.textFields["foodNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap()
        name.typeText("Unfinished snack")
        app.navigationBars["Log Food"].buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Discard this food entry?"].waitForExistence(timeout: 2))
        app.buttons["Keep Editing"].tap()
        XCTAssertEqual(name.value as? String, "Unfinished snack")
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
        XCTAssertTrue(app.descendants(matching: .any)["foodLogSuccessMessage"].waitForExistence(timeout: 3))
        app.navigationBars["Log Food"].buttons["Done"].tap()

        let apple = app.staticTexts["Apple"]
        for _ in 0..<3 where !apple.exists { app.swipeUp() }
        XCTAssertTrue(apple.waitForExistence(timeout: 3))
        apple.tap()
        XCTAssertTrue(app.descendants(matching: .any)["limitedFoodNutritionView"].waitForExistence(timeout: 3))
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
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: app.staticTexts["Apple"])
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testBorderlessListScreensRemainNavigablePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Actual weight"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Scan barcode"].exists)
        XCTAssertTrue(app.searchFields.firstMatch.exists)
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
        XCTAssertLessThan(splash.frame.midY, app.frame.midY)
        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 4))
        XCTAssertFalse(splash.exists)
    }

    @MainActor
    func testTodayDayNavigationFinishesOnThePreviousDay() {
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
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Keep within")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Sodium"].exists)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Vitamins")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Vitamin D"].exists)
    }

    @MainActor
    func testWeightInsightsUseCompactExplanationsPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Actual weight"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "below your 7-day average")
        ).firstMatch.exists)

        let displayMenu = app.buttons["weightDisplayMenu"]
        XCTAssertTrue(displayMenu.exists)
        XCTAssertGreaterThanOrEqual(displayMenu.frame.height, 43.9)
        displayMenu.tap()
        let actualMode = app.buttons["weightDisplayActual"]
        XCTAssertTrue(actualMode.waitForExistence(timeout: 2))
        actualMode.tap()
        XCTAssertTrue(app.staticTexts["Actual weight"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Actual remaining"].exists)
        XCTAssertTrue(app.buttons["actualWeightInfo"].exists)

        app.buttons["weightDisplayMenu"].tap()
        let trendMode = app.buttons["weightDisplayTrend"]
        XCTAssertTrue(trendMode.waitForExistence(timeout: 2))
        trendMode.tap()
        XCTAssertTrue(app.staticTexts["Trend weight"].waitForExistence(timeout: 2))

        let trendInfo = app.buttons["trendWeightInfo"]
        XCTAssertTrue(trendInfo.exists)
        XCTAssertGreaterThanOrEqual(trendInfo.frame.width, 43.9)
        XCTAssertGreaterThanOrEqual(trendInfo.frame.height, 43.9)
        trendInfo.tap()
        XCTAssertTrue(app.staticTexts["Why Leafy emphasizes trend weight"].waitForExistence(timeout: 2))
        app.buttons["dismissTrendWeightExplanation"].tap()

        let fluctuationInfo = app.buttons["weightFluctuationRangeInfo"]
        XCTAssertTrue(fluctuationInfo.waitForExistence(timeout: 2))
        fluctuationInfo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fluctuationRangeMeaning"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["fluctuationRangeInside"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["fluctuationRangeOutside"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "smoothed seven-reading trend")).firstMatch.exists)
        app.buttons["Dismiss fluctuation range explanation"].tap()

        let info = app.buttons["weightInsightInfo-pace"]
        for _ in 0..<3 where !info.exists { app.swipeUp() }
        XCTAssertTrue(info.waitForExistence(timeout: 2))

        XCTAssertTrue(app.staticTexts["Pace"].exists)
        info.tap()
        let explanation = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Compares your observed weekly trend with the weekly change")
        ).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["weightInsightExplanation-pace"].exists)
        XCTAssertFalse(app.popovers.firstMatch.exists)
        app.buttons["dismissWeightInsightExplanation"].tap()

        let insightIdentifiers = [
            "totalChange", "latestChange", "daysLogged", "pace",
        ]
        for identifier in insightIdentifiers {
            let control = app.buttons["weightInsightInfo-\(identifier)"]
            for _ in 0..<4 where !control.exists { app.swipeUp() }
            XCTAssertTrue(control.exists, "Missing insight control \(identifier)")
        }

        for removedIdentifier in [
            "totalProgress", "weeklyTrend", "goalPace", "typicalFluctuation",
            "projectedGoal", "actualRangeChange", "actualVersusTrend",
        ] {
            XCTAssertFalse(app.buttons["weightInsightInfo-\(removedIdentifier)"].exists)
        }
    }

    @MainActor
    func testTrendWeightIsHiddenBeforeSevenReadings() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SixWeightReadings", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Actual weight"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["weightDisplayMenu"].exists)
        XCTAssertFalse(app.staticTexts["Trend"].exists)
        XCTAssertFalse(app.staticTexts["Seven-day trend"].exists)
    }

    @MainActor
    func testSettingsNutritionPlanUsesBorderlessTargetOverviewAndCalculationSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Scan"].exists)
        XCTAssertFalse(app.tabBars.buttons["Plan"].exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["nutritionPlanLink"].waitForExistence(timeout: 3))
        app.buttons["nutritionPlanLink"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["planResults"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["planCalorieTarget"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["planMacroTargets"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["planGoalSummary"].exists)

        app.buttons["showPlanCalculation"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["planCalculationView"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["planCalculation-Resting-energy"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["planCalculation-Estimated-maintenance"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["planCalculation-Daily-deficit"].exists)
        XCTAssertTrue(app.staticTexts["Protein target"].exists)
    }

    @MainActor
    func testAuthenticatedPlanEditingStaysSeparateFromAccountCreation() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["nutritionPlanLink"].waitForExistence(timeout: 3))
        app.buttons["nutritionPlanLink"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["planEditView"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Edit plan"].exists)
        XCTAssertFalse(app.staticTexts["Create account and save"].exists)
        XCTAssertFalse(app.staticTexts["Already have an account? Sign in"].exists)
        XCTAssertFalse(app.staticTexts["Are you 18 or older?"].exists)

        XCTAssertTrue(app.descendants(matching: .any)["targetWeightWholePicker"].exists)
        XCTAssertTrue(app.buttons["targetWeightValueButton"].exists)
        app.buttons["targetWeightValueButton"].tap()
        XCTAssertTrue(app.textFields["targetWeightTextField"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["targetWeightValueButton"].waitForExistence(timeout: 2))

        app.buttons["Maintain"].tap()
        XCTAssertTrue(app.buttons["reviewPlanChangesButton"].isEnabled)
        app.buttons["reviewPlanChangesButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["planEditReview"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Your updated targets"].exists)
        XCTAssertFalse(app.staticTexts["Create account and save"].exists)
        XCTAssertFalse(app.staticTexts["Sign in"].exists)
    }

    @MainActor
    func testOnboardingPlanResultsUsesDetachedActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-PlanResultsPreview", "-SkipBrandSplash"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["onboardingPlanResults"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Preview complete"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Adjust answers"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["planCalorieTarget"].exists)
    }

    @MainActor
    func testWeightHistoryUsesFiveEntryPreviewAndFullHistoryDestination() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-SkipBrandSplash"]
        app.launch()

        app.tabBars.buttons["Progress"].tap()
        let viewAll = app.buttons["View all"]
        for _ in 0..<6 where !viewAll.exists { app.swipeUp() }
        XCTAssertTrue(viewAll.waitForExistence(timeout: 2))
        viewAll.tap()

        XCTAssertTrue(app.descendants(matching: .any)["weightHistoryView"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Weight history"].exists)
    }
}
