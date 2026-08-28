import XCTest
@testable import Leafy

@MainActor
final class AuthenticationRoutingTests: XCTestCase {
    func testAppStartsInLaunchingState() {
        let app = AppCoordinator()
        XCTAssertEqual(app.route, .launching)
    }

    func testPresentingAuthenticationClearsTransientMessages() {
        let app = AppCoordinator()
        app.errorMessage = "Old error"
        app.statusMessage = "Old status"

        app.presentAuthentication()

        XCTAssertTrue(app.showAuthentication)
        XCTAssertNil(app.errorMessage)
        XCTAssertNil(app.statusMessage)
    }
}
