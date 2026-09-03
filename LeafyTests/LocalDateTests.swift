import XCTest
@testable import Leafy

final class LocalDateTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
    private let honolulu = TimeZone(identifier: "Pacific/Honolulu")!

    func testLeapDaysRoundTripAndRejectNonLeap() throws {
        XCTAssertEqual(try LocalDate(year: 2000, month: 2, day: 29).isoString, "2000-02-29")
        XCTAssertEqual(try LocalDate(year: 2024, month: 2, day: 29).isoString, "2024-02-29")
        XCTAssertThrowsError(try LocalDate(year: 1900, month: 2, day: 29))
        XCTAssertThrowsError(try LocalDate(year: 2026, month: 2, day: 29))
        XCTAssertThrowsError(try LocalDate(isoString: "1900-02-29"))
        XCTAssertThrowsError(try LocalDate(isoString: "2026-02-29"))
    }

    func testCodableAcceptsOnlyCanonicalYMD() throws {
        XCTAssertEqual(try decode("\"2000-02-29\""), try LocalDate(year: 2000, month: 2, day: 29))
        XCTAssertThrowsError(try decode("\"1996-7-01\""))
        XCTAssertThrowsError(try decode("\"1996-07-1\""))
        XCTAssertThrowsError(try decode("\"19960701\""))
        XCTAssertThrowsError(try decode("\"07/01/1996\""))
        XCTAssertThrowsError(try decode("\"1996-07-01T00:00:00Z\""))
        XCTAssertThrowsError(try decode("\"1996-02-30\""))
    }

    func testCodableIgnoresEncoderDateStrategies() throws {
        let date = try LocalDate(year: 1996, month: 7, day: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertEqual(String(data: try encoder.encode(date), encoding: .utf8), "\"1996-07-01\"")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(LocalDate.self, from: Data("\"1996-07-01\"".utf8)), date)
    }

    func testPickerBoundaryKeepsCivilDayInEverySurroundingZone() throws {
        let expected = try LocalDate(year: 2008, month: 7, day: 29)
        for timeZone in [utc, newYork, losAngeles, kiritimati, honolulu] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            calendar.timeZone = timeZone
            let pickerDate = calendar.date(from: DateComponents(year: 2008, month: 7, day: 29))!
            let civil = try XCTUnwrap(LocalDate(localCivilFrom: pickerDate, timeZone: timeZone))
            XCTAssertEqual(civil, expected, "local civil Y/M/D in \(timeZone.identifier)")

            let utcDay = LocalDate.utcCivilDate(from: pickerDate)
            if timeZone.identifier == "Pacific/Kiritimati" {
                XCTAssertEqual(utcDay, try LocalDate(year: 2008, month: 7, day: 28))
            }
        }
    }

    func testDisplayFormatsCivilDayWithoutTimezoneShift() throws {
        let date = try LocalDate(year: 2027, month: 5, day: 24)
        for timeZone in [utc, newYork, losAngeles, kiritimati, honolulu] {
            let formatted = date.formatted(date: .long, locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone)
            XCTAssertTrue(formatted.contains("24"), formatted)
            XCTAssertTrue(formatted.contains("May"), formatted)
        }
    }

    private func decode(_ json: String) throws -> LocalDate {
        try JSONDecoder().decode(LocalDate.self, from: Data(json.utf8))
    }
}
