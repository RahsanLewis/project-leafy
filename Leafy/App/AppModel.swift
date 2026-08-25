import Foundation
import GoogleSignIn
import Observation

@MainActor @Observable
final class AppModel {
    enum Route: Equatable { case launching, onboarding, dashboard }
    enum AuthenticationPurpose: Equatable { case savePlan, accessExistingAccount }
    enum SaveState: Equatable { case idle, creatingAccount, awaitingConfirmation, resendingConfirmation, authenticating, saving, deleting }
    enum MealEstimateActivity: Equatable { case idle, analyzing, refining, saving }
    private enum MorningCheckInLoggingHandoff { case idle, awaitingLogger, logging }

    var route: Route = .launching
    var draft = OnboardingDraft()
    var preview: NutritionPlan?
    var currentPlan: NutritionPlan?
    var selectedLogDate = Calendar.current.startOfDay(for: .now)
    var foodEntries: [FoodEntry] = []
    var weightEntries: [WeightEntry] = []
    var dailyPlan: NutritionPlan?
    var dailyNutrition: DailyNutritionSummary?
    var isNutrientAutoFillLoading = false
    var nutrientAutoFillError: String?
    var morningCheckIn: MorningCheckIn?
    var showMorningCheckIn = false
    var hasMorningCheckInReminder = false
    var planAdjustmentNotice: PlanAdjustmentNotice?
    var isCheckInMutationInProgress = false
    var checkInErrorMessage: String?
    var isDailyLoading = false
    var isFoodMutationInProgress = false
    var productSearchResults: [ProductSummary] = []
    var recentLoggingFoods: [ProductSummary] = []
    var productHistory: [ProductSummary] = []
    var isProductLoading = false
    var productErrorMessage: String?
    var catalogContributions: [CatalogContribution] = []
    var isCatalogContributionLoading = false
    var catalogContributionErrorMessage: String?
    var mealEstimate: MealEstimate?
    var mealEstimateActivity: MealEstimateActivity = .idle
    var isMealEstimateLoading: Bool { mealEstimateActivity != .idle }
    var mealEstimateErrorMessage: String?
    var chatThreads: [NutritionChatThread] = []
    var activeChatThreadID: UUID?
    var chatMessages: [NutritionChatMessage] = []
    var isChatLoading = false
    var chatErrorMessage: String?
    var chatMealLoggingMessageID: UUID?
    var pendingChatClientMessageID: UUID?
    var pendingChatText: String?
    var showLogFood = false
    var pendingMealDescription = ""
    private var mealEstimateSessionID: UUID?
    private var mealPhotoObjectPath: String?
    private var mealEstimateLogDate = Calendar.current.startOfDay(for: .now)
    var isWeightLoading = false
    var isWeightMutationInProgress = false
    var weightErrorMessage: String?
    var weightErrorTitle = "We couldn’t update your weight"
    var weightStatusMessage: String?
    var weightNutritionContext: WeightNutritionContext?
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
    var account: LeafyAccount?
    var termsAccepted = false
    var privacyAccepted = false
    var coreDataAccepted = false
    var showCoreDataAcknowledgment = false
    var isCoreDataAcknowledgmentLoading = false
    var coreDataAcknowledgmentError: String?
    var authFlowState: AuthFlowState = .signedOut
    var showPasswordRecovery = false
    let pendingOnboardingCache = PendingOnboardingCache()
    private var authObserverTask: Task<Void, Never>?
    private var lastPromptedCheckInDay: Date?
    private var morningCheckInLoggingHandoff = MorningCheckInLoggingHandoff.idle
    private var logDateBeforeMorningCheckInHandoff: Date?
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
        if ProcessInfo.processInfo.arguments.contains("-ForceOnboarding") {
            route = .onboarding
            return
        }
        observeAuthentication()
        guard await service.currentUserID() != nil else {
            isAuthenticated = false
            if let pending = await pendingOnboardingCache.load() {
                apply(pending.input)
                if let stepID = pending.stepID, let step = OnboardingDraft.Step(rawValue: stepID) {
                    draft.step = step
                } else if let legacyStep = pending.stepRawValue {
                    draft.step = OnboardingDraft.Step.legacy(legacyStep, draft: draft)
                } else {
                    draft.step = .results
                }
                termsAccepted = pending.termsAccepted
                privacyAccepted = pending.privacyAccepted
                coreDataAccepted = pending.coreDataAccepted
                _ = calculatePreview()
            }
            route = .onboarding
            return
        }
        isAuthenticated = true
        authFlowState = .authenticated
        account = try? await service.account()
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
            _ = await (daily, weights)
            await refreshCoreDataUseStatus()
            await loadMorningCheckIn(presentWhenNeeded: !showCoreDataAcknowledgment)
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
        guard termsAccepted, privacyAccepted, coreDataAccepted else {
            errorMessage = "Accept the required agreements before creating your account."
            return
        }
        guard validateCredentials(confirmPassword: true) else { return }
        await perform(.creatingAccount) {
            let needsConfirmation = try await service.createAccount(
                email: normalizedEmail,
                password: password
            )
            if needsConfirmation {
                authFlowState = .awaitingEmailConfirmation(normalizedEmail)
                saveState = .awaitingConfirmation
            } else {
                try await saveAuthenticatedDraft(recordLegalAcceptance: true)
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
            try await saveAuthenticatedDraft(accessToken: accessToken, recordLegalAcceptance: true)
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
            try await saveAuthenticatedDraft(accessToken: accessToken, recordLegalAcceptance: true)
        }
    }

    func loadAfterApple(identityToken: String, nonce: String) async {
        await perform(.authenticating) {
            let accessToken = try await service.signInWithApple(identityToken: identityToken, nonce: nonce)
            try await loadAuthenticatedAccount(accessToken: accessToken)
        }
    }

    func saveAfterGoogle(identityToken: String, accessToken: String, nonce: String) async {
        await perform(.authenticating) {
            let sessionAccessToken = try await service.signInWithGoogle(
                identityToken: identityToken,
                accessToken: accessToken,
                nonce: nonce
            )
            try await saveAuthenticatedDraft(accessToken: sessionAccessToken, recordLegalAcceptance: true)
        }
    }

    func loadAfterGoogle(identityToken: String, accessToken: String, nonce: String) async {
        await perform(.authenticating) {
            let sessionAccessToken = try await service.signInWithGoogle(
                identityToken: identityToken,
                accessToken: accessToken,
                nonce: nonce
            )
            try await loadAuthenticatedAccount(accessToken: sessionAccessToken)
        }
    }

    func saveAuthenticatedDraft(accessToken: String? = nil, recordLegalAcceptance: Bool = false) async throws {
        saveState = .saving
        let plan = try await service.savePlan(draft.input, accessToken: accessToken, recordLegalAcceptance: recordLegalAcceptance)
        try await cache.save(plan, input: draft.input)
        currentPlan = plan
        isAuthenticated = true
        authFlowState = .authenticated
        account = try? await service.account()
        await pendingOnboardingCache.clear()
        preview = nil
        showAuthentication = false
        route = .dashboard
        showCoreDataAcknowledgment = false
        selectedLogDate = Calendar.current.startOfDay(for: .now)
        await loadDailyLog()
        await loadWeightHistory()
        await loadMorningCheckIn(presentWhenNeeded: true)
    }

    func updateAuthenticatedPlan(input: NutritionPlanInput) async throws {
        guard await service.currentUserID() != nil else { throw PlanService.ServiceError.notAuthenticated }
        saveState = .saving
        defer { saveState = .idle }
        let plan = try await service.savePlan(input)
        try await cache.save(plan, input: input)
        currentPlan = plan
        if isViewingToday { dailyPlan = plan }
        apply(input)
    }

    func loadDailyLog() async {
        guard route == .dashboard else { return }
        isDailyLoading = true
        dailyErrorMessage = nil
        do {
            async let loadedDay = dailyLog(for: selectedLogDate)
            async let loadedNutrition = service.fetchDailyNutrition(on: selectedLogDate)
            let loaded = try await loadedDay
            dailyPlan = loaded.plan
            foodEntries = loaded.entries
            dailyNutrition = try? await loadedNutrition
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
        }
        isDailyLoading = false
    }

    @discardableResult
    func moveLogDate(by days: Int) async -> Bool {
        let calendar = Calendar.current
        guard let candidate = calendar.date(byAdding: .day, value: days, to: selectedLogDate) else { return false }
        let today = calendar.startOfDay(for: .now)
        let destination = min(calendar.startOfDay(for: candidate), today)
        guard destination != selectedLogDate else { return false }

        if isCICOPreview {
            selectedLogDate = destination
            dailyPlan = currentPlan
            foodEntries = []
            dailyNutrition = Self.previewDailyNutrition(plan: currentPlan)
            return true
        }

        isDailyLoading = true
        dailyErrorMessage = nil
        defer { isDailyLoading = false }
        do {
            let loaded = try await dailyLog(for: destination)
            selectedLogDate = destination
            dailyPlan = loaded.plan
            foodEntries = loaded.entries
            dailyNutrition = try? await service.fetchDailyNutrition(on: destination)
            return true
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
            return false
        }
    }

    private func dailyLog(for date: Date) async throws -> (plan: NutritionPlan?, entries: [FoodEntry]) {
        async let entries = service.fetchFoodEntries(on: date)
        let plan: NutritionPlan?
        if Calendar.current.isDateInToday(date) {
            plan = currentPlan
        } else {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: day) ?? date
            plan = try await service.fetchPlan(activeAt: endOfDay)
        }
        return (plan, try await entries.sorted { $0.consumedAt < $1.consumedAt })
    }

    func createFoodEntry(_ input: FoodEntryInput) async -> Bool {
        guard input.isValid else { dailyErrorMessage = "Enter a food name and calories between 1 and 10,000."; return false }
        isFoodMutationInProgress = true
        dailyErrorMessage = nil
        if isCICOPreview {
            let entry = FoodEntry(
                id: UUID(), userID: UUID(), name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: input.calories, consumedAt: input.consumedAt,
                localDate: PlanService.localDayString(for: selectedLogDate),
                timeZone: Calendar.current.timeZone.identifier,
                createdAt: .now, updatedAt: .now,
                amount: input.amount, amountUnit: input.amountUnit,
                gramWeight: input.gramWeight, portionDescription: input.portionDescription,
                mealType: input.mealType
            )
            foodEntries.append(entry)
            foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyNutrition = Self.previewDailyNutrition(plan: dailyPlan)
            isFoodMutationInProgress = false
            return true
        }
        do {
            let entry = try await service.createFoodEntry(input, on: selectedLogDate)
            foodEntries.append(entry)
            foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyNutrition = try? await service.fetchDailyNutrition(on: selectedLogDate)
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

    func loadProductDetail(for entry: FoodEntry) async -> ProductDetail? {
        guard let foodVersionID = entry.canonicalFoodVersionID else { return nil }
        isProductLoading = true
        productErrorMessage = nil
        defer { isProductLoading = false }
        do { return try await service.productDetail(foodVersionID: foodVersionID) }
        catch { productErrorMessage = userFacingMessage(for: error); return nil }
    }

    func loadProductDetail(foodVersionID: UUID) async -> ProductDetail? {
        isProductLoading = true; productErrorMessage = nil
        defer { isProductLoading = false }
        do { return try await service.productDetail(foodVersionID: foodVersionID) }
        catch { productErrorMessage = userFacingMessage(for: error); return nil }
    }

    func startCatalogContribution(barcode: String, refreshExisting: Bool = false) async -> CatalogContributionStartResponse? {
        guard !isCICOPreview else { return nil }
        isCatalogContributionLoading = true; catalogContributionErrorMessage = nil
        defer { isCatalogContributionLoading = false }
        do { return try await service.startCatalogContribution(barcode: barcode, refreshExisting: refreshExisting) }
        catch { catalogContributionErrorMessage = userFacingMessage(for: error); return nil }
    }

    func uploadCatalogPhoto(_ data: Data, contributionID: UUID, assetKind: String) async -> CatalogContribution? {
        isCatalogContributionLoading = true; catalogContributionErrorMessage = nil
        defer { isCatalogContributionLoading = false }
        do { return try await service.uploadCatalogLabelPhoto(data, contributionID: contributionID, assetKind: assetKind) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            catalogContributionErrorMessage = userFacingMessage(for: error); return nil
        }
    }

    func extractCatalogContribution(id: UUID) async -> CatalogContribution? {
        isCatalogContributionLoading = true; catalogContributionErrorMessage = nil
        defer { isCatalogContributionLoading = false }
        do { return try await service.extractCatalogContribution(id: id) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            catalogContributionErrorMessage = userFacingMessage(for: error); return nil
        }
    }

    func enqueueCatalogContribution(
        id: UUID,
        servingCount: Double?,
        consumedAt: Date?,
        mealType: MealType?
    ) async -> CatalogContributionSubmitResponse? {
        isCatalogContributionLoading = true; catalogContributionErrorMessage = nil
        defer { isCatalogContributionLoading = false }
        do {
            let result = try await service.enqueueCatalogContribution(
                id: id,
                servingCount: servingCount,
                consumedAt: consumedAt,
                localDate: servingCount == nil ? nil : selectedLogDate,
                mealType: mealType
            )
            await loadCatalogContributions()
            return result
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            catalogContributionErrorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    func submitCatalogContribution(id: UUID, fields: CatalogContributionFields, nutrients: [CatalogContributionNutrient]) async -> CatalogContributionSubmitResponse? {
        isCatalogContributionLoading = true; catalogContributionErrorMessage = nil
        defer { isCatalogContributionLoading = false }
        do {
            let result = try await service.submitCatalogContribution(id: id, fields: fields, nutrients: nutrients)
            await loadCatalogContributions()
            return result
        } catch { catalogContributionErrorMessage = userFacingMessage(for: error); return nil }
    }

    func loadCatalogContributions() async {
        guard !isCICOPreview else { catalogContributions = []; return }
        isCatalogContributionLoading = true; catalogContributionErrorMessage = nil
        defer { isCatalogContributionLoading = false }
        do { catalogContributions = try await service.fetchCatalogContributions() }
        catch { catalogContributionErrorMessage = userFacingMessage(for: error) }
    }

    func deleteCatalogContribution(id: UUID) async -> Bool {
        isCatalogContributionLoading = true; catalogContributionErrorMessage = nil
        defer { isCatalogContributionLoading = false }
        do {
            try await service.deleteCatalogContribution(id: id)
            catalogContributions.removeAll { $0.id == id }
            return true
        } catch { catalogContributionErrorMessage = userFacingMessage(for: error); return false }
    }

    func logCatalogContribution(_ contribution: CatalogContribution, grams: Double, consumedAt: Date, mealType: MealType) async -> Bool {
        isFoodMutationInProgress = true; catalogContributionErrorMessage = nil
        defer { isFoodMutationInProgress = false }
        do {
            let entry = try await service.logCatalogContribution(contribution, grams: grams, consumedAt: consumedAt, localDate: selectedLogDate, mealType: mealType)
            foodEntries.append(entry); foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyNutrition = try? await service.fetchDailyNutrition(on: selectedLogDate)
            return true
        } catch { catalogContributionErrorMessage = userFacingMessage(for: error); return false }
    }

    func loadNutrients(for entry: FoodEntry) async -> [NutrientAmountInput] {
        if isCICOPreview { return dailyNutrition?.nutrients.map {
            NutrientAmountInput(
                code: $0.code, amount: $0.amount,
                derivationMethod: $0.hasEstimate ? .estimated : .calculated,
                confidence: $0.confidence
            )
        } ?? [] }
        return (try? await service.fetchFoodEntryNutrients(entryID: entry.id)) ?? []
    }

    func loadScore(for entry: FoodEntry) async -> ProductNutritionScore? {
        guard !isCICOPreview else { return entry.score }
        return (try? await service.fetchFoodEntryScore(entryID: entry.id)) ?? entry.score
    }

    func loadProductHistory() async {
        guard isAuthenticated else { return }
        do { productHistory = try await service.fetchProductHistory() }
        catch { productErrorMessage = userFacingMessage(for: error) }
    }

    func loadRecentLoggingFoods() async {
        guard isAuthenticated else { return }
        do { recentLoggingFoods = try await service.fetchRecentLoggingFoods() }
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
            dailyNutrition = try? await service.fetchDailyNutrition(on: selectedLogDate)
            return true
        } catch {
            productErrorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func analyzeMeal(
        description: String,
        photoData: Data?,
        consumedAt: Date,
        localDate: Date,
        mealType: MealType
    ) async -> Bool {
        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDescription.isEmpty || photoData != nil else {
            mealEstimateErrorMessage = "Add a photo or describe what you ate."
            return false
        }
        mealEstimateActivity = .analyzing
        mealEstimateErrorMessage = nil
        defer { mealEstimateActivity = .idle }
        let sessionID = mealEstimateSessionID ?? UUID()
        mealEstimateSessionID = sessionID
        mealEstimateLogDate = Calendar.current.startOfDay(for: localDate)
        if isCICOPreview {
            if ProcessInfo.processInfo.arguments.contains("-HoldAIMealEstimate") {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return false }
            }
            mealEstimate = Self.previewMealEstimate(sessionID: sessionID)
            return true
        }
        do {
            if let photoData, mealPhotoObjectPath == nil {
                mealPhotoObjectPath = try await service.uploadMealPhoto(photoData, sessionID: sessionID)
            }
            let input = MealEstimateInput(
                sessionID: sessionID,
                description: normalizedDescription,
                consumedAt: consumedAt,
                localDate: localDate,
                mealType: mealType,
                marketCountry: Locale.current.region?.identifier ?? "US"
            )
            mealEstimate = try await service.estimateMeal(input, photoObjectPath: mealPhotoObjectPath)
            return true
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return false }
            mealEstimateErrorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func answerMealFollowUp(_ answer: String?, skip: Bool = false) async -> Bool {
        guard let sessionID = mealEstimateSessionID else { return false }
        mealEstimateActivity = .refining
        mealEstimateErrorMessage = nil
        defer { mealEstimateActivity = .idle }
        if isCICOPreview {
            if ProcessInfo.processInfo.arguments.contains("-HoldAIMealEstimate") {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return false }
            }
            mealEstimate = Self.previewMealEstimate(sessionID: sessionID, ready: true)
            return true
        }
        do {
            mealEstimate = try await service.answerMealEstimate(sessionID: sessionID, answer: answer, skip: skip)
            return true
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return false }
            mealEstimateErrorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func updateMealEstimateItem(
        id: UUID,
        name: String,
        portion: String,
        calories: Int,
        estimatedGrams: Double?,
        nutrients: [NutrientAmountInput]
    ) {
        guard let index = mealEstimate?.items.firstIndex(where: { $0.id == id }) else { return }
        mealEstimate?.items[index].name = name
        mealEstimate?.items[index].portion = portion
        mealEstimate?.items[index].calories = calories
        mealEstimate?.items[index].estimatedGrams = estimatedGrams
        mealEstimate?.items[index].nutrients = nutrients
    }

    func removeMealEstimateItem(id: UUID) {
        mealEstimate?.items.removeAll { $0.id == id }
    }

    func confirmMealEstimate() async -> Bool {
        guard let estimate = mealEstimate, !estimate.items.isEmpty else {
            mealEstimateErrorMessage = "Keep at least one food item before saving."
            return false
        }
        let items = estimate.items.map {
            MealConfirmationItem(
                id: $0.id, name: $0.name, portion: $0.portion, calories: $0.calories,
                estimatedGrams: $0.estimatedGrams,
                nutrients: $0.nutrients ?? []
            )
        }
        guard items.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (0...10_000).contains($0.calories) }) else {
            mealEstimateErrorMessage = "Check that each food has a name and calories between 0 and 10,000."
            return false
        }
        mealEstimateActivity = .saving
        mealEstimateErrorMessage = nil
        defer { mealEstimateActivity = .idle }
        do {
            let entries: [FoodEntry]
            if isCICOPreview {
                entries = items.map { item in
                    FoodEntry(
                        id: UUID(), userID: UUID(), name: item.name, calories: item.calories,
                        consumedAt: .now, localDate: PlanService.localDayString(for: mealEstimateLogDate),
                        timeZone: Calendar.current.timeZone.identifier, createdAt: .now, updatedAt: .now,
                        portionDescription: item.portion, confidence: 0.7, userConfirmed: true,
                        entrySource: "text_ai", calorieMethod: "estimated"
                    )
                }
            } else {
                entries = try await service.confirmMealEstimate(sessionID: estimate.sessionID, items: items)
            }
            selectedLogDate = mealEstimateLogDate
            if entries.isEmpty { await loadDailyLog() }
            else {
                foodEntries.append(contentsOf: entries)
                foodEntries.sort { $0.consumedAt < $1.consumedAt }
                dailyNutrition = try? await service.fetchDailyNutrition(on: selectedLogDate)
            }
            clearMealEstimateState()
            return true
        } catch {
            mealEstimateErrorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func discardMealEstimate() async {
        guard let sessionID = mealEstimateSessionID else { clearMealEstimateState(); return }
        if !isCICOPreview { try? await service.discardMealEstimate(sessionID: sessionID) }
        clearMealEstimateState()
    }

    func cancelMealEstimateAnalysis() async {
        let sessionID = mealEstimateSessionID
        mealEstimateActivity = .idle
        mealEstimate = nil
        mealEstimateSessionID = nil
        mealPhotoObjectPath = nil
        mealEstimateErrorMessage = nil
        guard let sessionID, !isCICOPreview else { return }
        try? await service.discardMealEstimate(sessionID: sessionID)
    }

    private func clearMealEstimateState() {
        mealEstimate = nil
        mealEstimateSessionID = nil
        mealPhotoObjectPath = nil
        mealEstimateErrorMessage = nil
    }

    func startNewChat() {
        activeChatThreadID = nil
        chatMessages = []
        chatErrorMessage = nil
        pendingChatClientMessageID = nil
        pendingChatText = nil
    }

    func loadChatThreads() async {
        guard !isCICOPreview else { return }
        do { chatThreads = try await service.listNutritionChatThreads() }
        catch { chatErrorMessage = userFacingMessage(for: error) }
    }

    func openChatThread(_ thread: NutritionChatThread) async {
        isChatLoading = true
        chatErrorMessage = nil
        defer { isChatLoading = false }
        if isCICOPreview { activeChatThreadID = thread.id; return }
        do {
            let result = try await service.loadNutritionChatThread(id: thread.id)
            activeChatThreadID = result.thread.id
            chatMessages = result.messages
        } catch { chatErrorMessage = userFacingMessage(for: error) }
    }

    func sendChatMessage(_ text: String, clientMessageID: UUID = UUID()) async -> Bool {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 2_000 else {
            chatErrorMessage = "Keep your question under 2,000 characters."
            return false
        }
        isChatLoading = true
        chatErrorMessage = nil
        pendingChatClientMessageID = clientMessageID
        pendingChatText = message
        let temporaryMessage = NutritionChatMessage(
            id: clientMessageID, role: "user", content: message,
            sources: [], suggestedLogDescription: nil, createdAt: .now
        )
        chatMessages.append(temporaryMessage)
        defer {
            isChatLoading = false
            pendingChatClientMessageID = nil
            pendingChatText = nil
        }
        if isCICOPreview {
            let now = Date.now
            if ProcessInfo.processInfo.arguments.contains("-HoldChatResponse") {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled {
                    chatMessages.removeAll { $0.id == clientMessageID }
                    return false
                }
            }
            let offTopic = message.localizedCaseInsensitiveContains("write code") ||
                message.localizedCaseInsensitiveContains("stock portfolio")
            let eaten = message.localizedCaseInsensitiveContains("ate")
            let previewEstimate = eaten ? Self.previewMealEstimate(sessionID: UUID(), ready: true) : nil
            chatMessages.append(NutritionChatMessage(
                id: UUID(), role: "assistant",
                content: offTopic
                    ? "I’m focused on nutrition and health, so I can’t help with that. I can help you plan what to eat or talk through a health question."
                    : eaten
                    ? "Here’s an estimate based on what you described. Review the portions before logging it."
                    : "Based on your current plan, aim for protein-rich foods you enjoy and use your remaining calorie budget to guide the portion.",
                sources: offTopic ? [] : [NutritionChatSource(kind: "plan", label: "Your Leafy plan")],
                suggestedLogDescription: nil,
                mealSuggestion: offTopic ? nil : previewEstimate.map {
                    NutritionChatMealSuggestion(
                        sessionID: $0.sessionID, status: .ready,
                        totalCalories: $0.totalCalories, calorieLow: $0.calorieLow,
                        calorieHigh: $0.calorieHigh, confidence: $0.confidence,
                        assumptions: $0.assumptions, items: $0.items
                    )
                },
                createdAt: now
            ))
            return true
        }
        do {
            let result = try await service.sendNutritionChatMessage(
                message, threadID: activeChatThreadID, clientMessageID: clientMessageID
            )
            chatMessages.removeAll { $0.id == clientMessageID }
            activeChatThreadID = result.thread.id
            chatMessages.append(contentsOf: [result.userMessage, result.assistantMessage])
            if let index = chatThreads.firstIndex(where: { $0.id == result.thread.id }) { chatThreads[index] = result.thread }
            else { chatThreads.insert(result.thread, at: 0) }
            return true
        } catch {
            chatMessages.removeAll { $0.id == clientMessageID }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return false }
            chatErrorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func updateChatMealItem(messageID: UUID, itemID: UUID, name: String, portion: String, calories: Int) {
        guard let messageIndex = chatMessages.firstIndex(where: { $0.id == messageID }),
              let itemIndex = chatMessages[messageIndex].mealSuggestion?.items.firstIndex(where: { $0.id == itemID }) else { return }
        chatMessages[messageIndex].mealSuggestion?.items[itemIndex].name = name
        chatMessages[messageIndex].mealSuggestion?.items[itemIndex].portion = portion
        chatMessages[messageIndex].mealSuggestion?.items[itemIndex].calories = calories
    }

    func removeChatMealItem(messageID: UUID, itemID: UUID) {
        guard let index = chatMessages.firstIndex(where: { $0.id == messageID }) else { return }
        chatMessages[index].mealSuggestion?.items.removeAll { $0.id == itemID }
    }

    func chatMealReviewDraft(messageID: UUID, consumedAt: Date = .now) -> ChatMealReviewDraft? {
        guard let suggestion = chatMessages.first(where: { $0.id == messageID })?.mealSuggestion,
              suggestion.status == .ready else { return nil }
        return ChatMealReviewDraft(
            messageID: messageID, sessionID: suggestion.sessionID,
            items: suggestion.items.map(ChatMealReviewItem.init(prediction:)),
            consumedAt: consumedAt
        )
    }

    func confirmChatMeal(_ draft: ChatMealReviewDraft) async -> Bool {
        let messageID = draft.messageID
        guard let messageIndex = chatMessages.firstIndex(where: { $0.id == messageID }),
              let suggestion = chatMessages[messageIndex].mealSuggestion,
              suggestion.status == .ready, draft.isValid else { return false }
        let items = draft.items.map {
            ChatMealConfirmationItem(
                clientItemID: $0.id, predictionID: $0.predictionID,
                name: $0.name, portion: $0.portion, calories: $0.calories,
                nutrients: $0.nutrients, origin: $0.origin
            )
        }
        chatMealLoggingMessageID = messageID
        chatErrorMessage = nil
        defer { chatMealLoggingMessageID = nil }
        do {
            let entries: [FoodEntry]
            if isCICOPreview {
                entries = items.map { item in
                    FoodEntry(
                        id: UUID(), userID: UUID(), name: item.name, calories: item.calories,
                        consumedAt: draft.consumedAt, localDate: PlanService.localDayString(for: draft.consumedAt),
                        timeZone: Calendar.current.timeZone.identifier, createdAt: .now, updatedAt: .now,
                        portionDescription: item.portion, confidence: 0.7, userConfirmed: true,
                        entrySource: "text_ai",
                        calorieMethod: item.origin == .prediction ? "estimated" : "user_entered"
                    )
                }
            } else {
                entries = try await service.confirmChatMealEstimate(
                    sessionID: suggestion.sessionID, items: items, consumedAt: draft.consumedAt
                )
            }
            selectedLogDate = Calendar.current.startOfDay(for: draft.consumedAt)
            foodEntries.append(contentsOf: entries)
            foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyNutrition = try? await service.fetchDailyNutrition(on: selectedLogDate)
            if let refreshedIndex = chatMessages.firstIndex(where: { $0.id == messageID }) {
                chatMessages[refreshedIndex].mealSuggestion?.status = .logged
            }
            return true
        } catch {
            chatErrorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func deleteChatThread(_ thread: NutritionChatThread) async {
        if !isCICOPreview {
            do { try await service.deleteNutritionChatThread(id: thread.id) }
            catch { chatErrorMessage = userFacingMessage(for: error); return }
        }
        chatThreads.removeAll { $0.id == thread.id }
        if activeChatThreadID == thread.id { startNewChat() }
    }

    func presentMealLogger(description: String = "") {
        pendingMealDescription = description
        showLogFood = true
    }

    func beginLoggingYesterdayFromMorningCheckIn() {
        guard let morningCheckIn, morningCheckInLoggingHandoff == .idle else { return }
        logDateBeforeMorningCheckInHandoff = selectedLogDate
        selectedLogDate = Calendar.current.startOfDay(for: morningCheckIn.reviewDate)
        morningCheckInLoggingHandoff = .awaitingLogger
        showMorningCheckIn = false
    }

    func morningCheckInSheetDidDismiss() async {
        guard morningCheckInLoggingHandoff == .awaitingLogger else {
            dismissMorningCheckIn()
            return
        }
        if isCICOPreview {
            foodEntries = morningCheckIn?.entries ?? []
            dailyPlan = currentPlan
            dailyNutrition = Self.previewDailyNutrition(plan: currentPlan)
        } else {
            await loadDailyLog()
        }
        morningCheckInLoggingHandoff = .logging
        showLogFood = true
    }

    func mealLoggerDidDismiss() async {
        pendingMealDescription = ""
        guard morningCheckInLoggingHandoff == .logging else { return }

        if isCICOPreview, let checkIn = morningCheckIn {
            morningCheckIn = MorningCheckIn(
                reviewDate: checkIn.reviewDate,
                entries: foodEntries,
                intakeDay: checkIn.intakeDay,
                todayWeight: checkIn.todayWeight
            )
        } else {
            await loadMorningCheckIn(presentWhenNeeded: false)
        }

        selectedLogDate = logDateBeforeMorningCheckInHandoff
            ?? Calendar.current.startOfDay(for: .now)
        logDateBeforeMorningCheckInHandoff = nil
        morningCheckInLoggingHandoff = .idle
        selectedLogDate = Calendar.current.startOfDay(for: selectedLogDate)
        if isCICOPreview {
            foodEntries = []
            dailyPlan = currentPlan
            dailyNutrition = Self.previewDailyNutrition(plan: currentPlan)
        } else {
            await loadDailyLog()
        }
        showMorningCheckIn = true
    }

    func updateFoodEntry(_ entry: FoodEntry, input: FoodEntryInput) async -> Bool {
        guard input.isValid else { dailyErrorMessage = "Enter a food name and calories between 1 and 10,000."; return false }
        isFoodMutationInProgress = true
        dailyErrorMessage = nil
        if isCICOPreview {
            guard let index = foodEntries.firstIndex(where: { $0.id == entry.id }) else {
                isFoodMutationInProgress = false
                return false
            }
            foodEntries[index].name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
            foodEntries[index].calories = input.calories
            foodEntries[index].consumedAt = input.consumedAt
            foodEntries[index].amount = input.amount
            foodEntries[index].amountUnit = input.amountUnit
            foodEntries[index].gramWeight = input.gramWeight
            foodEntries[index].portionDescription = input.portionDescription
            foodEntries[index].mealType = input.mealType
            foodEntries[index].updatedAt = .now
            foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyNutrition = Self.previewDailyNutrition(plan: dailyPlan)
            isFoodMutationInProgress = false
            return true
        }
        do {
            let updated = try await service.updateFoodEntry(id: entry.id, input: input, on: selectedLogDate)
            if let index = foodEntries.firstIndex(where: { $0.id == entry.id }) { foodEntries[index] = updated }
            foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyNutrition = try? await service.fetchDailyNutrition(on: selectedLogDate)
            isFoodMutationInProgress = false
            return true
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
            isFoodMutationInProgress = false
            return false
        }
    }

    func deleteFoodEntry(_ entry: FoodEntry) async -> Bool {
        isFoodMutationInProgress = true
        dailyErrorMessage = nil
        if isCICOPreview {
            foodEntries.removeAll { $0.id == entry.id }
            dailyNutrition = Self.previewDailyNutrition(plan: dailyPlan)
            isFoodMutationInProgress = false
            return true
        }
        do {
            if entry.isAIEstimate { try await service.deleteAIMealEntry(id: entry.id) }
            else { try await service.deleteFoodEntry(id: entry.id) }
            foodEntries.removeAll { $0.id == entry.id }
            dailyNutrition = try? await service.fetchDailyNutrition(on: selectedLogDate)
            isFoodMutationInProgress = false
            return true
        } catch {
            dailyErrorMessage = userFacingMessage(for: error)
            isFoodMutationInProgress = false
            return false
        }
    }

    func autoFillNutrients(for input: FoodEntryInput) async -> [NutrientAmountInput]? {
        isNutrientAutoFillLoading = true
        nutrientAutoFillError = nil
        defer { isNutrientAutoFillLoading = false }
        if isCICOPreview {
            return [
                .init(code: "protein_g", amount: 24, derivationMethod: .estimated, confidence: 0.72),
                .init(code: "carbohydrate_g", amount: 36, derivationMethod: .estimated, confidence: 0.68),
                .init(code: "fat_g", amount: 11, derivationMethod: .estimated, confidence: 0.64),
                .init(code: "fiber_g", amount: 5, derivationMethod: .estimated, confidence: 0.5),
                .init(code: "sodium_mg", amount: 420, derivationMethod: .estimated, confidence: 0.45),
            ]
        }
        do { return try await service.autoFillNutrients(for: input).nutrients }
        catch { nutrientAutoFillError = userFacingMessage(for: error); return nil }
    }

    func loadWeightHistory() async {
        guard route == .dashboard else { return }
        if isCICOPreview { return }
        isWeightLoading = true
        weightErrorTitle = "We couldn’t load your weight history"
        weightErrorMessage = nil
        do {
            async let loadedEntries = service.fetchWeightEntries()
            async let loadedContext = service.fetchWeightNutritionContext()
            let entries = try await loadedEntries
            weightEntries = entries.sorted { $0.recordedOn > $1.recordedOn }
            weightNutritionContext = try? await loadedContext
        } catch {
            weightErrorMessage = userFacingMessage(for: error)
        }
        isWeightLoading = false
    }

    func loadMorningCheckIn(presentWhenNeeded: Bool) async {
        guard route == .dashboard else { return }
        guard !showCoreDataAcknowledgment else { return }
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
        guard !showCoreDataAcknowledgment else { return }
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
        guard !isWeightMutationInProgress else { return false }
        weightErrorTitle = entry == nil ? "We couldn’t add your weight" : "We couldn’t update your weight"
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
        guard !isWeightMutationInProgress else { return }
        isWeightMutationInProgress = true
        weightErrorTitle = "We couldn’t delete this weight"
        weightErrorMessage = nil
        do {
            let response = try await service.deleteWeightEntry(id: entry.id)
            try await applyWeightMutation(response)
        } catch {
            weightErrorMessage = userFacingMessage(for: error)
        }
        isWeightMutationInProgress = false
    }

    func refreshCoreDataUseStatus() async {
        guard isAuthenticated, !isCICOPreview else { return }
        do {
            let status = try await service.coreDataUseStatus(version: AccountLegalDocument.coreDataUseVersion)
            showCoreDataAcknowledgment = !status.accepted
            coreDataAccepted = status.accepted
            coreDataAcknowledgmentError = nil
        } catch {
            showCoreDataAcknowledgment = true
            coreDataAcknowledgmentError = coreDataUseFailureMessage(for: error)
        }
    }

    func acceptCoreDataUse() async {
        isCoreDataAcknowledgmentLoading = true
        defer { isCoreDataAcknowledgmentLoading = false }
        do {
            _ = try await service.acceptCoreDataUse(version: AccountLegalDocument.coreDataUseVersion)
            coreDataAccepted = true
            showCoreDataAcknowledgment = false
            coreDataAcknowledgmentError = nil
            await loadMorningCheckIn(presentWhenNeeded: true)
        } catch {
            coreDataAcknowledgmentError = coreDataUseFailureMessage(for: error)
        }
    }

    private func coreDataUseFailureMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("session") ||
            message.localizedCaseInsensitiveContains("unauthorized") {
            return "Your session has expired. Sign out, then sign in again to continue."
        }
        return "We couldn’t save your choice. Check your connection and try again."
    }

    func signOut() async {
        do { try await service.signOut(scope: .local) } catch { errorMessage = userFacingMessage(for: error) }
        GIDSignIn.sharedInstance.signOut()
        await cache.clear()
        await pendingOnboardingCache.clear()
        resetToOnboarding()
    }

    func signOutEverywhere() async {
        do { try await service.signOut(scope: .global) } catch { errorMessage = userFacingMessage(for: error); return }
        GIDSignIn.sharedInstance.signOut()
        await cache.clear()
        await pendingOnboardingCache.clear()
        resetToOnboarding()
    }

    func requestPasswordReset(email: String) async -> Bool {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else { errorMessage = "Enter a valid email address."; return false }
        do {
            try await service.requestPasswordReset(email: normalized)
            statusMessage = "If an account exists for that email, a reset link is on its way."
            return true
        } catch {
            // Avoid revealing whether an account exists.
            statusMessage = "If an account exists for that email, a reset link is on its way."
            return true
        }
    }

    func refreshAccount() async { account = try? await service.account() }

    func changeEmail(to newEmail: String, currentPassword: String) async -> Bool {
        guard let currentEmail = account?.email, newEmail.contains("@") else {
            errorMessage = "Enter a valid new email address."; return false
        }
        do {
            _ = try await service.signIn(email: currentEmail, password: currentPassword)
            try await service.updateEmail(newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            statusMessage = "Check your new email address to confirm this change."
            await refreshAccount()
            return true
        } catch { errorMessage = userFacingMessage(for: error); return false }
    }

    func changePassword(to newPassword: String, currentPassword: String) async -> Bool {
        guard let currentEmail = account?.email, newPassword.count >= 8 else {
            errorMessage = "Use a new password with at least 8 characters."; return false
        }
        do {
            _ = try await service.signIn(email: currentEmail, password: currentPassword)
            try await service.updatePassword(newPassword)
            statusMessage = "Your password was updated."
            return true
        } catch { errorMessage = userFacingMessage(for: error); return false }
    }

    func completePasswordReset(_ newPassword: String) async -> Bool {
        guard newPassword.count >= 8 else { errorMessage = "Password must be at least 8 characters."; return false }
        do {
            try await service.updatePassword(newPassword)
            try await service.signOut(scope: .global)
            showPasswordRecovery = false
            statusMessage = "Password updated. Sign in again on this device."
            resetToOnboarding()
            presentAuthentication(.accessExistingAccount)
            return true
        } catch { errorMessage = userFacingMessage(for: error); return false }
    }

    func persistPendingOnboarding() async {
        try? await pendingOnboardingCache.save(PendingOnboardingState(
            input: draft.input,
            stepID: draft.step.rawValue,
            termsAccepted: termsAccepted,
            privacyAccepted: privacyAccepted,
            coreDataAccepted: coreDataAccepted
        ))
    }

    func handleIncomingURL(_ url: URL) async {
        guard let route = AuthLinkRoute.parse(url, configuration: configuration) else { return }
        service.handleAuthURL(url)
        if route == .passwordRecovery { showPasswordRecovery = true }
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
        clearMealEstimateState()
        morningCheckIn = nil; planAdjustmentNotice = nil; showMorningCheckIn = false
        showCoreDataAcknowledgment = false; coreDataAcknowledgmentError = nil
        isAuthenticated = false
        account = nil; authFlowState = .signedOut
        draft = OnboardingDraft(); route = .onboarding
    }

    private func loadAuthenticatedAccount(accessToken: String) async throws {
        let cloud = try await service.fetchCloudState(accessToken: accessToken)
        isAuthenticated = true
        authFlowState = .authenticated
        account = try? await service.account()
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
        _ = await (daily, weights)
        await refreshCoreDataUseStatus()
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
        if message.localizedCaseInsensitiveContains("invalid login") || message.localizedCaseInsensitiveContains("invalid credentials") {
            return "The email or password is incorrect."
        }
        if message.localizedCaseInsensitiveContains("email rate limit") {
            return "Leafy’s shared email allowance has been reached. Supabase’s built-in mail service allows only two emails per hour, so try again later or use the most recent confirmation email."
        }
        if message.localizedCaseInsensitiveContains("email not confirmed") {
            return "Confirm your email using the link we sent, then try again."
        }
        if message.localizedCaseInsensitiveContains("nonce")
            || message.localizedCaseInsensitiveContains("id_token")
            || message.localizedCaseInsensitiveContains("identity token") {
            return "Leafy couldn’t verify this sign-in. Please try again."
        }
        return message
    }

    private func observeAuthentication() {
        guard authObserverTask == nil else { return }
        authObserverTask = Task { [weak self] in
            guard let self else { return }
            for await event in service.authEvents {
                guard !Task.isCancelled else { return }
                switch event {
                case .passwordRecovery:
                    showPasswordRecovery = true
                    authFlowState = .passwordRecovery
                case .signedIn, .userUpdated:
                    isAuthenticated = true
                    authFlowState = .authenticated
                    account = try? await service.account()
                case .signedOut, .userDeleted:
                    isAuthenticated = false
                    account = nil
                    authFlowState = .signedOut
                case let .initialSession(hasSession):
                    authFlowState = hasSession ? .authenticated : .signedOut
                }
            }
        }
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
        let previewWeightCount = ProcessInfo.processInfo.arguments.contains("-SixWeightReadings") ? 6 : 8
        weightEntries = (0..<previewWeightCount).map { offset in
            WeightEntry(
                id: UUID(),
                userID: userID,
                weightKG: 84.0 + Double(offset) * 0.08,
                recordedOn: calendar.date(byAdding: .day, value: -offset, to: today) ?? today,
                timeZone: calendar.timeZone.identifier,
                source: offset == previewWeightCount - 1 ? .baseline : .manual,
                planID: plan.id,
                createdAt: .now,
                updatedAt: .now
            )
        }
        weightNutritionContext = WeightNutritionContext(
            available: true,
            confirmedDayCount: 7,
            elevatedNutrients: []
        )
        selectedLogDate = today
        route = .dashboard
        isAuthenticated = true
        foodEntries = []
        dailyNutrition = Self.previewDailyNutrition(plan: plan)
        let previewCheckInEntries = ProcessInfo.processInfo.arguments.contains("-EmptyMorningCheckIn")
            ? []
            : [breakfast, dinner]
        morningCheckIn = MorningCheckIn(reviewDate: yesterday, entries: previewCheckInEntries, intakeDay: nil, todayWeight: nil)
        hasMorningCheckInReminder = true
        showMorningCheckIn = !ProcessInfo.processInfo.arguments.contains("-SkipMorningCheckIn")
        if ProcessInfo.processInfo.arguments.contains("-PlanResultsPreview") {
            preview = plan
            draft.step = .results
            route = .onboarding
            showMorningCheckIn = false
        }
    }

    private static func previewMealEstimate(sessionID: UUID, ready: Bool = false) -> MealEstimate {
        MealEstimate(
            sessionID: sessionID,
            status: ready ? .ready : .needsClarification,
            totalCalories: 610,
            calorieLow: 500,
            calorieHigh: 760,
            confidence: 0.68,
            assumptions: ["Chicken appears grilled", "Rice portion is about one cup"],
            items: [
                MealEstimateItem(
                    id: UUID(uuidString: "D27DC6DA-CC10-4E55-9CC0-A017C9345521")!,
                    name: "Grilled chicken", portion: "1 chicken breast", estimatedGrams: 170,
                    calories: 280, calorieLow: 240, calorieHigh: 340, confidence: 0.82,
                    assumptions: ["Skinless chicken breast"]
                ),
                MealEstimateItem(
                    id: UUID(uuidString: "CC094E0B-3F24-4AD0-B641-47A244D14B38")!,
                    name: "Rice and vegetables", portion: "About 1½ cups", estimatedGrams: 260,
                    calories: 330, calorieLow: 260, calorieHigh: 420, confidence: 0.58,
                    assumptions: ["One cup cooked rice", "Lightly oiled vegetables"]
                ),
            ],
            followUp: ready ? nil : MealFollowUp(
                id: UUID(uuidString: "47DC0199-6EBF-4B37-B7D9-AEC297A031DD")!, ordinal: 1,
                question: "Was any oil, butter, or sauce added?"
            )
        )
    }

    private static func previewDailyNutrition(plan: NutritionPlan?) -> DailyNutritionSummary? {
        guard let plan else { return nil }
        let values: [(String, String, String, Double, Double?, NutrientTargetKind)] = [
            ("protein_g", "Protein", "g", 54, Double(plan.proteinG), .goal),
            ("carbohydrate_g", "Carbohydrate", "g", 82, Double(plan.carbohydrateG), .goal),
            ("fat_g", "Fat", "g", 24, Double(plan.fatG), .goal),
            ("fiber_g", "Dietary fiber", "g", 13, 28, .goal),
            ("sodium_mg", "Sodium", "mg", 920, 2300, .limit),
            ("vitamin_d_mcg", "Vitamin D", "mcg", 7, 20, .goal),
            ("calcium_mg", "Calcium", "mg", 610, 1300, .goal),
            ("iron_mg", "Iron", "mg", 8.2, 18, .goal),
        ]
        let nutrients = values.enumerated().map { index, value in
            let nutrientClass: String = switch value.0 {
            case "protein_g", "carbohydrate_g", "fat_g": "macro"
            case "vitamin_d_mcg": "vitamin"
            case "sodium_mg", "calcium_mg", "iron_mg": "mineral"
            default: "other"
            }
            return DailyNutrient(
                code: value.0, name: value.1, unit: value.2, nutrientClass: nutrientClass,
                displayOrder: index, targetKind: value.5, amount: value.3, targetAmount: value.4,
                percentOfTarget: value.4.map { value.3 / $0 }, coverage: 0.78,
                estimatedAmount: value.3 * 0.35, verifiedAmount: value.3 * 0.65, confidence: 0.68
            )
        }
        return DailyNutritionSummary(
            localDate: PlanService.localDayString(for: .now), totalCalories: 0, macroCoverage: 0.78,
            reference: NutrientReference(
                code: "fda_adults_4_plus_2020", name: "FDA Daily Values",
                population: "Adults and children age 4 and older",
                sourceURL: URL(string: "https://www.fda.gov/food/nutrition-facts-label/daily-value-nutrition-and-supplement-facts-labels")!
            ), nutrients: nutrients
        )
    }
}
