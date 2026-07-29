import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    enum Route { case onboarding, dashboard }
    enum SaveState: Equatable { case idle, sendingCode, awaitingCode, authenticating, saving, deleting }

    var route: Route = .onboarding
    var draft = OnboardingDraft()
    var preview: NutritionPlan?
    var currentPlan: NutritionPlan?
    var errorMessage: String?
    var saveState: SaveState = .idle
    var email = ""
    var emailCode = ""
    var showAuthentication = false
    var isConfigured: Bool { configuration.isConfigured }

    let configuration: AppConfiguration
    let service: PlanService
    let cache = PlanCache()

    init(configuration: AppConfiguration = .live()) {
        self.configuration = configuration
        self.service = PlanService(configuration: configuration)
    }

    func restore() async {
        guard await service.currentUserID() != nil else { return }
        if let cloud = try? await service.fetchCloudState() {
            currentPlan = cloud.0; apply(cloud.1); try? await cache.save(cloud.0, input: cloud.1); route = .dashboard
        } else if let cached = await cache.load() {
            currentPlan = cached.plan; apply(cached.input); route = .dashboard
        }
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

    func sendCode() async {
        guard email.contains("@") else { errorMessage = "Enter a valid email address."; return }
        await perform(.sendingCode) { try await service.sendEmailCode(email.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if errorMessage == nil { saveState = .awaitingCode }
    }

    func verifyCodeAndSave() async {
        guard emailCode.count >= 6 else { errorMessage = "Enter the six-digit code from your email."; return }
        await perform(.authenticating) {
            try await service.verifyEmailCode(email: email.trimmingCharacters(in: .whitespacesAndNewlines), code: emailCode)
            try await saveAuthenticatedDraft()
        }
    }

    func saveAfterApple(identityToken: String, nonce: String) async {
        await perform(.authenticating) {
            try await service.signInWithApple(identityToken: identityToken, nonce: nonce)
            try await saveAuthenticatedDraft()
        }
    }

    func saveAuthenticatedDraft() async throws {
        saveState = .saving
        let plan = try await service.savePlan(draft.input)
        try await cache.save(plan, input: draft.input)
        currentPlan = plan
        preview = nil
        showAuthentication = false
        route = .dashboard
    }

    func editPlan() {
        route = .onboarding
        preview = nil
        draft.step = .goal
        draft.isEditing = true
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
        currentPlan = nil; preview = nil; draft = OnboardingDraft(); route = .onboarding
    }

    private func apply(_ input: NutritionPlanInput) {
        draft.birthDate = input.birthDate; draft.calculationSex = input.calculationSex
        draft.heightCM = input.heightCM; draft.currentWeightKG = input.currentWeightKG
        draft.targetWeightKG = input.targetWeightKG ?? input.currentWeightKG
        draft.activityLevel = input.activityLevel; draft.goal = input.goal; draft.pace = input.pace; draft.unitSystem = input.unitSystem
    }

    private func perform(_ state: SaveState, operation: () async throws -> Void) async {
        saveState = state; errorMessage = nil
        do { try await operation() } catch { errorMessage = error.localizedDescription }
        if saveState != .awaitingCode { saveState = .idle }
    }
}
