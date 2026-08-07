import SwiftUI

struct NutrientEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let input: FoodEntryInput
    @Binding var values: [String: String]
    @Binding var estimatedCodes: Set<String>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        autoFill()
                    } label: {
                        Label(app.isNutrientAutoFillLoading ? "Estimating nutrients…" : "Auto-fill with AI", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(!input.isValid || app.isNutrientAutoFillLoading)
                    if let message = app.nutrientAutoFillError {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.subheadline).foregroundStyle(.orange)
                    }
                    Text("AI values are estimates. Review them before saving; Leafy will identify them as estimated in nutrition details.")
                        .font(LeafyTypography.footnote).foregroundStyle(.secondary)
                }

                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(NutrientCatalog.items.filter { $0.group == group }) { nutrient in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(nutrient.name)
                                    if estimatedCodes.contains(nutrient.code) {
                                        Text("AI estimate").font(LeafyTypography.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                TextField("—", text: binding(for: nutrient.code))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                Text(nutrient.unit).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                                    .frame(minWidth: 34, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nutrition details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .interactiveDismissDisabled(app.isNutrientAutoFillLoading)
        }
    }

    private var groups: [String] { ["Macros", "Build toward", "Vitamins", "Minerals", "Keep within", "Additional"] }

    private func binding(for code: String) -> Binding<String> {
        Binding(
            get: { values[code] ?? "" },
            set: { newValue in values[code] = newValue; estimatedCodes.remove(code) }
        )
    }

    private func autoFill() {
        Task {
            guard let estimates = await app.autoFillNutrients(for: input) else { return }
            for estimate in estimates {
                values[estimate.code] = estimate.amount.formatted(.number.precision(.fractionLength(0...3)))
                estimatedCodes.insert(estimate.code)
            }
        }
    }
}
