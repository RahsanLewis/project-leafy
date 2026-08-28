import Foundation
import Supabase

actor AuthService {
    let configuration: AppConfiguration
    nonisolated let supabase: SupabaseClient
    private var activeAccessToken: String?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        supabase = SupabaseClient(supabaseURL: configuration.supabaseURL, supabaseKey: configuration.supabaseKey)
    }

    func currentUserID() async -> UUID? {
        guard configuration.isConfigured, let session = try? await supabase.auth.session else { return nil }
        activeAccessToken = session.accessToken
        return session.user.id
    }

    func resolvedAccessToken(_ supplied: String? = nil) async throws -> String {
        if let supplied { activeAccessToken = supplied; return supplied }
        if let session = try? await supabase.auth.session {
            activeAccessToken = session.accessToken
            return session.accessToken
        }
        if let activeAccessToken { return activeAccessToken }
        throw PlanService.ServiceError.notAuthenticated
    }

    func clearAccessToken() { activeAccessToken = nil }
}

enum RESTReadEndpoint: Sendable {
    case latestPlan
    case profile
    case foodEntries(localDate: String)
    case foodEntry(id: UUID, fields: String)
    case activePlan(cutoff: String)
    case weightEntries
    case intakeDay(localDate: String)
    case latestPlanAdjustment

    var path: String {
        switch self {
        case .latestPlan: "nutrition_plans?select=*&order=revision.desc&limit=1"
        case .profile: "profiles?select=*&limit=1"
        case let .foodEntries(localDate): "food_entries_with_score?select=*&local_date=eq.\(localDate)&order=consumed_at.asc"
        case let .foodEntry(id, fields): "food_entries_with_score?select=\(fields)&id=eq.\(id.uuidString)&limit=1"
        case let .activePlan(cutoff): "nutrition_plans?select=*&created_at=lte.\(cutoff)&order=created_at.desc&limit=1"
        case .weightEntries: "weight_entries?select=*&order=recorded_on.desc"
        case let .intakeDay(localDate): "daily_intake_days?select=*&local_date=eq.\(localDate)&limit=1"
        case .latestPlanAdjustment: "plan_adjustments?select=*&acknowledged_at=is.null&order=applied_at.desc&limit=1"
        }
    }
}

struct RESTReadClient: Sendable {
    let configuration: AppConfiguration

    func get(_ endpoint: RESTReadEndpoint, accessToken: String) async throws -> Data {
        guard let url = URL(string: "\(configuration.supabaseURL.absoluteString)/rest/v1/\(endpoint.path)") else {
            throw PlanService.ServiceError.notConfigured
        }
        var request = URLRequest(url: url)
        request.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlanService.ServiceError.invalidResponse(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                PlanService.apiErrorMessage(from: data)
            )
        }
        return data
    }
}

struct EdgeFunctionClient: Sendable {
    let configuration: AppConfiguration

    func post<T: Decodable>(function: String, body: Data, accessToken: String, response: T.Type) async throws -> T {
        let url = configuration.supabaseURL.appending(path: "functions/v1/\(function)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlanService.ServiceError.invalidResponse(
                (urlResponse as? HTTPURLResponse)?.statusCode ?? 0,
                PlanService.apiErrorMessage(from: data)
            )
        }
        return try PlanService.makeDecoder().decode(T.self, from: data)
    }
}

struct StorageUploadClient: Sendable {
    let configuration: AppConfiguration

    func uploadJPEG(_ data: Data, path: String, accessToken: String) async throws {
        guard let url = URL(string: "\(configuration.supabaseURL.absoluteString)/storage/v1/object/nutrition-media/\(path)") else {
            throw PlanService.ServiceError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlanService.ServiceError.invalidResponse(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                PlanService.apiErrorMessage(from: responseData)
            )
        }
    }
}
