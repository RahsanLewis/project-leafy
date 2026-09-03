import SwiftUI

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
            get: { birthDate.dateForPicker() },
            set: { date in
                guard let civil = LocalDate(localCivilFrom: date, timeZone: .current) else { return }
                if civil != birthDate {
                    selectBirthDate(civil)
                }
            }
        )
    }
}
