import SwiftUI

struct WeightEntryEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let entry: WeightEntry?
    @State private var whole: Int
    @State private var tenth: Int
    @State private var date: Date

    init(entry: WeightEntry?) {
        self.entry = entry
        let imperial = entry.map { $0.weightKG * 2.20462 } ?? 170
        _whole = State(initialValue: Int(imperial))
        _tenth = State(initialValue: Int((imperial * 10).rounded()) % 10)
        _date = State(initialValue: entry?.recordedOn ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack(spacing: 0) {
                        Picker("Whole", selection: $whole) {
                            ForEach(wholeRange, id: \.self) { Text("\($0)").tag($0) }
                        }.pickerStyle(.wheel)
                        Picker("Decimal", selection: $tenth) {
                            ForEach(0...9, id: \.self) { Text(".\($0)").tag($0) }
                        }.pickerStyle(.wheel).frame(width: 90)
                        Text(unitLabel).font(.title3).foregroundStyle(.secondary).padding(.trailing)
                    }.frame(height: 150)
                }
                Section("Date") {
                    DatePicker("Weigh-in date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                if let error = app.weightErrorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
            }
            .navigationTitle(entry == nil ? "Log Weight" : "Edit Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button(entry == nil ? "Add Weight" : "Save Changes") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(app.isWeightMutationInProgress)
                    .padding(20).background(.regularMaterial)
            }
            .interactiveDismissDisabled(app.isWeightMutationInProgress)
            .overlay { if app.isWeightMutationInProgress { ProgressView().padding(18).background(.regularMaterial, in: .rect(cornerRadius: 14)) } }
        }
        .onAppear {
            let kg = entry?.weightKG ?? app.draft.currentWeightKG
            let value = app.draft.unitSystem == .imperial ? kg * 2.20462 : kg
            whole = Int(value); tenth = Int((value * 10).rounded()) % 10
        }
    }

    private var wholeRange: ClosedRange<Int> { app.draft.unitSystem == .imperial ? 77...772 : 35...350 }
    private var unitLabel: String { app.draft.unitSystem == .imperial ? "lb" : "kg" }
    private var displayWeight: Double { Double(whole) + Double(tenth) / 10 }
    private var weightKG: Double { app.draft.unitSystem == .imperial ? displayWeight / 2.20462 : displayWeight }
    private func save() {
        Task { if await app.saveWeightEntry(entry, weightKG: weightKG, recordedOn: date) { dismiss() } }
    }
}
