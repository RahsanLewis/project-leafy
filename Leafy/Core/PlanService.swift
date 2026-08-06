import Foundation
import Supabase

actor PlanService {
    enum ServiceError: LocalizedError {
        case notConfigured, notAuthenticated, invalidResponse(Int, String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Connect Leafy to Supabase in Config/Base.xcconfig before saving."
            case .notAuthenticated: "Your session has expired. Sign in again to continue."
            case let .invalidResponse(code, message):
                message.isEmpty ? "The server could not complete the request (\(code))." : message
            }
        }
    }

    let configuration: AppConfiguration
    let supabase: SupabaseClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var activeAccessToken: String?

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
        guard let session = try? await supabase.auth.session else { return nil }
        activeAccessToken = session.accessToken
        return session.user.id
    }

    func createAccount(email: String, password: String) async throws -> Bool {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        let response = try await supabase.auth.signUp(email: email, password: password)
        if case let .session(session) = response {
            activeAccessToken = session.accessToken
            return false
        }
        return true
    }

    func resendAccountConfirmation(email: String) async throws {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        try await supabase.auth.resend(email: email, type: .signup)
    }

    func signIn(email: String, password: String) async throws -> String {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        let session = try await supabase.auth.signIn(email: email, password: password)
        activeAccessToken = session.accessToken
        return session.accessToken
    }

    func signInWithApple(identityToken: String, nonce: String) async throws -> String {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        let session = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: identityToken, nonce: nonce)
        )
        activeAccessToken = session.accessToken
        return session.accessToken
    }

    func signOut() async throws {
        defer { activeAccessToken = nil }
        try await supabase.auth.signOut()
    }

    func savePlan(_ input: NutritionPlanInput, accessToken: String? = nil) async throws -> NutritionPlan {
        let data = try encoder.encode(input)
        return try await request(function: "save-nutrition-plan", body: data, accessToken: accessToken, response: NutritionPlan.self)
    }

    func fetchCloudState(accessToken suppliedToken: String? = nil) async throws -> (NutritionPlan, NutritionPlanInput)? {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        let accessToken: String
        if let suppliedToken {
            accessToken = suppliedToken
            activeAccessToken = suppliedToken
        } else {
            accessToken = try await resolvedAccessToken()
        }
        let planData = try await rest(path: "nutrition_plans?select=*&order=revision.desc&limit=1", accessToken: accessToken)
        let profileData = try await rest(path: "profiles?select=*&limit=1", accessToken: accessToken)
        guard let plan = try decoder.decode([NutritionPlan].self, from: planData).first,
              let profile = try JSONDecoder().decode([ProfileDTO].self, from: profileData).first
        else { return nil }
        return (plan, try profile.input())
    }

    func fetchFoodEntries(on date: Date, calendar: Calendar = .current) async throws -> [FoodEntry] {
        let token = try await resolvedAccessToken()
        let localDate = Self.localDayString(for: date, calendar: calendar)
        let data = try await rest(
            path: "food_entries?select=*&local_date=eq.\(localDate)&order=consumed_at.asc",
            accessToken: token
        )
        return try decoder.decode([FoodEntry].self, from: data)
    }

    func fetchPlan(activeAt endOfDay: Date) async throws -> NutritionPlan? {
        let token = try await resolvedAccessToken()
        let cutoff = ISO8601DateFormatter().string(from: endOfDay)
        let data = try await rest(
            path: "nutrition_plans?select=*&created_at=lte.\(cutoff)&order=created_at.desc&limit=1",
            accessToken: token
        )
        return try decoder.decode([NutritionPlan].self, from: data).first
    }

    func fetchWeightEntries() async throws -> [WeightEntry] {
        let token = try await resolvedAccessToken()
        let data = try await rest(
            path: "weight_entries?select=*&order=recorded_on.desc",
            accessToken: token
        )
        return try decoder.decode([WeightEntry].self, from: data)
    }

    func fetchIntakeDay(on date: Date, calendar: Calendar = .current) async throws -> DailyIntakeDay? {
        let token = try await resolvedAccessToken()
        let localDate = Self.localDayString(for: date, calendar: calendar)
        let data = try await rest(
            path: "daily_intake_days?select=*&local_date=eq.\(localDate)&limit=1",
            accessToken: token
        )
        return try decoder.decode([DailyIntakeDay].self, from: data).first
    }

    func fetchLatestPlanAdjustment() async throws -> PlanAdjustmentNotice? {
        let token = try await resolvedAccessToken()
        let data = try await rest(
            path: "plan_adjustments?select=*&acknowledged_at=is.null&order=applied_at.desc&limit=1",
            accessToken: token
        )
        return try decoder.decode([PlanAdjustmentNotice].self, from: data).first
    }

    func updateDailyCheckIn(
        status: IntakeDayStatus,
        on date: Date,
        calendar: Calendar = .current
    ) async throws -> DailyCheckInResponse {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": status.rawValue,
            "local_date": Self.localDayString(for: date, calendar: calendar),
            "time_zone": calendar.timeZone.identifier
        ])
        return try await request(function: "manage-daily-checkin", body: body, response: DailyCheckInResponse.self)
    }

    func refreshAdaptiveTarget(calendar: Calendar = .current) async throws -> DailyCheckInResponse {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "refresh",
            "time_zone": calendar.timeZone.identifier
        ])
        return try await request(function: "manage-daily-checkin", body: body, response: DailyCheckInResponse.self)
    }

    func acknowledgePlanAdjustment(id: UUID) async throws {
        let token = try await resolvedAccessToken()
        let body = try JSONSerialization.data(withJSONObject: [
            "acknowledged_at": ISO8601DateFormatter().string(from: .now)
        ])
        _ = try await restMutation(
            method: "PATCH",
            path: "plan_adjustments?id=eq.\(id.uuidString)",
            accessToken: token,
            body: body,
            prefer: "return=minimal"
        )
    }

    func saveWeightEntry(id: UUID?, weightKG: Double, recordedOn: Date, calendar: Calendar = .current) async throws -> WeightMutationResponse {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "upsert",
            "id": id?.uuidString as Any,
            "weight_kg": weightKG,
            "recorded_on": Self.localDayString(for: recordedOn, calendar: calendar),
            "time_zone": calendar.timeZone.identifier
        ].compactMapValues { $0 })
        return try await request(function: "manage-weight-entry", body: body, response: WeightMutationResponse.self)
    }

    func deleteWeightEntry(id: UUID) async throws -> WeightMutationResponse {
        let body = try JSONSerialization.data(withJSONObject: ["action": "delete", "id": id.uuidString])
        return try await request(function: "manage-weight-entry", body: body, response: WeightMutationResponse.self)
    }

    func createFoodEntry(_ input: FoodEntryInput, on localDate: Date, calendar: Calendar = .current) async throws -> FoodEntry {
        let token = try await resolvedAccessToken()
        let body = try foodEntryBody(input, localDate: localDate, calendar: calendar, includeUpdatedAt: false)
        let data = try await restMutation(method: "POST", path: "food_entries", accessToken: token, body: body, prefer: "return=representation")
        guard let entry = try decoder.decode([FoodEntry].self, from: data).first else { throw ServiceError.invalidResponse(200, "No food entry was returned.") }
        return entry
    }

    func fetchDataContributionStatus() async throws -> DataContributionStatus {
        let body = try JSONSerialization.data(withJSONObject: ["action": "status"])
        return try await request(function: "manage-data-contribution", body: body, response: DataContributionStatus.self)
    }

    func joinDataContribution(countryCode: String, regionCode: String?) async throws -> DataContributionStatus {
        var object: [String: Any] = [
            "action": "join",
            "jurisdiction_country": countryCode,
        ]
        if let regionCode { object["jurisdiction_region"] = regionCode }
        let body = try JSONSerialization.data(withJSONObject: object)
        return try await request(function: "manage-data-contribution", body: body, response: DataContributionStatus.self)
    }

    func leaveDataContribution() async throws -> DataContributionStatus {
        let body = try JSONSerialization.data(withJSONObject: ["action": "leave"])
        return try await request(function: "manage-data-contribution", body: body, response: DataContributionStatus.self)
    }

    func updateFoodEntry(id: UUID, input: FoodEntryInput, on localDate: Date, calendar: Calendar = .current) async throws -> FoodEntry {
        let token = try await resolvedAccessToken()
        let body = try foodEntryBody(input, localDate: localDate, calendar: calendar, includeUpdatedAt: true)
        let data = try await restMutation(method: "PATCH", path: "food_entries?id=eq.\(id.uuidString)", accessToken: token, body: body, prefer: "return=representation")
        guard let entry = try decoder.decode([FoodEntry].self, from: data).first else { throw ServiceError.invalidResponse(404, "Food entry not found.") }
        return entry
    }

    func deleteFoodEntry(id: UUID) async throws {
        let token = try await resolvedAccessToken()
        _ = try await restMutation(method: "DELETE", path: "food_entries?id=eq.\(id.uuidString)", accessToken: token, body: nil, prefer: "return=minimal")
    }

    func searchProducts(_ query: String) async throws -> [ProductSummary] {
        let body = try JSONSerialization.data(withJSONObject: ["action": "search", "query": query])
        let result: ProductListResponse = try await request(function: "discover-food-product", body: body, response: ProductListResponse.self)
        return result.products
    }

    func lookupProduct(barcode: String) async throws -> ProductSummary? {
        let body = try JSONSerialization.data(withJSONObject: ["action": "barcode", "barcode": barcode])
        let result: ProductSummaryResponse = try await request(function: "discover-food-product", body: body, response: ProductSummaryResponse.self)
        return result.product
    }

    func productDetail(for product: ProductSummary) async throws -> ProductDetail {
        var object: [String: Any] = ["action": "detail"]
        if let id = product.foodVersionID { object["food_version_id"] = id.uuidString }
        else if let id = product.fdcID { object["fdc_id"] = id }
        let body = try JSONSerialization.data(withJSONObject: object)
        let result: ProductDetailResponse = try await request(function: "discover-food-product", body: body, response: ProductDetailResponse.self)
        return result.product
    }

    func fetchProductHistory() async throws -> [ProductSummary] {
        let body = try JSONSerialization.data(withJSONObject: ["action": "history"])
        let result: ProductListResponse = try await request(function: "discover-food-product", body: body, response: ProductListResponse.self)
        return result.products
    }

    func logProduct(_ product: ProductDetail, grams: Double, consumedAt: Date, localDate: Date, mealType: MealType, calendar: Calendar = .current) async throws -> FoodEntry {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "log", "food_version_id": product.foodVersionID.uuidString,
            "grams": grams, "consumed_at": ISO8601DateFormatter().string(from: consumedAt),
            "local_date": Self.localDayString(for: localDate, calendar: calendar),
            "time_zone": calendar.timeZone.identifier, "meal_type": mealType.rawValue,
        ])
        let result: ProductLogResponse = try await request(function: "discover-food-product", body: body, response: ProductLogResponse.self)
        return result.entry
    }

    func uploadMealPhoto(_ data: Data, sessionID: UUID) async throws -> String {
        guard data.count <= 4 * 1024 * 1024 else {
            throw ServiceError.invalidResponse(413, "Choose a meal photo smaller than 4 MB.")
        }
        guard let userID = await currentUserID() else { throw ServiceError.notAuthenticated }
        let token = try await resolvedAccessToken()
        let path = "\(userID.uuidString.lowercased())/ai-meals/\(sessionID.uuidString.lowercased()).jpg"
        guard let url = URL(string: "\(configuration.supabaseURL.absoluteString)/storage/v1/object/nutrition-media/\(path)") else {
            throw ServiceError.notConfigured
        }
        var upload = URLRequest(url: url)
        upload.httpMethod = "POST"
        upload.httpBody = data
        upload.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        upload.setValue("true", forHTTPHeaderField: "x-upsert")
        let (responseData, response) = try await URLSession.shared.data(for: upload)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0, Self.apiErrorMessage(from: responseData))
        }
        return path
    }

    func estimateMeal(_ input: MealEstimateInput, photoObjectPath: String?) async throws -> MealEstimate {
        var object: [String: Any] = [
            "action": "analyze", "session_id": input.sessionID.uuidString.lowercased(),
            "description": input.description, "voice_transcript": input.voiceTranscript,
            "consumed_at": ISO8601DateFormatter().string(from: input.consumedAt),
            "local_date": Self.localDayString(for: input.localDate),
            "time_zone": Calendar.current.timeZone.identifier, "meal_type": input.mealType.rawValue,
        ]
        if let photoObjectPath { object["photo_object_path"] = photoObjectPath }
        let body = try JSONSerialization.data(withJSONObject: object)
        return try await request(function: "estimate-meal", body: body, response: MealEstimate.self)
    }

    func answerMealEstimate(sessionID: UUID, answer: String?, skip: Bool) async throws -> MealEstimate {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "answer", "session_id": sessionID.uuidString.lowercased(),
            "answer": answer ?? "", "skip": skip,
        ])
        return try await request(function: "estimate-meal", body: body, response: MealEstimate.self)
    }

    func confirmMealEstimate(sessionID: UUID, items: [MealConfirmationItem]) async throws -> [FoodEntry] {
        let encodedItems = items.map { item in
            ["id": item.id.uuidString.lowercased(), "name": item.name, "portion": item.portion, "calories": item.calories] as [String: Any]
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "confirm", "session_id": sessionID.uuidString.lowercased(), "items": encodedItems,
        ])
        let result: MealConfirmationResponse = try await request(function: "estimate-meal", body: body, response: MealConfirmationResponse.self)
        return result.entries
    }

    func discardMealEstimate(sessionID: UUID) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "discard", "session_id": sessionID.uuidString.lowercased(),
        ])
        let _: EmptyResponse = try await request(function: "estimate-meal", body: body, response: EmptyResponse.self)
    }

    func deleteAIMealEntry(id: UUID) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "delete_entry", "food_entry_id": id.uuidString.lowercased(),
        ])
        let _: EmptyResponse = try await request(function: "estimate-meal", body: body, response: EmptyResponse.self)
    }

    func transcribeMealAudio(at fileURL: URL) async throws -> String {
        let token = try await resolvedAccessToken()
        let audio = try Data(contentsOf: fileURL)
        guard audio.count <= 3 * 1024 * 1024 else {
            throw ServiceError.invalidResponse(413, "Keep voice descriptions under 60 seconds.")
        }
        let boundary = "LeafyBoundary\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"meal.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let url = configuration.supabaseURL.appending(path: "functions/v1/transcribe-meal-audio")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0, Self.apiErrorMessage(from: data))
        }
        return try decoder.decode(MealTranscriptionResponse.self, from: data).transcript
    }

    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["apple_authorization_code": appleAuthorizationCode as Any].compactMapValues { $0 })
        let _: EmptyResponse = try await request(function: "delete-account", body: body, response: EmptyResponse.self)
    }

    private func request<T: Decodable>(function: String, body: Data, accessToken suppliedToken: String? = nil, response: T.Type) async throws -> T {
        guard configuration.isConfigured else { throw ServiceError.notConfigured }
        let accessToken: String
        if let suppliedToken {
            accessToken = suppliedToken
            activeAccessToken = suppliedToken
        } else {
            accessToken = try await resolvedAccessToken()
        }
        let url = configuration.supabaseURL.appending(path: "functions/v1/\(function)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.invalidResponse(status, Self.apiErrorMessage(from: data))
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
            throw ServiceError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0, Self.apiErrorMessage(from: data))
        }
        return data
    }

    private func restMutation(method: String, path: String, accessToken: String, body: Data?, prefer: String) async throws -> Data {
        guard let url = URL(string: "\(configuration.supabaseURL.absoluteString)/rest/v1/\(path)") else { throw ServiceError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0, Self.apiErrorMessage(from: data))
        }
        return data
    }

    private static func apiErrorMessage(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(APIErrorPayload.self, from: data), !payload.error.isEmpty {
            return payload.error
        }
        return String(data: data, encoding: .utf8) ?? "The server could not complete the request."
    }

    private func foodEntryBody(_ input: FoodEntryInput, localDate: Date, calendar: Calendar, includeUpdatedAt: Bool) throws -> Data {
        var object: [String: Any] = [
            "name": input.normalizedName,
            "calories": input.calories,
            "consumed_at": ISO8601DateFormatter().string(from: input.consumedAt),
            "local_date": Self.localDayString(for: localDate, calendar: calendar),
            "time_zone": calendar.timeZone.identifier,
            "meal_type": input.mealType.rawValue,
            "user_confirmed": true,
            "provenance": ["capture_version": "ios-v2"]
        ]
        if let amount = input.amount { object["amount"] = amount }
        if let amountUnit = input.amountUnit { object["amount_unit"] = amountUnit }
        if let gramWeight = input.gramWeight { object["gram_weight"] = gramWeight }
        if let portionDescription = input.portionDescription { object["portion_description"] = portionDescription }
        if includeUpdatedAt { object["updated_at"] = ISO8601DateFormatter().string(from: .now) }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func resolvedAccessToken() async throws -> String {
        if let session = try? await supabase.auth.session {
            activeAccessToken = session.accessToken
            return session.accessToken
        }
        if let activeAccessToken { return activeAccessToken }
        throw ServiceError.notAuthenticated
    }

    static func localDayString(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private struct APIErrorPayload: Decodable { let error: String }
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
