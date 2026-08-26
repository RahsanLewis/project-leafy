import XCTest
@testable import Leafy

@MainActor
final class AuthenticationRoutingTests: XCTestCase {
    func testAppStartsInLaunchingState() {
        let app = AppModel()
        XCTAssertEqual(app.route, .launching)
    }

    func testPresentingAuthenticationClearsTransientMessages() {
        let app = AppModel()
        app.errorMessage = "Old error"
        app.statusMessage = "Old status"

        app.presentAuthentication()

        XCTAssertTrue(app.showAuthentication)
        XCTAssertNil(app.errorMessage)
        XCTAssertNil(app.statusMessage)
    }
}
