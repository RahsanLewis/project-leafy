import Foundation

struct AppConfiguration: Sendable {
    let supabaseURL: URL
    let supabaseKey: String
    let privacyURL: URL
    let termsURL: URL
    let supportURL: URL

    static func live(bundle: Bundle = .main) -> AppConfiguration {
        func string(_ key: String) -> String { bundle.object(forInfoDictionaryKey: key) as? String ?? "" }
        return AppConfiguration(
            supabaseURL: URL(string: string("SUPABASE_URL")) ?? URL(string: "https://example.supabase.co")!,
            supabaseKey: string("SUPABASE_PUBLISHABLE_KEY"),
            privacyURL: URL(string: string("PRIVACY_POLICY_URL")) ?? URL(string: "https://example.com/privacy")!,
            termsURL: URL(string: string("TERMS_URL")) ?? URL(string: "https://example.com/terms")!,
            supportURL: URL(string: string("SUPPORT_URL")) ?? URL(string: "https://example.com/support")!
        )
    }

    var isConfigured: Bool { !supabaseKey.contains("YOUR_") && !supabaseURL.host!.contains("example") }
}

