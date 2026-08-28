import SwiftUI
import UIKit

struct WeightWheelSelection: Equatable, Sendable {
    var kilograms: Double

    init(kilograms: Double) {
        self.kilograms = kilograms
    }

    func displayValue(in unitSystem: UnitSystem) -> Double {
        unitSystem == .imperial ? kilograms * 2.2046226218 : kilograms
    }

    func whole(in unitSystem: UnitSystem) -> Int {
        Int(displayValue(in: unitSystem))
    }

    func tenth(in unitSystem: UnitSystem) -> Int {
        Int((displayValue(in: unitSystem) * 10).rounded()) % 10
    }

    mutating func setWhole(_ whole: Int, unitSystem: UnitSystem) {
        setDisplayValue(Double(whole) + Double(tenth(in: unitSystem)) / 10, unitSystem: unitSystem)
    }

    mutating func setTenth(_ tenth: Int, unitSystem: UnitSystem) {
        setDisplayValue(Double(whole(in: unitSystem)) + Double(tenth) / 10, unitSystem: unitSystem)
    }

    private mutating func setDisplayValue(_ value: Double, unitSystem: UnitSystem) {
        kilograms = unitSystem == .imperial ? value / 2.2046226218 : value
    }
}

struct WeightWheelPicker: View {
    @Binding var selection: WeightWheelSelection
    let unitSystem: UnitSystem
    var identifierPrefix = "weight"

    private var wholeRange: ClosedRange<Int> {
        unitSystem == .imperial ? 77...772 : 35...350
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Whole weight", selection: Binding(
                get: { selection.whole(in: unitSystem) },
                set: { selection.setWhole($0, unitSystem: unitSystem) }
            )) {
                ForEach(wholeRange, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier("\(identifierPrefix)WholePicker")

            Text(".")
                .font(LeafyTypography.title2)

            Picker("Decimal weight", selection: Binding(
                get: { selection.tenth(in: unitSystem) },
                set: { selection.setTenth($0, unitSystem: unitSystem) }
            )) {
                ForEach(0...9, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(width: 92)
            .accessibilityIdentifier("\(identifierPrefix)DecimalPicker")

            Text(unitSystem == .imperial ? "lb" : "kg")
                .font(LeafyTypography.title3)
                .foregroundStyle(.secondary)
                .padding(.trailing, LeafySpacing.medium)
        }
        .frame(height: 190)
        .accessibilityElement(children: .contain)
    }
}

struct WeightEntryEditorView: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(\.dismiss) private var dismiss
    let entry: WeightEntry?
    @State private var selection: WeightWheelSelection
    @State private var date: Date
    @State private var baselineSelection: WeightWheelSelection
    @State private var baselineDate: Date
    @State private var showingDiscardConfirmation = false
    @State private var didInitialize = false

    init(entry: WeightEntry?) {
        self.entry = entry
        let weight = entry?.weightKG ?? 77
        let recordedOn = entry?.recordedOn ?? .now
        let initial = WeightWheelSelection(kilograms: weight)
        _selection = State(initialValue: initial)
        _baselineSelection = State(initialValue: initial)
        _date = State(initialValue: recordedOn)
        _baselineDate = State(initialValue: recordedOn)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        Text(entry == nil ? "Log your weight" : "Edit weight")
                            .font(LeafyTypography.largeTitle)
                        Text(entry == nil
                             ? "A consistent scale reading helps Leafy follow your longer-term trend."
                             : "Adjust the reading or the day it was recorded.")
                            .font(LeafyTypography.body)
                            .foregroundStyle(.secondary)
                    }

                    WeightWheelPicker(
                        selection: $selection,
                        unitSystem: app.draft.unitSystem,
                        identifierPrefix: "entryWeight"
                    )

                    VStack(spacing: 0) {
                        HStack {
                            Text("Weigh-in date").font(LeafyTypography.body)
                            Spacer()
                            DatePicker(
                                "Weigh-in date",
                                selection: $date,
                                in: ...Date.now,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .accessibilityIdentifier("weightEntryDate")
                        }
                        .frame(minHeight: LeafyTheme.rowMinHeight)
                        Rectangle().fill(LeafyTheme.hairline).frame(height: 1)
                    }

                    if let error = app.weightErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, LeafySpacing.medium)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color.orange).frame(width: 3)
                            }
                            .accessibilityIdentifier("weightEntryError")
                    }

                    Text("Daily changes from water, sodium, and carbohydrates are normal. Leafy uses your trend—not one reading.")
                        .font(LeafyTypography.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(LeafyTheme.pageInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LeafyTheme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    if app.isWeightMutationInProgress {
                        HStack(spacing: LeafySpacing.small) {
                            ProgressView().tint(.white)
                            Text(entry == nil ? "Adding…" : "Saving…")
                        }
                    } else {
                        Text(entry == nil ? "Add Weight" : "Save Changes")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(app.isWeightMutationInProgress)
                .leafyDetachedBottomControl()
                .accessibilityIdentifier("saveWeightEntryButton")
            }
        }
        .interactiveDismissDisabled(app.isWeightMutationInProgress || isDirty)
        .sheet(isPresented: $showingDiscardConfirmation) {
            LeafyConfirmationSheet(
                title: "Discard your changes?",
                message: "Your edited weight or date hasn’t been saved.",
                confirmTitle: "Discard Changes",
                isDestructive: true,
                confirmIdentifier: "confirmDiscardWeightChangesButton",
                cancelTitle: "Keep Editing",
                sheetIdentifier: "discardWeightChangesConfirmationSheet"
            ) { dismiss() }
        }
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            let kilograms = entry?.weightKG ?? app.weightEntries.first?.weightKG ?? app.draft.currentWeightKG
            selection = WeightWheelSelection(kilograms: kilograms)
            baselineSelection = selection
            baselineDate = date
            app.weightErrorMessage = nil
        }
    }

    private var isDirty: Bool {
        abs(selection.kilograms - baselineSelection.kilograms) > 0.01 ||
            !Calendar.current.isDate(date, inSameDayAs: baselineDate)
    }

    private func cancel() {
        if isDirty { showingDiscardConfirmation = true }
        else { dismiss() }
    }

    private func save() {
        Task {
            if await app.saveWeightEntry(entry, weightKG: selection.kilograms, recordedOn: date) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}
