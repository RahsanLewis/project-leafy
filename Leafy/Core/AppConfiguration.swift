import Foundation

struct AppConfiguration: Sendable {
    let supabaseURL: URL
    let supabaseKey: String
    let privacyURL: URL
    let termsURL: URL
    let supportURL: URL
    let googleIOSClientID: String
    let googleServerClientID: String
    let googleReversedClientID: String
    let authCallbackURL: URL
    let authURLScheme: String
    let environment: String

    static func live(bundle: Bundle = .main) -> AppConfiguration {
        func string(_ key: String) -> String { bundle.object(forInfoDictionaryKey: key) as? String ?? "" }
        return AppConfiguration(
            supabaseURL: URL(string: string("SUPABASE_URL")) ?? URL(string: "https://example.supabase.co")!,
            supabaseKey: string("SUPABASE_PUBLISHABLE_KEY"),
            privacyURL: URL(string: string("PRIVACY_POLICY_URL")) ?? URL(string: "https://example.com/privacy")!,
            termsURL: URL(string: string("TERMS_URL")) ?? URL(string: "https://example.com/terms")!,
            supportURL: URL(string: string("SUPPORT_URL")) ?? URL(string: "https://example.com/support")!,
            googleIOSClientID: string("GOOGLE_IOS_CLIENT_ID"),
            googleServerClientID: string("GOOGLE_SERVER_CLIENT_ID"),
            googleReversedClientID: string("GOOGLE_REVERSED_CLIENT_ID"),
            authCallbackURL: URL(string: string("AUTH_CALLBACK_URL")) ?? URL(string: "https://auth.projectleafy.app/auth/callback")!,
            authURLScheme: string("AUTH_URL_SCHEME").isEmpty ? "leafy" : string("AUTH_URL_SCHEME"),
            environment: string("APP_ENVIRONMENT").isEmpty ? "production" : string("APP_ENVIRONMENT")
        )
    }

    var isConfigured: Bool { !supabaseKey.contains("YOUR_") && !supabaseURL.host!.contains("example") }
    var isGoogleConfigured: Bool {
        googleIOSClientID.hasSuffix(".apps.googleusercontent.com") &&
        googleServerClientID.hasSuffix(".apps.googleusercontent.com") &&
        googleReversedClientID == googleIOSClientID.split(separator: ".").reversed().joined(separator: ".")
    }

    /// Food Impact remains available to non-production builds while it is refined.
    var isFoodImpactEnabled: Bool {
        environment.caseInsensitiveCompare("production") != .orderedSame
    }
}
