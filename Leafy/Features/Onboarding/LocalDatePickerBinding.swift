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
