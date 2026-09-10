import Foundation

enum AuthFlowState: Equatable, Sendable {
    case signedOut
    case authenticating
    case awaitingEmailConfirmation(String)
    case passwordRecovery
    case authenticated
}

enum LeafyAuthEvent: Equatable, Sendable {
    case initialSession(Bool)
    case signedIn
    case signedOut
    case passwordRecovery
    case userUpdated
    case userDeleted
}

struct AccountIdentity: Identifiable, Equatable, Sendable {
    let id: String
    let provider: String
    let email: String?

    var displayName: String {
        switch provider {
        case "apple": "Apple"
        case "google": "Google"
        case "email": "Email and password"
        default: provider.capitalized
        }
    }
}

struct LeafyAccount: Equatable, Sendable {
    let userID: UUID
    let email: String?
    let emailConfirmed: Bool
    let identities: [AccountIdentity]

    var hasAppleIdentity: Bool {
        identities.contains { $0.provider.caseInsensitiveCompare("apple") == .orderedSame }
    }
}

enum AccountLegalDocument {
    static let termsVersion = 1
    static let privacyVersion = 1
    static let coreDataUseVersion = 1
}

struct CoreDataUseStatus: Codable, Equatable, Sendable {
    let accepted: Bool
    let version: Int
}

struct PendingOnboardingState: Equatable, Sendable {
    let input: NutritionPlanInput?
    let stepID: String?
    let stepRawValue: Int?
    let termsAccepted: Bool
    let privacyAccepted: Bool
    let coreDataAccepted: Bool
    let requiresBirthDateConfirmation: Bool

    init(
        input: NutritionPlanInput?,
        stepID: String?,
        stepRawValue: Int? = nil,
        termsAccepted: Bool,
        privacyAccepted: Bool,
        coreDataAccepted: Bool = false,
        requiresBirthDateConfirmation: Bool = false
    ) {
        self.input = input
        self.stepID = stepID
        self.stepRawValue = stepRawValue
        self.termsAccepted = termsAccepted
        self.privacyAccepted = privacyAccepted
        self.coreDataAccepted = coreDataAccepted
        self.requiresBirthDateConfirmation = requiresBirthDateConfirmation
    }
}

actor PendingOnboardingCache {
    static let currentVersion = 2
    private let url: URL

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        if let fileURL {
            url = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            url = base.appending(path: "leafy-pending-onboarding.json")
        }
    }

    func save(_ state: PendingOnboardingState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(EnvelopeV2(state: state)).write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    func load(timeZone: TimeZone = .current) -> PendingOnboardingState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let v2 = decodeV2(data) { return v2 }
        if let migrated = migrateV1(data, timeZone: timeZone) {
            try? save(migrated)
            return migrated
        }
        if let consents = decodeConsents(data) {
            let recovered = PendingOnboardingState(
                input: nil,
                stepID: "birthDate",
                termsAccepted: consents.termsAccepted,
                privacyAccepted: consents.privacyAccepted,
                coreDataAccepted: consents.coreDataAccepted,
                requiresBirthDateConfirmation: true
            )
            try? save(recovered)
            return recovered
        }
        return nil
    }

    func clear() { try? FileManager.default.removeItem(at: url) }

    private func decodeV2(_ data: Data) -> PendingOnboardingState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(EnvelopeV2.self, from: data),
              envelope.version == Self.currentVersion
        else { return nil }
        return envelope.state
    }

    private func migrateV1(_ data: Data, timeZone: TimeZone) -> PendingOnboardingState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacy = try? decoder.decode(LegacyV1.self, from: data) else { return nil }
        let birthDate: LocalDate?
        if let instant = legacy.input.birthDate {
            birthDate = LocalDate.displayed(from: instant, timeZone: timeZone)
        } else {
            birthDate = nil
        }
        let input = NutritionPlanInput(
            birthDate: birthDate,
            calculationSex: legacy.input.calculationSex,
            heightCM: legacy.input.heightCM,
            currentWeightKG: legacy.input.currentWeightKG,
            targetWeightKG: legacy.input.targetWeightKG,
            activityLevel: legacy.input.activityLevel,
            goal: legacy.input.goal,
            pace: legacy.input.pace,
            unitSystem: legacy.input.unitSystem
        )
        return PendingOnboardingState(
            input: input,
            stepID: "birthDate",
            stepRawValue: legacy.stepRawValue,
            termsAccepted: legacy.termsAccepted,
            privacyAccepted: legacy.privacyAccepted,
            coreDataAccepted: legacy.coreDataAccepted ?? false,
            requiresBirthDateConfirmation: true
        )
    }

    private func decodeConsents(_ data: Data) -> (termsAccepted: Bool, privacyAccepted: Bool, coreDataAccepted: Bool)? {
        struct Fragment: Decodable {
            var termsAccepted: Bool?
            var privacyAccepted: Bool?
            var coreDataAccepted: Bool?
        }
        guard let fragment = try? JSONDecoder().decode(Fragment.self, from: data) else { return nil }
        guard fragment.termsAccepted != nil || fragment.privacyAccepted != nil || fragment.coreDataAccepted != nil else {
            return nil
        }
        return (
            fragment.termsAccepted ?? false,
            fragment.privacyAccepted ?? false,
            fragment.coreDataAccepted ?? false
        )
    }
}

private struct EnvelopeV2: Codable {
    var version: Int
    var input: NutritionPlanInput?
    var stepID: String?
    var stepRawValue: Int?
    var termsAccepted: Bool
    var privacyAccepted: Bool
    var coreDataAccepted: Bool
    var requiresBirthDateConfirmation: Bool

    init(state: PendingOnboardingState) {
        version = PendingOnboardingCache.currentVersion
        input = state.input
        stepID = state.stepID
        stepRawValue = state.stepRawValue
        termsAccepted = state.termsAccepted
        privacyAccepted = state.privacyAccepted
        coreDataAccepted = state.coreDataAccepted
        requiresBirthDateConfirmation = state.requiresBirthDateConfirmation
    }

    var state: PendingOnboardingState {
        PendingOnboardingState(
            input: input,
            stepID: stepID,
            stepRawValue: stepRawValue,
            termsAccepted: termsAccepted,
            privacyAccepted: privacyAccepted,
            coreDataAccepted: coreDataAccepted,
            requiresBirthDateConfirmation: requiresBirthDateConfirmation
        )
    }
}

/// Dedicated v1 on-disk shape. `birth_date` is an ISO8601 instant.
private struct LegacyV1: Decodable {
    var input: LegacyV1Input
    var stepID: String?
    var stepRawValue: Int?
    var termsAccepted: Bool
    var privacyAccepted: Bool
    var coreDataAccepted: Bool?
}

private struct LegacyV1Input: Decodable {
    var birthDate: Date?
    var calculationSex: CalculationSex
    var heightCM: Double
    var currentWeightKG: Double
    var targetWeightKG: Double?
    var activityLevel: ActivityLevel
    var goal: WeightGoal
    var pace: GoalPace
    var unitSystem: UnitSystem

    enum CodingKeys: String, CodingKey {
        case birthDate = "birth_date"
        case calculationSex = "calculation_sex"
        case heightCM = "height_cm"
        case currentWeightKG = "current_weight_kg"
        case targetWeightKG = "target_weight_kg"
        case activityLevel = "activity_level"
        case goal, pace
        case unitSystem = "unit_system"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        birthDate = try? container.decode(Date.self, forKey: .birthDate)
        calculationSex = try container.decode(CalculationSex.self, forKey: .calculationSex)
        heightCM = try container.decode(Double.self, forKey: .heightCM)
        currentWeightKG = try container.decode(Double.self, forKey: .currentWeightKG)
        targetWeightKG = try container.decodeIfPresent(Double.self, forKey: .targetWeightKG)
        activityLevel = try container.decode(ActivityLevel.self, forKey: .activityLevel)
        goal = try container.decode(WeightGoal.self, forKey: .goal)
        pace = try container.decode(GoalPace.self, forKey: .pace)
        unitSystem = try container.decode(UnitSystem.self, forKey: .unitSystem)
    }
}

enum AuthLinkRoute: Equatable {
    case callback
    case passwordRecovery
    case emailChange

    static func parse(_ url: URL, configuration: AppConfiguration = .live()) -> AuthLinkRoute? {
        let callback = configuration.authCallbackURL
        let allowedUniversalLink = url.scheme?.lowercased() == callback.scheme?.lowercased() &&
            url.host?.lowercased() == callback.host?.lowercased()
        let allowedCustomLink = url.scheme?.lowercased() == configuration.authURLScheme.lowercased() &&
            url.host?.lowercased() == "auth"
        let allowed = allowedUniversalLink || allowedCustomLink
        guard allowed else { return nil }
        let path = url.path.lowercased()
        if path.contains("reset") || path.contains("recovery") { return .passwordRecovery }
        if path.contains("email-change") { return .emailChange }
        if path.contains("callback") || path.contains("confirm") || allowedCustomLink { return .callback }
        return nil
    }
}
