import XCTest
@testable import Leafy

@MainActor
final class AuthenticationRoutingTests: XCTestCase {
    func testAppStartsInLaunchingState() {
        let app = AppModel()
        XCTAssertEqual(app.route, .launching)
    }

    func testPresentingReturningUserAuthenticationRecordsPurpose() {
        let app = AppModel()
        app.errorMessage = "Old error"
        app.statusMessage = "Old status"

        app.presentAuthentication(.accessExistingAccount)

        XCTAssertTrue(app.showAuthentication)
        XCTAssertEqual(app.authenticationPurpose, .accessExistingAccount)
        XCTAssertNil(app.errorMessage)
        XCTAssertNil(app.statusMessage)
    }

    func testPlanSavingAuthenticationRemainsAvailable() {
        let app = AppModel()
        app.presentAuthentication(.savePlan)

        XCTAssertEqual(app.authenticationPurpose, .savePlan)
    }
}
