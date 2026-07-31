import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    enum Route { case onboarding, dashboard }
    enum SaveState: Equatable { case idle, creatingAccount, awaitingConfirmation, resendingConfirmation, authenticating, saving, deleting }

    var route: Route = .onboarding
    var draft = OnboardingDraft()
    var preview: NutritionPlan?
    var currentPlan: NutritionPlan?
    var errorMessage: String?
    var statusMessage: String?
    var saveState: SaveState = .idle
    var email = ""
    var password = ""
    var passwordConfirmation = ""
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

    func saveAfterApple(identityToken: String, nonce: String) async {
        await perform(.authenticating) {
            let accessToken = try await service.signInWithApple(identityToken: identityToken, nonce: nonce)
            try await saveAuthenticatedDraft(accessToken: accessToken)
        }
    }

    func saveAuthenticatedDraft(accessToken: String? = nil) async throws {
        saveState = .saving
        let plan = try await service.savePlan(draft.input, accessToken: accessToken)
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
}
