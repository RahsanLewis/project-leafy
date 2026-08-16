import SwiftUI

struct NutrientEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let input: FoodEntryInput
    @Binding var values: [String: String]
    @Binding var estimatedCodes: Set<String>
    let loggingContext: Bool
    @State private var expandedGroups: Set<NutritionGroup> = [.macros]
    @FocusState private var focusedCode: String?

    init(
        input: FoodEntryInput,
        values: Binding<[String: String]>,
        estimatedCodes: Binding<Set<String>>,
        loggingContext: Bool = false
    ) {
        self.input = input
        _values = values
        _estimatedCodes = estimatedCodes
        self.loggingContext = loggingContext
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                    autoFillSection
                    ForEach(groups, id: \.self) { group in
                        nutrientGroup(group)
                    }
                }
                .padding(.horizontal, LeafyTheme.pageInset)
                .padding(.top, LeafySpacing.medium)
                .padding(.bottom, LeafySpacing.xxLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LeafyTheme.canvas)
            .navigationTitle("Nutrition details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedCode = nil }
                }
            }
            .interactiveDismissDisabled(app.isNutrientAutoFillLoading)
        }
    }

    private var autoFillSection: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Button(action: autoFill) {
                Label(
                    app.isNutrientAutoFillLoading ? "Estimating nutrients…" : "Auto-fill with AI",
                    systemImage: "sparkles"
                )
                .font(LeafyTypography.headline)
                .foregroundStyle(LeafyTheme.green)
                .frame(minHeight: LeafyTheme.minimumTouchTarget)
            }
            .disabled(!input.isValid || app.isNutrientAutoFillLoading)

            Text("Review estimated values before saving. You can replace any estimate by typing your own value.")
                .font(LeafyTypography.footnote)
                .foregroundStyle(.secondary)
            if let message = app.nutrientAutoFillError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func nutrientGroup(_ group: NutritionGroup) -> some View {
        let items = NutrientCatalog.items.filter { $0.group == group }
        return DisclosureGroup(isExpanded: binding(for: group)) {
            VStack(spacing: 0) {
                ForEach(items) { nutrient in
                    nutrientRow(nutrient)
                    if nutrient.id != items.last?.id { Divider().overlay(LeafyTheme.hairline) }
                }
            }
            .padding(.top, LeafySpacing.small)
        } label: {
            HStack {
                Text(group.title).font(LeafyTypography.title3)
                Spacer()
                if let count = enteredCount(in: items), count > 0 {
                    Text("\(count) added")
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: LeafyTheme.minimumTouchTarget)
        }
        .tint(LeafyTheme.green)
    }

    private func nutrientRow(_ nutrient: NutrientCatalog.Item) -> some View {
        HStack(spacing: LeafySpacing.compact) {
            HStack(spacing: LeafySpacing.small) {
                Text(nutrient.name)
                    .font(LeafyTypography.body)
                if estimatedCodes.contains(nutrient.code) {
                    Image(systemName: "sparkles")
                        .font(LeafyTypography.icon(12))
                        .foregroundStyle(LeafyTheme.green)
                        .accessibilityLabel("AI estimated")
                }
            }
            Spacer(minLength: LeafySpacing.small)
            TextField("—", text: valueBinding(for: nutrient.code))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(LeafyTypography.bodyMedium)
                .focused($focusedCode, equals: nutrient.code)
                .frame(width: 90)
                .accessibilityLabel(nutrient.name)
            Text(nutrient.unit)
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 42, alignment: .leading)
        }
        .frame(minHeight: LeafyTheme.rowMinHeight)
    }

    private var groups: [NutritionGroup] { NutritionGroup.detailOrder }
    private func binding(for group: NutritionGroup) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(group) },
            set: { expanded in
                withAnimation(LeafyMotion.state) {
                    if expanded { expandedGroups.insert(group) } else { expandedGroups.remove(group) }
                }
            }
        )
    }
    private func enteredCount(in items: [NutrientCatalog.Item]) -> Int? {
        items.filter { !(values[$0.code] ?? "").isEmpty }.count
    }
    private func valueBinding(for code: String) -> Binding<String> {
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
            expandedGroups.insert(.macros)
        }
    }
}
