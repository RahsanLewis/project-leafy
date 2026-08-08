import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    enum Route: Equatable { case launching, onboarding, dashboard }
    enum AuthenticationPurpose: Equatable { case savePlan, accessExistingAccount }
    enum SaveState: Equatable { case idle, creatingAccount, awaitingConfirmation, resendingConfirmation, authenticating, saving, deleting }
    enum MealEstimateActivity: Equatable { case idle, analyzing, refining, saving }

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
    var showLogFood = false
    var pendingMealDescription = ""
    private var mealEstimateSessionID: UUID?
    private var mealPhotoObjectPath: String?
    private var mealEstimateLogDate = Calendar.current.startOfDay(for: .now)
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
                mealType: mealType
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

    func updateMealEstimateItem(id: UUID, name: String, portion: String, calories: Int) {
        guard let index = mealEstimate?.items.firstIndex(where: { $0.id == id }) else { return }
        mealEstimate?.items[index].name = name
        mealEstimate?.items[index].portion = portion
        mealEstimate?.items[index].calories = calories
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
                nutrients: $0.nutrients ?? []
            )
        }
        guard items.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...10_000).contains($0.calories) }) else {
            mealEstimateErrorMessage = "Review each food name and calorie estimate before saving."
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

    func sendChatMessage(_ text: String) async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 2_000 else {
            chatErrorMessage = "Keep your question under 2,000 characters."
            return
        }
        isChatLoading = true
        chatErrorMessage = nil
        defer { isChatLoading = false }
        if isCICOPreview {
            let now = Date.now
            chatMessages.append(NutritionChatMessage(id: UUID(), role: "user", content: message, sources: [], suggestedLogDescription: nil, createdAt: now))
            let eaten = message.localizedCaseInsensitiveContains("ate")
            let previewEstimate = eaten ? Self.previewMealEstimate(sessionID: UUID(), ready: true) : nil
            chatMessages.append(NutritionChatMessage(
                id: UUID(), role: "assistant",
                content: eaten ? "Here’s an estimate based on what you described. Review the portions before logging it." : "Based on your current plan, aim for protein-rich foods you enjoy and use your remaining calorie budget to guide the portion.",
                sources: [NutritionChatSource(kind: "plan", label: "Your Leafy plan")],
                suggestedLogDescription: nil,
                mealSuggestion: previewEstimate.map {
                    NutritionChatMealSuggestion(
                        sessionID: $0.sessionID, status: .ready,
                        totalCalories: $0.totalCalories, calorieLow: $0.calorieLow,
                        calorieHigh: $0.calorieHigh, confidence: $0.confidence,
                        assumptions: $0.assumptions, items: $0.items
                    )
                },
                createdAt: now
            ))
            return
        }
        do {
            let result = try await service.sendNutritionChatMessage(message, threadID: activeChatThreadID, clientMessageID: UUID())
            activeChatThreadID = result.thread.id
            chatMessages.append(contentsOf: [result.userMessage, result.assistantMessage])
            if let index = chatThreads.firstIndex(where: { $0.id == result.thread.id }) { chatThreads[index] = result.thread }
            else { chatThreads.insert(result.thread, at: 0) }
        } catch { chatErrorMessage = userFacingMessage(for: error) }
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

    func confirmChatMeal(messageID: UUID) async -> Bool {
        guard let messageIndex = chatMessages.firstIndex(where: { $0.id == messageID }),
              let suggestion = chatMessages[messageIndex].mealSuggestion,
              suggestion.status == .ready, !suggestion.items.isEmpty else { return false }
        let items = suggestion.items.map {
            MealConfirmationItem(
                id: $0.id, name: $0.name, portion: $0.portion, calories: $0.calories,
                nutrients: $0.nutrients ?? []
            )
        }
        guard items.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...10_000).contains($0.calories) }) else {
            chatErrorMessage = "Review each food name and calorie estimate before logging."
            return false
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
                        consumedAt: .now, localDate: PlanService.localDayString(for: .now),
                        timeZone: Calendar.current.timeZone.identifier, createdAt: .now, updatedAt: .now,
                        portionDescription: item.portion, confidence: 0.7, userConfirmed: true,
                        entrySource: "text_ai", calorieMethod: "estimated"
                    )
                }
            } else {
                entries = try await service.confirmMealEstimate(sessionID: suggestion.sessionID, items: items)
            }
            selectedLogDate = Calendar.current.startOfDay(for: .now)
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
        clearMealEstimateState()
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
        dailyNutrition = Self.previewDailyNutrition(plan: plan)
        morningCheckIn = MorningCheckIn(reviewDate: yesterday, entries: [breakfast, dinner], intakeDay: nil, todayWeight: nil)
        hasMorningCheckInReminder = true
        showMorningCheckIn = !ProcessInfo.processInfo.arguments.contains("-SkipMorningCheckIn")
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
            DailyNutrient(
                code: value.0, name: value.1, unit: value.2, nutrientClass: index < 3 ? "macro" : "other",
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
