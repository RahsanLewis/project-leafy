import Foundation

/// Civil calendar date `{year, month, day}` with no instant and no timezone.
///
/// Wire format is canonical `yyyy-MM-dd` only. Validity is a Gregorian UTC
/// round-trip so February 29 exists only on actual leap days.
struct LocalDate: Codable, Equatable, Hashable, Sendable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    enum ValidationError: Error, Equatable {
        case invalidCivilDate(year: Int, month: Int, day: Int)
        case invalidFormat(String)
    }

    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    init(year: Int, month: Int, day: Int) throws {
        guard Self.isValidGregorianUTC(year: year, month: month, day: day) else {
            throw ValidationError.invalidCivilDate(year: year, month: month, day: day)
        }
        self.year = year
        self.month = month
        self.day = day
    }

    init(isoString: String) throws {
        guard let parsed = Self.parseCanonical(isoString) else {
            throw ValidationError.invalidFormat(isoString)
        }
        self = parsed
    }

    /// Local civil Y/M/D of a DatePicker or other view-only Foundation Date.
    /// Uses the supplied timezone's Gregorian Y/M/D — never a UTC swap on the instant.
    init?(localCivilFrom date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let validated = try? LocalDate(year: year, month: month, day: day)
        else { return nil }
        self = validated
    }

    /// Y/M/D the previous Date-based UI would display in `timeZone`.
    static func displayed(from instant: Date, timeZone: TimeZone) -> LocalDate? {
        LocalDate(localCivilFrom: instant, timeZone: timeZone)
    }

    static func utcCivilDate(from instant: Date) -> LocalDate {
        let parts = gregorianUTC.dateComponents([.year, .month, .day], from: instant)
        return try! LocalDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func yearsBeforeNow(_ years: Int, now: Date = .now, timeZone: TimeZone = .current) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let past = calendar.date(byAdding: .year, value: -years, to: now) ?? now
        return LocalDate(localCivilFrom: past, timeZone: timeZone) ?? (try! LocalDate(year: 1996, month: 1, day: 1))
    }

    func ageInYears(asOf other: LocalDate) -> Int {
        var age = other.year - year
        if other.month < month || (other.month == month && other.day < day) {
            age -= 1
        }
        return age
    }

    func adding(days: Int) -> LocalDate {
        let start = Self.gregorianUTC.date(from: DateComponents(year: year, month: month, day: day))!
        let added = Self.gregorianUTC.date(byAdding: .day, value: days, to: start)!
        return LocalDate.utcCivilDate(from: added)
    }

    /// Transient formatter/DatePicker adapter at local noon. Never persist or calculate from this Date.
    func dateAtLocalNoon(timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    func dateForPicker(timeZone: TimeZone = .current) -> Date {
        dateAtLocalNoon(timeZone: timeZone) ?? .now
    }

    /// Language and field order only. The civil Y/M/D is authoritative in every timezone.
    func formatted(
        date style: Date.FormatStyle.DateStyle,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let adapter = dateAtLocalNoon(timeZone: timeZone) else { return isoString }
        var format = Date.FormatStyle(date: style, time: .omitted)
        format.locale = locale
        format.timeZone = timeZone
        return adapter.formatted(format)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let parsed = Self.parseCanonical(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected canonical yyyy-MM-dd, got \(string)"
            )
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func isValidGregorianUTC(year: Int, month: Int, day: Int) -> Bool {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let date = gregorianUTC.date(from: components) else { return false }
        let back = gregorianUTC.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }

    private static func parseCanonical(_ string: String) -> LocalDate? {
        guard string.count == 10 else { return nil }
        let characters = Array(string)
        guard characters[4] == "-", characters[7] == "-" else { return nil }
        let yearChars = characters[0...3]
        let monthChars = characters[5...6]
        let dayChars = characters[8...9]
        guard yearChars.allSatisfy(\.isNumber),
              monthChars.allSatisfy(\.isNumber),
              dayChars.allSatisfy(\.isNumber),
              let year = Int(String(yearChars)),
              let month = Int(String(monthChars)),
              let day = Int(String(dayChars))
        else { return nil }
        return try? LocalDate(year: year, month: month, day: day)
    }
}

extension LocalDate: CustomStringConvertible {
    var description: String { isoString }
}
