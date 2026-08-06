import SwiftUI

struct MorningCheckInView: View {
    private enum Step { case intake, weight }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .intake
    @State private var weightText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LeafySpacing.large) {
                    header
                    if step == .intake { intakeCard } else { weightCard }
                    if let error = app.checkInErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                    }
                }
                .padding(LeafySpacing.large)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }
                        .foregroundStyle(LeafyTheme.green)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(app.isCheckInMutationInProgress)
        .onAppear {
            step = app.morningCheckIn?.needsIntakeReview == true ? .intake : .weight
            let latest = app.weightEntries.first?.weightKG ?? app.draft.currentWeightKG
            let display = app.draft.unitSystem == .imperial ? latest * 2.20462 : latest
            weightText = display.formatted(.number.precision(.fractionLength(1)))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Image(systemName: step == .intake ? "checkmark.circle.fill" : "scalemass.fill")
                .font(.system(size: 42))
                .foregroundStyle(LeafyTheme.green)
            Text("Morning check-in")
                .font(LeafyTypography.largeTitle)
            Text(step == .intake
                 ? "Confirm yesterday’s food log so Leafy can learn from complete days."
                 : "Frequent weigh-ins help Leafy separate daily fluctuations from your longer-term trend.")
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
        }
    }

    private var intakeCard: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            if let checkIn = app.morningCheckIn {
                Text(checkIn.reviewDate.formatted(date: .complete, time: .omitted))
                    .font(LeafyTypography.headline)
                HStack(alignment: .firstTextBaseline) {
                    Text(checkIn.entries.isEmpty ? "No food logged" : "\(checkIn.calorieTotal.formatted()) Cal")
                        .font(LeafyTypography.title)
                    Spacer()
                    Text("\(checkIn.entries.count) \(checkIn.entries.count == 1 ? "item" : "items")")
                        .foregroundStyle(.secondary)
                }
                Divider()
                if checkIn.entries.isEmpty {
                    actionButton("I fasted", status: .fasted)
                    secondaryAction("I didn’t log yesterday", status: .incomplete)
                } else {
                    actionButton("Yes, this is complete", status: .confirmed)
                    Button("Review food log") {
                        app.selectedLogDate = checkIn.reviewDate
                        dismiss()
                        Task { await app.loadDailyLog() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    secondaryAction("I didn’t finish logging", status: .incomplete)
                }
            }
        }
        .padding(LeafySpacing.large)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            Text("Today’s weight")
                .font(LeafyTypography.headline)
            HStack(alignment: .firstTextBaseline) {
                TextField("Weight", text: $weightText)
                    .font(LeafyTypography.metric(48, extraBold: true))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(app.draft.unitSystem == .imperial ? "lb" : "kg")
                    .font(LeafyTypography.title3)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            Button("Log weight") { Task { await saveWeight() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(app.isWeightMutationInProgress || parsedWeightKG == nil)
            Button("Skip for today") { dismiss() }
                .frame(maxWidth: .infinity)
                .foregroundStyle(LeafyTheme.green)
        }
        .padding(LeafySpacing.large)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }

    private func actionButton(_ title: String, status: IntakeDayStatus) -> some View {
        Button(title) { Task { await update(status) } }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(app.isCheckInMutationInProgress)
    }

    private func secondaryAction(_ title: String, status: IntakeDayStatus) -> some View {
        Button(title) { Task { await update(status) } }
            .frame(maxWidth: .infinity)
            .foregroundStyle(LeafyTheme.green)
            .disabled(app.isCheckInMutationInProgress)
    }

    private func update(_ status: IntakeDayStatus) async {
        if await app.reviewYesterday(as: status) {
            if app.morningCheckIn?.needsWeight == true { step = .weight } else { dismiss() }
        }
    }

    private var parsedWeightKG: Double? {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let kg = app.draft.unitSystem == .imperial ? value / 2.20462 : value
        return (35...350).contains(kg) ? kg : nil
    }

    private func saveWeight() async {
        guard let kg = parsedWeightKG else { return }
        if await app.saveWeightEntry(nil, weightKG: kg, recordedOn: .now) { dismiss() }
    }
}
