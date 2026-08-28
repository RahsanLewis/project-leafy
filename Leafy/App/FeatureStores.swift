import Foundation
import Observation

@MainActor @Observable
final class DailyLogStore {
    let service: PlanService
    var selectedLogDate = Calendar.current.startOfDay(for: .now)
    var foodEntries: [FoodEntry] = []
    var pendingCatalogLogs: [PendingCatalogLog] = []
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
    var dailyErrorMessage: String?
    var showLogFood = false
    var pendingMealDescription = ""

    init(service: PlanService) { self.service = service }
}

@MainActor @Observable
final class ProductStore {
    let service: PlanService
    let dailyLog: DailyLogStore
    let isPreview: Bool
    var productSearchResults: [ProductSummary] = []
    var productHistory: [ProductSummary] = []
    var isProductLoading = false
    var productErrorMessage: String?
    var catalogContributions: [CatalogContribution] = []
    var isCatalogContributionLoading = false
    var catalogContributionErrorMessage: String?

    init(service: PlanService, dailyLog: DailyLogStore, isPreview: Bool) {
        self.service = service; self.dailyLog = dailyLog; self.isPreview = isPreview
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { productSearchResults = []; return }
        isProductLoading = true; productErrorMessage = nil
        defer { isProductLoading = false }
        do { productSearchResults = try await service.searchProducts(query) }
        catch { productErrorMessage = userFacingMessage(error) }
    }

    func lookup(barcode: String) async -> ProductSummary? {
        isProductLoading = true; productErrorMessage = nil
        defer { isProductLoading = false }
        do { return try await service.lookupProduct(barcode: barcode) }
        catch { productErrorMessage = userFacingMessage(error); return nil }
    }

    func detail(_ product: ProductSummary) async -> ProductDetail? {
        isProductLoading = true; productErrorMessage = nil
        defer { isProductLoading = false }
        do { return try await service.productDetail(for: product) }
        catch { productErrorMessage = userFacingMessage(error); return nil }
    }

    func log(_ product: ProductDetail, grams: Double, consumedAt: Date, mealType: MealType) async -> Bool {
        dailyLog.isFoodMutationInProgress = true; productErrorMessage = nil
        defer { dailyLog.isFoodMutationInProgress = false }
        do {
            let entry = try await service.logProduct(
                product, grams: grams, consumedAt: consumedAt,
                localDate: dailyLog.selectedLogDate, mealType: mealType
            )
            dailyLog.foodEntries.append(entry); dailyLog.foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyLog.dailyNutrition = try? await service.fetchDailyNutrition(on: dailyLog.selectedLogDate)
            return true
        } catch { productErrorMessage = userFacingMessage(error); return false }
    }
}

@MainActor @Observable
final class WeightStore {
    let service: PlanService
    var weightEntries: [WeightEntry] = []
    var isWeightLoading = false
    var isWeightMutationInProgress = false
    var weightErrorMessage: String?
    var weightErrorTitle = "We couldn’t update your weight"
    var weightStatusMessage: String?
    var lastWeightOutcome: WeightMutationOutcome?

    init(service: PlanService) { self.service = service }
}

@MainActor @Observable
final class AuthSessionStore {
    let service: PlanService
    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var showAuthentication = false
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

    init(service: PlanService) { self.service = service }
}

@MainActor @Observable
final class ChatStore {
    let service: PlanService
    let dailyLog: DailyLogStore
    let isPreview: Bool
    var threads: [NutritionChatThread] = []
    var activeThreadID: UUID?
    var messages: [NutritionChatMessage] = []
    var isLoading = false
    var errorMessage: String?
    var mealLoggingMessageID: UUID?
    var pendingClientMessageID: UUID?
    var pendingText: String?

    init(service: PlanService, dailyLog: DailyLogStore, isPreview: Bool) {
        self.service = service
        self.dailyLog = dailyLog
        self.isPreview = isPreview
    }

    func startNewChat() {
        activeThreadID = nil; messages = []; errorMessage = nil
        pendingClientMessageID = nil; pendingText = nil
    }

    func loadThreads() async {
        guard !isPreview else { return }
        do { threads = try await service.listNutritionChatThreads() }
        catch { errorMessage = userFacingMessage(error) }
    }

    func open(_ thread: NutritionChatThread) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        if isPreview { activeThreadID = thread.id; return }
        do {
            let result = try await service.loadNutritionChatThread(id: thread.id)
            activeThreadID = result.thread.id; messages = result.messages
        } catch { errorMessage = userFacingMessage(error) }
    }

    func send(_ text: String, clientMessageID: UUID = UUID()) async -> Bool {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 2_000 else {
            errorMessage = "Keep your question under 2,000 characters."; return false
        }
        isLoading = true; errorMessage = nil
        pendingClientMessageID = clientMessageID; pendingText = message
        messages.append(NutritionChatMessage(
            id: clientMessageID, role: "user", content: message,
            sources: [], suggestedLogDescription: nil, createdAt: .now
        ))
        defer { isLoading = false; pendingClientMessageID = nil; pendingText = nil }
        if isPreview {
            if ProcessInfo.processInfo.arguments.contains("-HoldChatResponse") {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { messages.removeAll { $0.id == clientMessageID }; return false }
            }
            let offTopic = message.localizedCaseInsensitiveContains("write code") || message.localizedCaseInsensitiveContains("stock portfolio")
            let eaten = message.localizedCaseInsensitiveContains("ate")
            let estimate = eaten ? AppCoordinator.previewMealEstimate(sessionID: UUID(), ready: true) : nil
            messages.append(NutritionChatMessage(
                id: UUID(), role: "assistant",
                content: offTopic
                    ? "I’m focused on nutrition and health, so I can’t help with that. I can help you plan what to eat or talk through a health question."
                    : eaten ? "Here’s an estimate based on what you described. Review the portions before logging it."
                    : "Based on your current plan, aim for protein-rich foods you enjoy and use your remaining calorie budget to guide the portion.",
                sources: offTopic ? [] : [NutritionChatSource(kind: "plan", label: "Your Leafy plan")],
                suggestedLogDescription: nil,
                mealSuggestion: offTopic ? nil : estimate.map {
                    NutritionChatMealSuggestion(
                        sessionID: $0.sessionID, status: .ready,
                        totalCalories: $0.totalCalories, calorieLow: $0.calorieLow,
                        calorieHigh: $0.calorieHigh, confidence: $0.confidence,
                        assumptions: $0.assumptions, items: $0.items
                    )
                }, createdAt: .now
            ))
            return true
        }
        do {
            let result = try await service.sendNutritionChatMessage(message, threadID: activeThreadID, clientMessageID: clientMessageID)
            messages.removeAll { $0.id == clientMessageID }
            activeThreadID = result.thread.id
            messages.append(contentsOf: [result.userMessage, result.assistantMessage])
            if let index = threads.firstIndex(where: { $0.id == result.thread.id }) { threads[index] = result.thread }
            else { threads.insert(result.thread, at: 0) }
            return true
        } catch {
            messages.removeAll { $0.id == clientMessageID }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return false }
            errorMessage = userFacingMessage(error); return false
        }
    }

    func cancelPendingResponse() -> String {
        let text = pendingText ?? ""
        messages.removeAll { $0.id == pendingClientMessageID }
        isLoading = false
        return text
    }

    func mealReviewDraft(messageID: UUID, consumedAt: Date = .now) -> ChatMealReviewDraft? {
        guard let suggestion = messages.first(where: { $0.id == messageID })?.mealSuggestion,
              suggestion.status == .ready else { return nil }
        return ChatMealReviewDraft(
            messageID: messageID, sessionID: suggestion.sessionID,
            items: suggestion.items.map(ChatMealReviewItem.init(prediction:)), consumedAt: consumedAt
        )
    }

    func confirmMeal(_ draft: ChatMealReviewDraft) async -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == draft.messageID }),
              let suggestion = messages[index].mealSuggestion, suggestion.status == .ready, draft.isValid else { return false }
        let items = draft.items.map {
            ChatMealConfirmationItem(
                clientItemID: $0.id, predictionID: $0.predictionID, name: $0.name,
                portion: $0.portion, calories: $0.calories, nutrients: $0.nutrients, origin: $0.origin
            )
        }
        mealLoggingMessageID = draft.messageID; errorMessage = nil
        defer { mealLoggingMessageID = nil }
        do {
            let entries = isPreview ? items.map {
                FoodEntry(
                    id: UUID(), userID: UUID(), name: $0.name, calories: $0.calories,
                    consumedAt: draft.consumedAt, localDate: PlanService.localDayString(for: draft.consumedAt),
                    timeZone: Calendar.current.timeZone.identifier, createdAt: .now, updatedAt: .now,
                    portionDescription: $0.portion, confidence: 0.7, userConfirmed: true,
                    entrySource: "text_ai", calorieMethod: $0.origin == .prediction ? "estimated" : "user_entered"
                )
            } : try await service.confirmChatMealEstimate(sessionID: suggestion.sessionID, items: items, consumedAt: draft.consumedAt)
            dailyLog.selectedLogDate = Calendar.current.startOfDay(for: draft.consumedAt)
            dailyLog.foodEntries.append(contentsOf: entries)
            dailyLog.foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyLog.dailyNutrition = try? await service.fetchDailyNutrition(on: dailyLog.selectedLogDate)
            if let refreshed = messages.firstIndex(where: { $0.id == draft.messageID }) { messages[refreshed].mealSuggestion?.status = .logged }
            return true
        } catch { errorMessage = userFacingMessage(error); return false }
    }

    func delete(_ thread: NutritionChatThread) async {
        if !isPreview {
            do { try await service.deleteNutritionChatThread(id: thread.id) }
            catch { errorMessage = userFacingMessage(error); return }
        }
        threads.removeAll { $0.id == thread.id }
        if activeThreadID == thread.id { startNewChat() }
    }
}

@MainActor @Observable
final class AIMealStore {
    enum Activity: Equatable { case idle, analyzing, refining, saving }
    let service: PlanService
    let dailyLog: DailyLogStore
    let isPreview: Bool
    var estimate: MealEstimate?
    var activity: Activity = .idle
    var errorMessage: String?
    private var sessionID: UUID?
    private var photoObjectPath: String?
    private var logDate = Calendar.current.startOfDay(for: .now)
    var isLoading: Bool { activity != .idle }

    init(service: PlanService, dailyLog: DailyLogStore, isPreview: Bool) {
        self.service = service; self.dailyLog = dailyLog; self.isPreview = isPreview
    }

    func analyze(description: String, photoData: Data?, consumedAt: Date, localDate: Date, mealType: MealType) async -> Bool {
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty || photoData != nil else { errorMessage = "Add a photo or describe what you ate."; return false }
        activity = .analyzing; errorMessage = nil; defer { activity = .idle }
        let id = sessionID ?? UUID(); sessionID = id; logDate = Calendar.current.startOfDay(for: localDate)
        if isPreview {
            if ProcessInfo.processInfo.arguments.contains("-HoldAIMealEstimate") { try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return false } }
            estimate = AppCoordinator.previewMealEstimate(sessionID: id); return true
        }
        do {
            if let photoData, photoObjectPath == nil { photoObjectPath = try await service.uploadMealPhoto(photoData, sessionID: id) }
            let input = MealEstimateInput(
                sessionID: id, description: description, consumedAt: consumedAt, localDate: localDate,
                mealType: mealType, marketCountry: Locale.current.region?.identifier ?? "US"
            )
            estimate = try await service.estimateMeal(input, photoObjectPath: photoObjectPath); return true
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return false }
            errorMessage = userFacingMessage(error); return false
        }
    }

    func answer(_ answer: String?, skip: Bool = false) async -> Bool {
        guard let sessionID else { return false }
        activity = .refining; errorMessage = nil; defer { activity = .idle }
        if isPreview { estimate = AppCoordinator.previewMealEstimate(sessionID: sessionID, ready: true); return true }
        do { estimate = try await service.answerMealEstimate(sessionID: sessionID, answer: answer, skip: skip); return true }
        catch { if Task.isCancelled { return false }; errorMessage = userFacingMessage(error); return false }
    }

    func updateItem(id: UUID, name: String, portion: String, calories: Int, estimatedGrams: Double?, nutrients: [NutrientAmountInput]) {
        guard let index = estimate?.items.firstIndex(where: { $0.id == id }) else { return }
        estimate?.items[index].name = name; estimate?.items[index].portion = portion
        estimate?.items[index].calories = calories; estimate?.items[index].estimatedGrams = estimatedGrams
        estimate?.items[index].nutrients = nutrients
    }

    func removeItem(id: UUID) { estimate?.items.removeAll { $0.id == id } }

    func confirm() async -> Bool {
        guard let estimate, !estimate.items.isEmpty else { errorMessage = "Keep at least one food item before saving."; return false }
        let items = estimate.items.map { MealConfirmationItem(id: $0.id, name: $0.name, portion: $0.portion, calories: $0.calories, estimatedGrams: $0.estimatedGrams, nutrients: $0.nutrients ?? []) }
        guard items.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (0...10_000).contains($0.calories) }) else {
            errorMessage = "Check that each food has a name and calories between 0 and 10,000."; return false
        }
        activity = .saving; errorMessage = nil; defer { activity = .idle }
        do {
            let entries = isPreview ? items.map {
                FoodEntry(
                    id: UUID(), userID: UUID(), name: $0.name, calories: $0.calories,
                    consumedAt: .now, localDate: PlanService.localDayString(for: logDate),
                    timeZone: Calendar.current.timeZone.identifier, createdAt: .now, updatedAt: .now,
                    portionDescription: $0.portion, confidence: 0.7, userConfirmed: true,
                    entrySource: "text_ai", calorieMethod: "estimated"
                )
            } : try await service.confirmMealEstimate(sessionID: estimate.sessionID, items: items)
            dailyLog.selectedLogDate = logDate
            dailyLog.foodEntries.append(contentsOf: entries); dailyLog.foodEntries.sort { $0.consumedAt < $1.consumedAt }
            dailyLog.dailyNutrition = try? await service.fetchDailyNutrition(on: logDate)
            clear(); return true
        } catch { errorMessage = userFacingMessage(error); return false }
    }

    func discard() async {
        if let sessionID, !isPreview { try? await service.discardMealEstimate(sessionID: sessionID) }
        clear()
    }

    func cancelAnalysis() async {
        let id = sessionID; clear(); activity = .idle
        if let id, !isPreview { try? await service.discardMealEstimate(sessionID: id) }
    }

    private func clear() { estimate = nil; sessionID = nil; photoObjectPath = nil; errorMessage = nil }
}

private func userFacingMessage(_ error: Error) -> String { error.localizedDescription }
