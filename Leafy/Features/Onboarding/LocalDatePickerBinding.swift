import SwiftUI

enum BirthDatePickerAdapter {
    /// UTC civil eligibility bounds converted to local-noon DatePicker adapters.
    static func allowableRange(
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> ClosedRange<Date> {
        let utc = TimeZone(secondsFromGMT: 0)!
        let earliest = LocalDate.yearsBeforeNow(120, now: now, timeZone: utc)
        let latest = LocalDate.yearsBeforeNow(18, now: now, timeZone: utc)
        return earliest.dateForPicker(timeZone: timeZone)...latest.dateForPicker(timeZone: timeZone)
    }
}

extension Binding where Value == LocalDate {
    /// DatePicker adapter. Converts selected local civil Y/M/D at the view boundary.
    var datePickerSelection: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue.dateForPicker() },
            set: { date in
                if let civil = LocalDate(localCivilFrom: date, timeZone: .current) {
                    wrappedValue = civil
                }
            }
        )
    }
}

extension OnboardingDraft {
    /// DatePicker adapter that marks a real user selection only when Y/M/D changes.
    var birthDatePickerSelection: Binding<Date> {
        Binding(
            get: { self.birthDate.dateForPicker() },
            set: { date in
                guard let civil = LocalDate(localCivilFrom: date, timeZone: .current) else { return }
                if civil != self.birthDate {
                    self.selectBirthDate(civil)
                }
            }
        )
    }
}
