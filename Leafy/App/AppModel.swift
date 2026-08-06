import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    enum Route: Equatable { case launching, onboarding, dashboard }
    enum AuthenticationPurpose: Equatable { case savePlan, accessExistingAccount }
    enum SaveState: Equatable { case idle, creatingAccount, awaitingConfirmation, resendingConfirmation, authenticating, saving, deleting }

    var route: Route = .launching
    var draft = OnboardingDraft()
    var preview: NutritionPlan?
    var currentPlan: NutritionPlan?
    var selectedLogDate = Calendar.current.startOfDay(for: .now)
    var foodEntries: [FoodEntry] = []
    var weightEntries: [WeightEntry] = []
    var dailyPlan: NutritionPlan?
    var morningCheckIn: MorningCheckIn?
    var showMorningCheckIn = false
    var hasMorningCheckInReminder = false
    var planAdjustmentNotice: PlanAdjustmentNotice?
    var dataContributionStatus: DataContributionStatus?
    var isDataContributionLoading = false
    var dataContributionErrorMessage: String?
    var isCheckInMutationInProgress = false
    var checkInErrorMessage: String?
    var isDailyLoading = false
    var isFoodMutationInProgress = false
    var productSearchResults: [ProductSummary] = []
    var productHistory: [ProductSummary] = []
    var isProductLoading = false
    var productErrorMessage: String?
    var isWeightLoading = false
    var isWeightMutationInProgress = false
    var weightErrorMessage: String?
    var weightStatusMessage: String?
    var lastWeightOutcome: WeightMutationOutcome?
    var dailyErrorMessage: String?
    var errorMessage: String?
    var statusMessage: String?
    var saveState: SaveState = .idle
    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var showAuthentication = false
    var authenticationPurpose: AuthenticationPurpose = .savePlan
    var isAuthenticated = false
    private var lastPromptedCheckInDay: Date?
    var isConfigured: Bool { configuration.isConfigured }
    var isPreviewMode: Bool { isCICOPreview }
    var dailySummary: DailyCalorieSummary {
        DailyCalorieSummary(budget: dailyPlan?.calorieTargetKcal, entries: foodEntries)
    }
    var isViewingToday: Bool { Calendar.current.isDateInToday(selectedLogDate) }
    var weightProgress: WeightProgress {
        WeightProgress(
            latestKG: weightEntries.first?.weightKG,
            previousKG: weightEntries.dropFirst().first?.weightKG,
            startingKG: weightEntries.last?.weightKG ?? draft.currentWeightKG,
            targetKG: draft.goal == .maintain ? nil : draft.targetWeightKG,
            goal: draft.goal
        )
    }

    let configuration: AppConfiguration
    let service: PlanService
    let cache = PlanCache()
    private let isCICOPreview: Bool

    init(configuration: AppConfiguration = .live()) {
        self.configuration = configuration
        self.service = PlanService(configuration: configuration)
        self.isCICOPreview = ProcessInfo.processInfo.arguments.contains("-CICOPreview")
        if isCICOPreview { configureCICOPreview() }
    }

    func restore() async {
        if isCICOPreview { return }
        guard await service.currentUserID() != nil else {
            isAuthenticated = false
            route = .onboarding
            return
        }
        isAuthenticated = true
        if let cloud = try? await service.fetchCloudState() {
            currentPlan = cloud.0; apply(cloud.1); try? await cache.save(cloud.0, input: cloud.1); route = .dashboard
        } else if let cached = await cache.load() {
            currentPlan = cached.plan; apply(cached.input); route = .dashboard
        } else {
            route = .onboarding
        }
        if route == .dashboard {
            async let daily: Void = loadDailyLog()
            async let weights: Void = loadWeightHistory()
            async let contribution: Void = loadDataContributionStatus()
            _ = await (daily, weights, contribution)
            await loadMorningCheckIn(presentWhenNeeded: true)
        }
    }

    func presentAuthentication(_ purpose: AuthenticationPurpose) {
        authenticationPurpose = purpose
        errorMessage = nil
        statusMessage = nil
        saveState = .idle
        showAuthentication = true
    }

    func calculatePreview() -> Bool {
        do {
            preview = try NutritionCalculator.calculate(input: draft.input)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createAccount() async {
        guard validateCredentials(confirmPassword: true) else { return }
        await perform(.creatingAccount) {
            let needsConfirmation = try await service.createAccount(
                email: normalizedEmail,
                password: password
            )
            if needsConfirmation {
                saveState = .awaitingConfirmation
            } else {
                try await saveAuthenticatedDraft()
            }
        }
    }

    func resendAccountConfirmation() async {
        statusMessage = nil
        await perform(.resendingConfirmation) {
            try await service.resendAccountConfirmation(email: normalizedEmail)
            statusMessage = "A new confirmation email was sent to \(normalizedEmail)."
            saveState = .awaitingConfirmation
        }
        // A failed resend should keep the confirmation instructions and inline error visible.
        if errorMessage != nil { saveState = .awaitingConfirmation }
    }

    func finishConfirmedAccount() async {
        await perform(.authenticating) {
            let accessToken = try await service.signIn(email: normalizedEmail, password: password)
            try await saveAuthenticatedDraft(accessToken: accessToken)
        }
    }

    func signInAndSave() async {
        guard validateCredentials(confirmPassword: false) else { return }
        await perform(.authenticating) {
            let accessToken = try await service.signIn(email: normalizedEmail, password: password)
            try await saveAuthenticatedDraft(accessToken: accessToken)
        }
    }

    func signInAndLoadAccount() async {
        guard validateCredentials(confirmPassword: false) else { return }
        await perform(.authenticating) {
            let accessToken = try await service.signIn(email: normalizedEmail, password: password)
            try await loadAuthenticatedAccount(accessToken: accessToken)
        }
    }

    func saveAfterApple(identityToken: String, nonce: String) async {
        await perform(.authenticating) {
            let accessToken = try await service.signInWithApple(identityToken: identityToken, nonce: nonce)
            try await saveAuthenticatedDraft(accessToken: accessToken)
        }
    }

    func loadAfterApple(identityToken: String, nonce: String) async {
        await perform(.authenticating) {
            let accessToken = try await service.signInWithApple(identityToken: identityToken, nonce: nonce)
            try await loadAuthenticatedAccount(accessToken: accessToken)
        }
    }

    func saveAuthenticatedDraft(accessToken: String? = nil) async throws {
        saveState = .saving
        let plan = try await service.savePlan(draft.input, accessToken: accessToken)
        try await cache.save(plan, input: draft.input)
        currentPlan = plan
        isAuthenticated = true
        preview = nil
        showAuthentication = false
        route = .dashboard
        selectedLogDate = Calendar.current.startOfDay(for: .now)
        await loadDailyLog()
        await loadWeightHistory()
        await loadMorningCheckIn(presentWhenNeeded: true)
    }

    func editPlan() {
        route = .onboarding
        preview = nil
        draft.step = .goal
        draft.isEditing = true
    }

    func loadDailyLog() async {
        guard route == .dashboard else { return }
        isDailyLoading = true
        dailyErrorMessage = nil
        do {
            async let entries = service.fetchFoodEntries(on: selectedLogDate)
            if isViewingToday {
                dailyPlan = currentPlan
            } else {
                let calendar = Calendar.current
                let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: selectedLogDate)) ?? selectedLogDate
                dailyPlan = try await service.fetchPlan(activeAt: endOfDay)
            }
            let loadedEntries = try await entries
            foodEntries = loadedEntries.sorted { $0.consumedAt < $1.consumedAt }
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
        }
        isDailyLoading = false
    }

    func moveLogDate(by days: Int) async {
        let calendar = Calendar.current
        guard let candidate = calendar.date(byAdding: .day, value: days, to: selectedLogDate) else { return }
        let today = calendar.startOfDay(for: .now)
        selectedLogDate = min(calendar.startOfDay(for: candidate), today)
        await loadDailyLog()
    }

    func createFoodEntry(_ input: FoodEntryInput) async -> Bool {
        guard input.isValid else { dailyErrorMessage = "Enter a food name and calories between 1 and 10,000."; return false }
        isFoodMutationInProgress = true
        dailyErrorMessage = nil
        do {
            let entry = try await service.createFoodEntry(input, on: selectedLogDate)
            foodEntries.append(entry)
            foodEntries.sort { $0.consumedAt < $1.consumedAt }
            isFoodMutationInProgress = false
            return true
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
            if case PlanService.ServiceError.notAuthenticated = error {
                isAuthenticated = false
                presentAuthentication(.accessExistingAccount)
            }
            isFoodMutationInProgress = false
            return false
        }
    }

    func searchProducts(_ query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { productSearchResults = []; return }
        isProductLoading = true
        productErrorMessage = nil
        do { productSearchResults = try await service.searchProducts(normalized) }
        catch { productErrorMessage = userFacingMessage(for: error) }
        isProductLoading = false
    }

    func lookupProduct(barcode: String) async -> ProductSummary? {
        isProductLoading = true
        productErrorMessage = nil
        defer { isProductLoading = false }
        do { return try await service.lookupProduct(barcode: barcode) }
        catch { productErrorMessage = userFacingMessage(for: error); return nil }
    }

    func loadProductDetail(_ product: ProductSummary) async -> ProductDetail? {
        isProductLoading = true
        productErrorMessage = nil
        defer { isProductLoading = false }
        do { return try await service.productDetail(for: product) }
        catch { productErrorMessage = userFacingMessage(for: error); return nil }
    }

    func loadProductHistory() async {
        guard isAuthenticated else { return }
        do { productHistory = try await service.fetchProductHistory() }
        catch { productErrorMessage = userFacingMessage(for: error) }
    }

    func logProduct(_ product: ProductDetail, grams: Double, consumedAt: Date, mealType: MealType) async -> Bool {
        isFoodMutationInProgress = true
        productErrorMessage = nil
        defer { isFoodMutationInProgress = false }
        do {
            let entry = try await service.logProduct(product, grams: grams, consumedAt: consumedAt, localDate: selectedLogDate, mealType: mealType)
            foodEntries.append(entry)
            foodEntries.sort { $0.consumedAt < $1.consumedAt }
            return true
        } catch {
            productErrorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func updateFoodEntry(_ entry: FoodEntry, input: FoodEntryInput) async -> Bool {
        guard input.isValid else { dailyErrorMessage = "Enter a food name and calories between 1 and 10,000."; return false }
        isFoodMutationInProgress = true
        dailyErrorMessage = nil
        do {
            let updated = try await service.updateFoodEntry(id: entry.id, input: input, on: selectedLogDate)
            if let index = foodEntries.firstIndex(where: { $0.id == entry.id }) { foodEntries[index] = updated }
            foodEntries.sort { $0.consumedAt < $1.consumedAt }
            isFoodMutationInProgress = false
            return true
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
            isFoodMutationInProgress = false
            return false
        }
    }

    func deleteFoodEntry(_ entry: FoodEntry) async {
        isFoodMutationInProgress = true
        dailyErrorMessage = nil
        do {
            try await service.deleteFoodEntry(id: entry.id)
            foodEntries.removeAll { $0.id == entry.id }
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
        }
        isFoodMutationInProgress = false
    }

    func loadWeightHistory() async {
        guard route == .dashboard else { return }
        isWeightLoading = true
        weightErrorMessage = nil
        do {
            let entries = try await service.fetchWeightEntries()
            weightEntries = entries.sorted { $0.recordedOn > $1.recordedOn }
        } catch {
            weightErrorMessage = userFacingMessage(for: error)
        }
        isWeightLoading = false
    }

    func loadMorningCheckIn(presentWhenNeeded: Bool) async {
        guard route == .dashboard else { return }
        if isCICOPreview { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }
        do {
            async let entries = service.fetchFoodEntries(on: yesterday)
            async let intakeDay = service.fetchIntakeDay(on: yesterday)
            async let adjustment = service.fetchLatestPlanAdjustment()
            let (loadedEntries, loadedDay, loadedAdjustment) = try await (entries, intakeDay, adjustment)
            let todayWeight = weightEntries.first { calendar.isDate($0.recordedOn, inSameDayAs: today) }
            let state = MorningCheckIn(
                reviewDate: yesterday,
                entries: loadedEntries,
                intakeDay: loadedDay,
                todayWeight: todayWeight
            )
            morningCheckIn = state
            planAdjustmentNotice = loadedAdjustment
            hasMorningCheckInReminder = state.needsIntakeReview || state.needsWeight
            if presentWhenNeeded, hasMorningCheckInReminder,
               lastPromptedCheckInDay.map({ !calendar.isDate($0, inSameDayAs: today) }) ?? true {
                lastPromptedCheckInDay = today
                showMorningCheckIn = true
            }
        } catch {
            checkInErrorMessage = userFacingMessage(for: error)
        }
    }

    func reviewYesterday(as status: IntakeDayStatus) async -> Bool {
        guard let morningCheckIn else { return false }
        if isCICOPreview {
            let now = Date()
            let complete = status == .confirmed || status == .fasted
            let day = DailyIntakeDay(
                userID: UUID(), localDate: morningCheckIn.reviewDate, status: status,
                confirmedCalories: complete ? (status == .fasted ? 0 : morningCheckIn.calorieTotal) : nil,
                confirmedItemCount: complete ? (status == .fasted ? 0 : morningCheckIn.entries.count) : nil,
                timeZone: Calendar.current.timeZone.identifier, revision: 1,
                confirmedAt: complete ? now : nil, createdAt: now, updatedAt: now
            )
            self.morningCheckIn = MorningCheckIn(
                reviewDate: morningCheckIn.reviewDate,
                entries: morningCheckIn.entries,
                intakeDay: day,
                todayWeight: nil
            )
            return true
        }
        isCheckInMutationInProgress = true
        checkInErrorMessage = nil
        do {
            let response = try await service.updateDailyCheckIn(status: status, on: morningCheckIn.reviewDate)
            try await applyAdaptiveResponse(response)
            await loadMorningCheckIn(presentWhenNeeded: false)
            isCheckInMutationInProgress = false
            return true
        } catch {
            checkInErrorMessage = userFacingMessage(for: error)
            isCheckInMutationInProgress = false
            return false
        }
    }

    func dismissMorningCheckIn() {
        showMorningCheckIn = false
        hasMorningCheckInReminder = morningCheckIn?.needsIntakeReview == true || morningCheckIn?.needsWeight == true
    }

    func presentMorningCheckIn() {
        checkInErrorMessage = nil
        showMorningCheckIn = true
    }

    func acknowledgePlanAdjustment() async {
        guard let notice = planAdjustmentNotice else { return }
        do {
            try await service.acknowledgePlanAdjustment(id: notice.id)
            planAdjustmentNotice = nil
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
        }
    }

    func saveWeightEntry(_ entry: WeightEntry?, weightKG: Double, recordedOn: Date) async -> Bool {
        guard (35...350).contains(weightKG), recordedOn <= .now else {
            weightErrorMessage = "Enter a valid weight and choose today or an earlier date."
            return false
        }
        isWeightMutationInProgress = true
        weightErrorMessage = nil
        do {
            let response = try await service.saveWeightEntry(id: entry?.id, weightKG: weightKG, recordedOn: recordedOn)
            try await applyWeightMutation(response)
            let adaptive = try await service.refreshAdaptiveTarget()
            try await applyAdaptiveResponse(adaptive)
            await loadMorningCheckIn(presentWhenNeeded: false)
            isWeightMutationInProgress = false
            return true
        } catch {
            weightErrorMessage = userFacingMessage(for: error)
            isWeightMutationInProgress = false
            return false
        }
    }

    func deleteWeightEntry(_ entry: WeightEntry) async {
        guard entry.source != .baseline else { return }
        isWeightMutationInProgress = true
        weightErrorMessage = nil
        do {
            let response = try await service.deleteWeightEntry(id: entry.id)
            try await applyWeightMutation(response)
        } catch {
            weightErrorMessage = userFacingMessage(for: error)
        }
        isWeightMutationInProgress = false
    }

    func loadDataContributionStatus() async {
        guard isAuthenticated, !isCICOPreview else { return }
        isDataContributionLoading = true
        dataContributionErrorMessage = nil
        do {
            dataContributionStatus = try await service.fetchDataContributionStatus()
        } catch {
            dataContributionErrorMessage = userFacingMessage(for: error)
        }
        isDataContributionLoading = false
    }

    func joinDataContribution(countryCode: String, regionCode: String?) async -> Bool {
        isDataContributionLoading = true
        dataContributionErrorMessage = nil
        do {
            dataContributionStatus = try await service.joinDataContribution(
                countryCode: countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                regionCode: regionCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            )
            isDataContributionLoading = false
            return true
        } catch {
            dataContributionErrorMessage = userFacingMessage(for: error)
            isDataContributionLoading = false
            return false
        }
    }

    func leaveDataContribution() async {
        isDataContributionLoading = true
        dataContributionErrorMessage = nil
        do {
            dataContributionStatus = try await service.leaveDataContribution()
        } catch {
            dataContributionErrorMessage = userFacingMessage(for: error)
        }
        isDataContributionLoading = false
    }

    func signOut() async {
        do { try await service.signOut() } catch { errorMessage = error.localizedDescription }
        await cache.clear()
        resetToOnboarding()
    }

    func deleteAccount() async {
        await perform(.deleting) { try await service.deleteAccount() }
        guard errorMessage == nil else { return }
        await cache.clear()
        resetToOnboarding()
    }

    private func resetToOnboarding() {
        currentPlan = nil; preview = nil; foodEntries = []; weightEntries = []; dailyPlan = nil
        productSearchResults = []; productHistory = []; productErrorMessage = nil
        morningCheckIn = nil; planAdjustmentNotice = nil; showMorningCheckIn = false
        dataContributionStatus = nil; dataContributionErrorMessage = nil
        isAuthenticated = false
        draft = OnboardingDraft(); route = .onboarding
    }

    private func loadAuthenticatedAccount(accessToken: String) async throws {
        let cloud = try await service.fetchCloudState(accessToken: accessToken)
        isAuthenticated = true
        showAuthentication = false
        selectedLogDate = Calendar.current.startOfDay(for: .now)

        guard let cloud else {
            await cache.clear()
            currentPlan = nil
            preview = nil
            foodEntries = []
            dailyPlan = nil
            draft = OnboardingDraft()
            statusMessage = "You’re signed in. Let’s create your first plan."
            route = .onboarding
            return
        }

        currentPlan = cloud.0
        apply(cloud.1)
        try await cache.save(cloud.0, input: cloud.1)
        preview = nil
        route = .dashboard
        async let daily: Void = loadDailyLog()
        async let weights: Void = loadWeightHistory()
        async let contribution: Void = loadDataContributionStatus()
        _ = await (daily, weights, contribution)
        await loadMorningCheckIn(presentWhenNeeded: true)
    }

    private func applyWeightMutation(_ response: WeightMutationResponse) async throws {
        if let input = response.planInput { apply(input) }
        if let plan = response.plan {
            currentPlan = plan
            if isViewingToday { dailyPlan = plan }
        }
        if let currentPlan { try await cache.save(currentPlan, input: draft.input) }
        lastWeightOutcome = response.outcome
        weightStatusMessage = switch response.outcome {
        case .tracked: "Weight history updated."
        case .planUpdated: "Your nutrition targets were updated for your latest weight."
        case .goalReached: "Goal reached—Leafy switched your plan to maintenance."
        case .reviewRequired: "Weight saved. Review your plan before changing nutrition targets."
        }
        await loadWeightHistory()
    }

    private func applyAdaptiveResponse(_ response: DailyCheckInResponse) async throws {
        if let plan = response.plan {
            currentPlan = plan
            if isViewingToday { dailyPlan = plan }
            try await cache.save(plan, input: draft.input)
        }
        if let adjustment = response.adjustment { planAdjustmentNotice = adjustment }
    }

    private func apply(_ input: NutritionPlanInput) {
        draft.birthDate = input.birthDate; draft.calculationSex = input.calculationSex
        draft.heightCM = input.heightCM; draft.currentWeightKG = input.currentWeightKG
        draft.targetWeightKG = input.targetWeightKG ?? input.currentWeightKG
        draft.activityLevel = input.activityLevel; draft.goal = input.goal; draft.pace = input.pace; draft.unitSystem = input.unitSystem
    }

    private func perform(_ state: SaveState, operation: () async throws -> Void) async {
        saveState = state; errorMessage = nil
        do { try await operation() } catch { errorMessage = userFacingMessage(for: error) }
        if saveState != .awaitingConfirmation { saveState = .idle }
    }

    private func userFacingMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("email rate limit") {
            return "Leafy’s shared email allowance has been reached. Supabase’s built-in mail service allows only two emails per hour, so try again later or use the most recent confirmation email."
        }
        if message.localizedCaseInsensitiveContains("email not confirmed") {
            return "Confirm your email using the link we sent, then try again."
        }
        return message
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validateCredentials(confirmPassword: Bool) -> Bool {
        guard normalizedEmail.contains("@") else { errorMessage = "Enter a valid email address."; return false }
        guard password.count >= 8 else { errorMessage = "Password must be at least 8 characters."; return false }
        guard !confirmPassword || password == passwordConfirmation else {
            errorMessage = "Passwords do not match."
            return false
        }
        return true
    }

    private func configureCICOPreview() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let userID = UUID()
        let plan = NutritionPlan(
            id: UUID(), revision: 2, calculatorVersion: "msj-amdr-v1",
            bmrKcal: 1_650, tdeeKcal: 2_250, calorieTargetKcal: 1_850,
            proteinG: 127, carbohydrateG: 208, fatG: 57,
            projectedWeeklyChangeKG: 0.36, estimatedGoalDate: nil, createdAt: .now
        )
        let breakfast = FoodEntry(
            id: UUID(), userID: userID, name: "Greek yogurt and berries", calories: 310,
            consumedAt: calendar.date(bySettingHour: 8, minute: 15, second: 0, of: yesterday) ?? yesterday,
            localDate: PlanService.localDayString(for: yesterday), timeZone: calendar.timeZone.identifier,
            createdAt: .now, updatedAt: .now
        )
        let dinner = FoodEntry(
            id: UUID(), userID: userID, name: "Chicken rice bowl", calories: 720,
            consumedAt: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: yesterday) ?? yesterday,
            localDate: PlanService.localDayString(for: yesterday), timeZone: calendar.timeZone.identifier,
            createdAt: .now, updatedAt: .now
        )
        currentPlan = plan
        dailyPlan = plan
        selectedLogDate = today
        route = .dashboard
        isAuthenticated = true
        foodEntries = []
        morningCheckIn = MorningCheckIn(reviewDate: yesterday, entries: [breakfast, dinner], intakeDay: nil, todayWeight: nil)
        hasMorningCheckInReminder = true
        showMorningCheckIn = !ProcessInfo.processInfo.arguments.contains("-SkipMorningCheckIn")
    }
}
