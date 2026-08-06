import XCTest
@testable import Leafy

final class DailyReminderTests: XCTestCase {
    func testDefaultReminderUsesEightAM() {
        let preferences = DailyReminderPreferences(
            isEnabled: false,
            hour: DailyReminderPreferences.defaultHour,
            minute: DailyReminderPreferences.defaultMinute
        )

        XCTAssertEqual(preferences.dateComponents.hour, 8)
        XCTAssertEqual(preferences.dateComponents.minute, 0)
    }

    func testReminderPreservesUserSelectedTime() {
        let preferences = DailyReminderPreferences(isEnabled: true, hour: 6, minute: 45)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(preferences.dateComponents.hour, 6)
        XCTAssertEqual(preferences.dateComponents.minute, 45)
    }
}
