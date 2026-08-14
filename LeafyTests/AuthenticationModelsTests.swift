import XCTest
@testable import Leafy

final class AuthenticationModelsTests: XCTestCase {
    private func configuration(
        iosClientID: String,
        serverClientID: String,
        reversedClientID: String
    ) -> AppConfiguration {
        AppConfiguration(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "publishable-key",
            privacyURL: URL(string: "https://projectleafy.app/privacy")!,
            termsURL: URL(string: "https://projectleafy.app/terms")!,
            supportURL: URL(string: "https://projectleafy.app/support")!,
            googleIOSClientID: iosClientID,
            googleServerClientID: serverClientID,
            googleReversedClientID: reversedClientID,
            authCallbackURL: URL(string: "https://auth.projectleafy.app/auth/callback")!,
            authURLScheme: "leafy",
            environment: "production"
        )
    }

    func testAuthRoutesAcceptOnlyLeafyUniversalAndCustomLinks() {
        let config = configuration(iosClientID: "", serverClientID: "", reversedClientID: "")
        XCTAssertEqual(AuthLinkRoute.parse(URL(string: "https://auth.projectleafy.app/auth/callback")!, configuration: config), .callback)
        XCTAssertEqual(AuthLinkRoute.parse(URL(string: "https://auth.projectleafy.app/auth/reset")!, configuration: config), .passwordRecovery)
        XCTAssertEqual(AuthLinkRoute.parse(URL(string: "leafy://auth/callback")!, configuration: config), .callback)
        XCTAssertNil(AuthLinkRoute.parse(URL(string: "https://example.com/auth/callback")!, configuration: config))
        XCTAssertNil(AuthLinkRoute.parse(URL(string: "leafy://malicious/callback")!, configuration: config))
    }

    func testStagingAuthRoutesCannotAcceptProductionLinks() {
        let config = AppConfiguration(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "publishable-key",
            privacyURL: URL(string: "https://projectleafy.app/privacy")!,
            termsURL: URL(string: "https://projectleafy.app/terms")!,
            supportURL: URL(string: "https://projectleafy.app/support")!,
            googleIOSClientID: "",
            googleServerClientID: "",
            googleReversedClientID: "",
            authCallbackURL: URL(string: "https://auth-staging.projectleafy.app/auth/callback")!,
            authURLScheme: "leafy-staging",
            environment: "staging"
        )

        XCTAssertEqual(AuthLinkRoute.parse(URL(string: "https://auth-staging.projectleafy.app/auth/reset")!, configuration: config), .passwordRecovery)
        XCTAssertEqual(AuthLinkRoute.parse(URL(string: "leafy-staging://auth/callback")!, configuration: config), .callback)
        XCTAssertNil(AuthLinkRoute.parse(URL(string: "https://auth.projectleafy.app/auth/callback")!, configuration: config))
        XCTAssertNil(AuthLinkRoute.parse(URL(string: "leafy://auth/callback")!, configuration: config))
    }

    func testGoogleConfigurationRequiresMatchingClientIDsAndURLScheme() {
        let iosClientID = "123-ios.apps.googleusercontent.com"
        let valid = configuration(
            iosClientID: iosClientID,
            serverClientID: "123-web.apps.googleusercontent.com",
            reversedClientID: "com.googleusercontent.apps.123-ios"
        )
        let mismatchedScheme = configuration(
            iosClientID: iosClientID,
            serverClientID: "123-web.apps.googleusercontent.com",
            reversedClientID: "com.googleusercontent.apps.wrong"
        )

        XCTAssertTrue(valid.isGoogleConfigured)
        XCTAssertFalse(mismatchedScheme.isGoogleConfigured)
    }
}
