import XCTest

final class LeafyUITests: XCTestCase {
    @MainActor
    func testWelcomeAndEligibilityGate() {
        let app = XCUIApplication()
        app.launchArguments = ["-ForceOnboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your nutrition, made clear"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["welcomeSignInButton"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Are you 18 or older?"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["Yes"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["A few health questions"].exists)
        XCTAssertTrue(app.staticTexts["Are you pregnant or breastfeeding?"].exists)
        XCTAssertTrue(app.staticTexts["Are you in eating-disorder recovery?"].exists)
        XCTAssertTrue(app.staticTexts["Are you following a diet directed by a clinician?"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["pregnancyAnswerNo"].tap()
        app.buttons["recoveryAnswerNo"].tap()
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["clinicianDietAnswerNo"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
    }

    @MainActor
    func testReturningUserCanOpenSignInBeforeOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-ForceOnboarding"]
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
        app.launchArguments = ["-ForceOnboarding"]
        app.launch()

        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Are you 18 or older?"].waitForExistence(timeout: 2))
        app.buttons["Yes"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["A few health questions"].waitForExistence(timeout: 2))
        app.buttons["pregnancyAnswerNo"].tap()
        app.buttons["recoveryAnswerNo"].tap()
        app.buttons["clinicianDietAnswerNo"].tap()
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
        app.launchArguments = ["-CICOPreview"]
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
        app.launchArguments = ["-CICOPreview", "-EmptyMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-EmptyMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        let description = app.textFields["aiMealDescription"]
        XCTAssertTrue(description.waitForExistence(timeout: 3))
        description.tap()
        description.typeText("Chicken, rice, and vegetables")
        app.buttons["Done"].tap()
        app.buttons["analyzeMealButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["mealClarificationScreen"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Nutrition review"].exists)
        let answer = app.descendants(matching: .any)["mealClarificationAnswer"]
        answer.tap()
        answer.typeText("One bowl")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["submitMealClarificationButton"].isEnabled)
        app.buttons["submitMealClarificationButton"].tap()
        XCTAssertTrue(app.buttons["confirmMealEstimateButton"].waitForExistence(timeout: 3))
        app.buttons["confirmMealEstimateButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["foodLogSuccessMessage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["aiMealDescription"].exists)
        app.navigationBars["Log Food"].buttons["Done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAIMealClarificationCanContinueWithoutAnAnswerPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        let description = app.textFields["aiMealDescription"]
        XCTAssertTrue(description.waitForExistence(timeout: 3))
        description.tap()
        description.typeText("A bowl of homemade soup")
        app.buttons["Done"].tap()
        app.buttons["analyzeMealButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["mealClarificationScreen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["skipMealClarificationButton"].exists)
        app.buttons["skipMealClarificationButton"].tap()
        XCTAssertTrue(app.buttons["confirmMealEstimateButton"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAskLeafyCanReviewAndLogAnEatenMealInlinePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-HoldChatResponse"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn", "-HoldAIMealEstimate"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        let description = app.textFields["aiMealDescription"]
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
    func testUnifiedFoodLoggingKeepsSearchDescribePhotoAndScanTogetherPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        XCTAssertTrue(app.navigationBars["Log Food"].waitForExistence(timeout: 3))

        XCTAssertFalse(app.segmentedControls["foodLoggingMethodPicker"].exists)
        let description = app.textFields["aiMealDescription"]
        XCTAssertTrue(description.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["addMealPhotoButton"].exists)
        XCTAssertTrue(app.buttons["scanBarcodeButton"].exists)
        description.tap()
        description.typeText("Apple")
        app.buttons["Done"].tap()
        let scan = app.buttons["scanBarcodeButton"]
        XCTAssertTrue(scan.exists)
        scan.tap()
        XCTAssertTrue(app.navigationBars["Scan barcode"].waitForExistence(timeout: 3))
        app.navigationBars["Scan barcode"].buttons["Cancel"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 2))
        XCTAssertEqual(description.value as? String, "Apple")
    }

    @MainActor
    func testScanTabSearchInsteadDismissesCameraAndActivatesSearchPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        attachUITestScreenshot(app, named: "01-today-before-tap")

        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 3))
        attachUITestScreenshot(app, named: "02-scan-tab-landing")

        XCTAssertTrue(app.buttons["scanBarcodeButton"].waitForExistence(timeout: 3))
        app.buttons["scanBarcodeButton"].tap()
        XCTAssertTrue(app.navigationBars["Scan barcode"].waitForExistence(timeout: 3))
        attachUITestScreenshot(app, named: "03-camera-open")

        XCTAssertTrue(app.buttons["Search Instead"].waitForExistence(timeout: 3))
        app.buttons["Search Instead"].tap()

        XCTAssertTrue(
            app.buttons["Cancel"].waitForExistence(timeout: 3),
            "Search was not activated by Search Instead"
        )

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Search field did not appear after Search Instead")

        XCTAssertFalse(
            app.staticTexts["Scan a packaged food"].exists,
            "scanLanding was still visible after Search Instead; searchContent should have replaced it"
        )
        XCTAssertTrue(
            app.staticTexts["Search packaged foods"].waitForExistence(timeout: 3),
            "searchContent empty state was not visible after Search Instead"
        )

        waitForNonExistence(
            of: app.navigationBars["Scan barcode"],
            timeout: 5,
            "camera cover still on screen after Search Instead"
        )

        attachUITestScreenshot(app, named: "04-after-search-instead")
        attachUITestScreenshot(app, named: "05-search-active")

        _ = app.keyboards.firstMatch.exists

        XCTAssertTrue(
            app.buttons["Cancel"].waitForExistence(timeout: 3),
            "Search Cancel button was gone before it could be tapped"
        )
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["Scan a packaged food"].waitForExistence(timeout: 3),
            "Scan landing did not return after cancelling search"
        )
        attachUITestScreenshot(app, named: "06-back-on-scan-tab")

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 3))
        attachUITestScreenshot(app, named: "07-back-on-today")
    }

    @MainActor
    func testLogFoodChooseFromLibraryOpensSystemPhotoPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        XCTAssertTrue(app.navigationBars["Log Food"].waitForExistence(timeout: 3))

        app.buttons["addMealPhotoButton"].tap()
        let chooseFromLibrary = app.buttons["Choose from Library"]
        XCTAssertTrue(chooseFromLibrary.waitForExistence(timeout: 2))
        chooseFromLibrary.tap()

        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLogFoodConfirmsBeforeDiscardingDescribeDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        let description = app.textFields["aiMealDescription"]
        XCTAssertTrue(description.waitForExistence(timeout: 2))
        description.tap()
        description.typeText("Unfinished snack")
        app.navigationBars["Log Food"].buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Discard this food entry?"].waitForExistence(timeout: 2))
        app.buttons["Keep Editing"].tap()
        XCTAssertEqual(description.value as? String, "Unfinished snack")
    }

    @MainActor
    func testFoodEntryOpensNutritionAndOffersEditAndDeleteActionsPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.buttons["logFoodButton"].tap()
        let description = app.textFields["aiMealDescription"]
        description.tap()
        description.typeText("Apple")
        app.buttons["Done"].tap()
        app.buttons["analyzeMealButton"].tap()
        let answer = app.descendants(matching: .any)["mealClarificationAnswer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 3))
        answer.tap()
        answer.typeText("One medium apple")
        app.buttons["Done"].tap()
        app.buttons["submitMealClarificationButton"].tap()
        XCTAssertTrue(app.buttons["confirmMealEstimateButton"].waitForExistence(timeout: 3))
        app.buttons["confirmMealEstimateButton"].tap()
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
    func testColdLaunchDoesNotRenderSecondInAppSplash() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["calorieBudgetCard"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["leafySplash"].exists)
    }

    @MainActor
    func testTodayDayNavigationFinishesOnThePreviousDay() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        let summary = app.descendants(matching: .any)["homeMacroSummary"]
        for _ in 0..<2 where !summary.exists { app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 3))

        app.buttons["openDailyNutrition"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dailyNutritionView"].waitForExistence(timeout: 3))
        for _ in 0..<2 where !app.staticTexts["Vitamins"].exists { app.swipeUp() }
        app.staticTexts["Vitamins"].tap()
        XCTAssertTrue(app.staticTexts["Vitamin D"].exists)
        let vitaminDInfo = app.buttons["About Vitamin D"]
        XCTAssertTrue(vitaminDInfo.waitForExistence(timeout: 2))
        vitaminDInfo.tap()
        XCTAssertTrue(app.staticTexts["What it supports"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Food sources"].exists)
        XCTAssertFalse(app.staticTexts["What it is"].exists)
        XCTAssertFalse(app.staticTexts["Logged amount"].exists)
        XCTAssertFalse(app.staticTexts["Data coverage"].exists)
        let explanationSheet = app.descendants(matching: .any)["dismissNutrientExplanationSheet"]
        XCTAssertTrue(explanationSheet.exists)
        XCTAssertLessThan(explanationSheet.frame.height, app.frame.height * 0.75)
        app.buttons["dismissNutrientExplanation"].tap()
    }

    @MainActor
    func testWeightInsightsUseCompactExplanationsPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Actual weight"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "below your 7-day average")
        ).firstMatch.exists)

        XCTAssertFalse(app.buttons["weightDisplayMenu"].exists)
        XCTAssertFalse(app.buttons["weightDisplayTrend"].exists)
        XCTAssertFalse(app.staticTexts["Trend weight"].exists)
        XCTAssertTrue(app.staticTexts["Actual remaining"].exists)
        let actualInfo = app.buttons["actualWeightInfo"]
        XCTAssertTrue(actualInfo.exists)
        XCTAssertGreaterThanOrEqual(actualInfo.frame.width, 43.9)
        XCTAssertGreaterThanOrEqual(actualInfo.frame.height, 43.9)
        actualInfo.tap()
        XCTAssertTrue(app.staticTexts["About actual weight"].waitForExistence(timeout: 2))
        app.buttons["dismissWeightExplanation"].tap()

        let fluctuationInfo = app.buttons["weightFluctuationRangeInfo"]
        XCTAssertTrue(fluctuationInfo.waitForExistence(timeout: 2))
        fluctuationInfo.tap()
        let rangeExplanation = app.descendants(matching: .any)["fluctuationRangeExplanation"]
        XCTAssertTrue(rangeExplanation.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "normal day-to-day weight fluctuations")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "trend downward")
        ).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Inside the range"].exists)
        XCTAssertFalse(app.staticTexts["Outside the range"].exists)
        XCTAssertFalse(app.staticTexts["What matters most"].exists)
        app.buttons["Dismiss fluctuation range explanation"].tap()

        let info = app.buttons["weightInsightsInfo"]
        for _ in 0..<3 where !info.exists { app.swipeUp() }
        XCTAssertTrue(info.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(info.frame.width, 43.9)
        XCTAssertGreaterThanOrEqual(info.frame.height, 43.9)

        XCTAssertTrue(app.staticTexts["Pace"].exists)
        info.tap()
        XCTAssertTrue(app.descendants(matching: .any)["weightInsightsExplanation"].waitForExistence(timeout: 2))
        for identifier in ["totalChange", "latestChange", "daysLogged", "pace"] {
            XCTAssertTrue(app.descendants(matching: .any)["weightInsightDefinition-\(identifier)"].exists)
        }
        XCTAssertFalse(app.popovers.firstMatch.exists)
        app.buttons["dismissWeightInsightsExplanation"].tap()

        let insightIdentifiers = [
            "totalChange", "latestChange", "daysLogged", "pace",
        ]
        for identifier in insightIdentifiers {
            XCTAssertFalse(app.buttons["weightInsightInfo-\(identifier)"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["weightInsight-\(identifier)"].exists)
        }

        for removedIdentifier in [
            "totalProgress", "weeklyTrend", "goalPace", "typicalFluctuation",
            "projectedGoal", "actualRangeChange", "actualVersusTrend",
        ] {
            XCTAssertFalse(app.buttons["weightInsightInfo-\(removedIdentifier)"].exists)
        }
    }

    @MainActor
    func testWeightChartSupportsEveryTimeframe() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["weightChart"].waitForExistence(timeout: 3))

        for range in ["1W", "1M", "3M", "YTD", "1Y", "All"] {
            let button = app.buttons["weightRange\(range)"]
            XCTAssertTrue(button.waitForExistence(timeout: 2), "Missing \(range) chart range")
            button.tap()
            XCTAssertTrue(button.isSelected, "\(range) should become the selected chart range")
            XCTAssertTrue(app.descendants(matching: .any)["weightChart"].exists)
        }
    }

    @MainActor
    func testTrendWeightIsHiddenBeforeSevenReadings() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SixWeightReadings", "-SkipMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
    func testSettingsProvidesDirectSignOutAndCompactBottomSheetConfirmations() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        let signOut = app.buttons["settingsSignOutButton"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 3))
        signOut.tap()

        let sheet = app.descendants(matching: .any)["signOutConfirmationSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        XCTAssertFalse(app.popovers.firstMatch.exists)
        XCTAssertLessThan(sheet.frame.height, app.frame.height * 0.6)
        XCTAssertTrue(app.buttons["confirmSignOutButton"].exists)
        app.buttons["signOutConfirmationSheetCancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))

        app.buttons["nutritionPlanLink"].tap()
        app.buttons["showPlanCalculation"].tap()
        let explanation = app.descendants(matching: .any)["planCalculationView"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(explanation.frame.height, app.frame.height * 0.86)
        XCTAssertFalse(app.popovers.firstMatch.exists)
    }

    @MainActor
    func testAuthenticatedPlanEditingStaysSeparateFromAccountCreation() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
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
        app.launchArguments = ["-CICOPreview", "-PlanResultsPreview"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["onboardingPlanResults"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Preview complete"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Adjust answers"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["planCalorieTarget"].exists)
    }

    @MainActor
    func testWeightHistoryUsesFiveEntryPreviewAndFullHistoryDestination() {
        let app = XCUIApplication()
        app.launchArguments = ["-CICOPreview", "-SkipMorningCheckIn"]
        app.launch()

        app.tabBars.buttons["Progress"].tap()
        let viewAll = app.buttons["View all"]
        for _ in 0..<6 where !viewAll.exists { app.swipeUp() }
        XCTAssertTrue(viewAll.waitForExistence(timeout: 2))
        viewAll.tap()

        XCTAssertTrue(app.descendants(matching: .any)["weightHistoryView"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Weight history"].exists)
    }

    @MainActor
    func attachUITestScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func waitForNonExistence(
        of element: XCUIElement,
        timeout: TimeInterval,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, message, file: file, line: line)
    }
}
