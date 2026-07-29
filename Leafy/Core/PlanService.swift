import Foundation
import Supabase

actor PlanService {
    enum ServiceError: LocalizedError {
        case notConfigured, notAuthenticated, invalidResponse(Int, String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Connect Leafy to Supabase in Config/Base.xcconfig before saving."
            case .notAuthenticated: "Please sign in before saving your plan."
            case let .invalidResponse(code, message): "The server returned \(code): \(message)"
            }
        }
    }

    let configuration: AppConfiguration
    let supabase: SupabaseClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        self.supabase = SupabaseClient(supabaseURL: configuration.supabaseURL, supabaseKey: configuration.supabaseKey)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(Self.dayFormatter)
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.dayFormatter.date(from: value) { return date }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: value) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid date: \(value)")
        }
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func currentUserID() async -> UUID? {
        guard configuration.isConfigured else { return nil }
        return try? await supabase.auth.session.user.id
    }

    func sendEmailCode(_ email: String) async throws {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        try await supabase.auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    func verifyEmailCode(email: String, code: String) async throws {
        try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        _ = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: identityToken, nonce: nonce)
        )
    }

    func signOut() async throws { try await supabase.auth.signOut() }

    func savePlan(_ input: NutritionPlanInput) async throws -> NutritionPlan {
        let data = try encoder.encode(input)
        return try await request(function: "save-nutrition-plan", body: data, response: NutritionPlan.self)
    }

    func fetchCloudState() async throws -> (NutritionPlan, NutritionPlanInput)? {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        let session = try await supabase.auth.session
        let planData = try await rest(path: "nutrition_plans?select=*&order=revision.desc&limit=1", accessToken: session.accessToken)
        let profileData = try await rest(path: "profiles?select=*&limit=1", accessToken: session.accessToken)
        guard let plan = try decoder.decode([NutritionPlan].self, from: planData).first,
              let profile = try JSONDecoder().decode([ProfileDTO].self, from: profileData).first
        else { return nil }
        return (plan, try profile.input())
    }

    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["apple_authorization_code": appleAuthorizationCode as Any].compactMapValues { $0 })
        let _: EmptyResponse = try await request(function: "delete-account", body: body, response: EmptyResponse.self)
    }

    private func request<T: Decodable>(function: String, body: Data, response: T.Type) async throws -> T {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        let session = try await supabase.auth.session
        let url = configuration.supabaseURL.appending(path: "functions/v1/\(function)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.invalidResponse(status, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func rest(path: String, accessToken: String) async throws -> Data {
        guard let url = URL(string: "\(configuration.supabaseURL.absoluteString)/rest/v1/\(path)") else { throw ServiceError.notConfigured }
        var request = URLRequest(url: url)
        request.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return data
    }
}

private struct EmptyResponse: Decodable { let ok: Bool }
private struct ProfileDTO: Decodable {
    let birthDate: String
    let calculationSex: CalculationSex
    let heightCM: Double
    let currentWeightKG: Double
    let targetWeightKG: Double?
    let activityLevel: ActivityLevel
    let goal: WeightGoal
    let pace: GoalPace
    let unitSystem: UnitSystem
    enum CodingKeys: String, CodingKey {
        case birthDate = "birth_date", calculationSex = "calculation_sex", heightCM = "height_cm"
        case currentWeightKG = "current_weight_kg", targetWeightKG = "target_weight_kg"
        case activityLevel = "activity_level", goal, pace, unitSystem = "unit_system"
    }
    func input() throws -> NutritionPlanInput {
        guard let date = PlanService.dayFormatter.date(from: birthDate) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid birth date"))
        }
        return NutritionPlanInput(birthDate: date, calculationSex: calculationSex, heightCM: heightCM, currentWeightKG: currentWeightKG, targetWeightKG: targetWeightKG, activityLevel: activityLevel, goal: goal, pace: pace, unitSystem: unitSystem)
    }
}

actor PlanCache {
    struct State: Codable { let plan: NutritionPlan; let input: NutritionPlanInput }
    private let url: URL
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appending(path: "leafy-current-plan.json")
    }
    func load() -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(State.self, from: data)
    }
    func save(_ plan: NutritionPlan, input: NutritionPlanInput) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(State(plan: plan, input: input))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutableURL = url; try? mutableURL.setResourceValues(values)
    }
    func clear() { try? FileManager.default.removeItem(at: url) }
}
