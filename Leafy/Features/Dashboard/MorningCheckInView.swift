import SwiftUI
import UIKit

struct MorningCheckInView: View {
    private enum Step { case intake, weight }
    private enum IntakeChoice: Equatable {
        case status(IntakeDayStatus)
        case logNow
    }

    @Environment(AppCoordinator.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .intake
    @State private var selectedChoice: IntakeChoice?
    @State private var weightSelection = WeightWheelSelection(kilograms: 77)
    @State private var showsTwoSteps = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showsTwoSteps { progressBar }
                ScrollView {
                    VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                        header
                        if step == .intake { intakeContent } else { weightContent }
                        if let error = app.checkInErrorMessage ?? (step == .weight ? app.weightErrorMessage : nil) {
                            inlineError(error)
                        }
                    }
                    .padding(LeafyTheme.pageInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(step)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                bottomAction
            }
            .background(LeafyTheme.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }
                        .foregroundStyle(LeafyTheme.green)
                        .disabled(app.isCheckInMutationInProgress || app.isWeightMutationInProgress)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(app.isCheckInMutationInProgress || app.isWeightMutationInProgress)
        .onAppear {
            let needsIntake = app.morningCheckIn?.needsIntakeReview == true
            let needsWeight = app.morningCheckIn?.needsWeight == true
            showsTwoSteps = needsIntake && needsWeight
            step = needsIntake ? .intake : .weight
            let latest = app.weightEntries.first?.weightKG ?? app.draft.currentWeightKG
            weightSelection = WeightWheelSelection(kilograms: latest)
            selectedChoice = nil
            app.checkInErrorMessage = nil
            app.weightErrorMessage = nil
        }
        .animation(reduceMotion ? .none : LeafyMotion.content, value: step)
    }

    private var progressBar: some View {
        ProgressView(value: step == .intake ? 1 : 2, total: 2)
            .tint(LeafyTheme.green)
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.top, LeafySpacing.small)
            .accessibilityLabel("Morning check-in progress")
            .accessibilityValue(step == .intake ? "Step 1 of 2" : "Step 2 of 2")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(step == .intake ? intakeTitle : "Today’s weight")
                .font(LeafyTypography.largeTitle)
            Text(step == .intake
                 ? intakeSubtitle
                 : "Frequent weigh-ins help Leafy separate daily fluctuations from your longer-term trend.")
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var intakeContent: some View {
        if let checkIn = app.morningCheckIn {
            VStack(alignment: .leading, spacing: LeafySpacing.large) {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Text(checkIn.reviewDate.formatted(date: .complete, time: .omitted))
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(checkIn.entries.isEmpty ? "No food logged" : "\(checkIn.calorieTotal.formatted()) Cal")
                            .font(LeafyTypography.metric(36, extraBold: true))
                        Spacer()
                        Text("\(checkIn.entries.count) \(checkIn.entries.count == 1 ? "item" : "items")")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !checkIn.entries.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(checkIn.entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.name).font(LeafyTypography.body)
                                Spacer()
                                Text("\(entry.calories) Cal")
                                    .font(LeafyTypography.subheadlineSemibold)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: LeafyTheme.rowMinHeight)
                            if index < min(checkIn.entries.count, 3) - 1 {
                                Divider().overlay(LeafyTheme.hairline)
                            }
                        }
                        if checkIn.entries.count > 3 {
                            Text("+ \(checkIn.entries.count - 3) more")
                                .font(LeafyTypography.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, LeafySpacing.small)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Button("Review food log", systemImage: "list.bullet") {
                        app.selectedLogDate = checkIn.reviewDate
                        dismiss()
                        Task { await app.loadDailyLog() }
                    }
                    .font(LeafyTypography.button)
                    .accessibilityIdentifier("reviewYesterdayFoodLogButton")
                }

                VStack(spacing: 0) {
                    if checkIn.entries.isEmpty {
                        choiceRow(
                            "I fasted",
                            explanation: "Continue to today’s weight.",
                            choice: .status(.fasted),
                            identifier: "morningIntakeFasted"
                        )
                        Divider().overlay(LeafyTheme.hairline)
                        choiceRow(
                            "Log what I ate",
                            explanation: "Add yesterday’s food now.",
                            choice: .logNow,
                            identifier: "morningIntakeLogNow"
                        )
                        Divider().overlay(LeafyTheme.hairline)
                        choiceRow(
                            "Skip yesterday",
                            explanation: "Move on without adding food.",
                            choice: .status(.incomplete),
                            identifier: "morningIntakeIncomplete"
                        )
                    } else {
                        choiceRow(
                            "Everything is logged",
                            explanation: "Continue to today’s weight.",
                            choice: .status(.confirmed),
                            identifier: "morningIntakeConfirmed"
                        )
                        Divider().overlay(LeafyTheme.hairline)
                        choiceRow(
                            "Add missing food",
                            explanation: "Add anything you missed now.",
                            choice: .logNow,
                            identifier: "morningIntakeLogNow"
                        )
                        Divider().overlay(LeafyTheme.hairline)
                        choiceRow(
                            "Continue without adding more",
                            explanation: "Move on to today’s weight.",
                            choice: .status(.incomplete),
                            identifier: "morningIntakeIncomplete"
                        )
                    }
                }
            }
        }
    }

    private var weightContent: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            WeightWheelPicker(
                selection: $weightSelection,
                unitSystem: app.draft.unitSystem,
                identifierPrefix: "checkInWeight"
            )

            Label("Water, sodium, carbohydrates, and digestion can move the scale day to day. Leafy follows the trend, not one reading.", systemImage: "drop.fill")
                .font(LeafyTypography.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Skip for today") { dismiss() }
                .font(LeafyTypography.button)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("skipMorningWeightButton")
        }
    }

    @ViewBuilder private var bottomAction: some View {
        if step == .intake {
            Button(action: submitIntake) {
                if app.isCheckInMutationInProgress {
                    HStack(spacing: LeafySpacing.small) {
                        ProgressView().tint(.white)
                        Text("Saving…")
                    }
                } else {
                    Text(selectedChoice == .logNow ? "Log yesterday’s food" : "Continue")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedChoice == nil || app.isCheckInMutationInProgress)
            .leafyDetachedBottomControl()
            .accessibilityIdentifier("continueMorningIntakeButton")
        } else {
            Button(action: submitWeight) {
                if app.isWeightMutationInProgress {
                    HStack(spacing: LeafySpacing.small) {
                        ProgressView().tint(.white)
                        Text("Saving…")
                    }
                } else {
                    Text("Log weight")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(app.isWeightMutationInProgress)
            .leafyDetachedBottomControl()
            .accessibilityIdentifier("logMorningWeightButton")
        }
    }

    private func choiceRow(
        _ title: String,
        explanation: String,
        choice: IntakeChoice,
        identifier: String
    ) -> some View {
        let selected = selectedChoice == choice
        return Button {
            selectedChoice = choice
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(alignment: .top, spacing: LeafySpacing.medium) {
                VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                    Text(title)
                        .font(LeafyTypography.headline)
                        .foregroundStyle(.primary)
                    Text(explanation)
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(LeafyTypography.title3)
                    .foregroundStyle(selected ? LeafyTheme.green : Color.secondary.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.top, 1)
            }
            .padding(.vertical, LeafySpacing.compact)
            .frame(minHeight: LeafyTheme.rowMinHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(explanation)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(LeafyTypography.subheadline)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, LeafySpacing.medium)
            .overlay(alignment: .leading) { Rectangle().fill(Color.orange).frame(width: 3) }
            .accessibilityIdentifier("morningCheckInError")
    }

    private func submitIntake() {
        guard let selectedChoice else { return }
        if selectedChoice == .logNow {
            app.beginLoggingYesterdayFromMorningCheckIn()
            return
        }
        guard case let .status(status) = selectedChoice else { return }
        Task {
            if await app.reviewYesterday(as: status) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if app.morningCheckIn?.needsWeight == true {
                    if reduceMotion { step = .weight }
                    else { withAnimation(LeafyMotion.content) { step = .weight } }
                } else {
                    dismiss()
                }
            }
        }
    }

    private var intakeTitle: String {
        app.morningCheckIn?.entries.isEmpty == false
            ? "Is yesterday’s food log complete?"
            : "Did you eat yesterday?"
    }

    private var intakeSubtitle: String {
        app.morningCheckIn?.entries.isEmpty == false
            ? "Add anything that’s missing, or continue."
            : "Choose what best describes yesterday."
    }

    private func submitWeight() {
        Task {
            if await app.saveWeightEntry(nil, weightKG: weightSelection.kilograms, recordedOn: .now) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}
