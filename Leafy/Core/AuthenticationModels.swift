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

struct PendingOnboardingState: Codable, Equatable, Sendable {
    let input: NutritionPlanInput
    let stepID: String?
    let stepRawValue: Int?
    let termsAccepted: Bool
    let privacyAccepted: Bool
    let coreDataAccepted: Bool

    init(
        input: NutritionPlanInput,
        stepID: String?,
        stepRawValue: Int? = nil,
        termsAccepted: Bool,
        privacyAccepted: Bool,
        coreDataAccepted: Bool = false
    ) {
        self.input = input
        self.stepID = stepID
        self.stepRawValue = stepRawValue
        self.termsAccepted = termsAccepted
        self.privacyAccepted = privacyAccepted
        self.coreDataAccepted = coreDataAccepted
    }

    private enum CodingKeys: String, CodingKey {
        case input, stepID, stepRawValue, termsAccepted, privacyAccepted, coreDataAccepted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decode(NutritionPlanInput.self, forKey: .input)
        stepID = try container.decodeIfPresent(String.self, forKey: .stepID)
        stepRawValue = try container.decodeIfPresent(Int.self, forKey: .stepRawValue)
        termsAccepted = try container.decode(Bool.self, forKey: .termsAccepted)
        privacyAccepted = try container.decode(Bool.self, forKey: .privacyAccepted)
        coreDataAccepted = try container.decodeIfPresent(Bool.self, forKey: .coreDataAccepted) ?? false
    }
}

actor PendingOnboardingCache {
    private let url: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appending(path: "leafy-pending-onboarding.json")
    }

    func save(_ state: PendingOnboardingState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    func load() -> PendingOnboardingState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PendingOnboardingState.self, from: data)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
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
