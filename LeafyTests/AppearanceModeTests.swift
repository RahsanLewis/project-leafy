import XCTest
@testable import Leafy

final class AppearanceModeTests: XCTestCase {
    func testLightIsThePersistedDefault() {
        XCTAssertEqual(AppearanceMode.light.rawValue, "light")
        XCTAssertEqual(AppearanceMode.light.preferredColorScheme, .light)
    }

    func testDarkForcesDarkColorScheme() {
        XCTAssertEqual(AppearanceMode.dark.preferredColorScheme, .dark)
    }

    func testFollowSystemDoesNotForceAColorScheme() {
        XCTAssertNil(AppearanceMode.system.preferredColorScheme)
    }

    func testStoredValuesRoundTrip() {
        for mode in AppearanceMode.allCases {
            XCTAssertEqual(AppearanceMode(rawValue: mode.rawValue), mode)
        }
    }
}
