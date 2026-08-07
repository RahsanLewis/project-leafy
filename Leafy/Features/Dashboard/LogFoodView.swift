import SwiftUI

enum FoodLoggingMethod: String, CaseIterable, Identifiable {
    case search
    case ai
    case manual

    var id: Self { self }

    var label: String {
        switch self {
        case .search: "Search"
        case .ai: "AI"
        case .manual: "Manual"
        }
    }
}

struct LogFoodView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var method: FoodLoggingMethod
    let initialAIDescription: String

    init(initialMethod: FoodLoggingMethod = .search, initialAIDescription: String = "") {
        _method = State(initialValue: initialMethod)
        self.initialAIDescription = initialAIDescription
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Logging method", selection: $method) {
                    ForEach(FoodLoggingMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, LeafyTheme.pageInset)
                .padding(.vertical, LeafySpacing.small)
                .background(Color(.systemGroupedBackground))
                .accessibilityIdentifier("foodLoggingMethodPicker")

                TabView(selection: $method) {
                    ProductDiscoveryView(intent: .log, embedded: true, onLogged: dismiss.callAsFunction)
                        .tag(FoodLoggingMethod.search)

                    AIMealView(logDate: app.selectedLogDate, embedded: true, initialDescription: initialAIDescription, onSaved: dismiss.callAsFunction)
                        .tag(FoodLoggingMethod.ai)

                    FoodEntryEditorView(
                        entry: nil,
                        logDate: app.selectedLogDate,
                        embedded: true,
                        onSaved: dismiss.callAsFunction
                    )
                    .tag(FoodLoggingMethod.manual)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
