import SwiftUI

struct DataPrivacyView: View {
    @Environment(AppModel.self) private var app
    @State private var browser: SafariDestination?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Text("Your data, under your control")
                        .font(LeafyTypography.title2)
                    Text("See what Leafy needs to work and review the information you have contributed.")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, LeafySpacing.compact)
            }
            .leafyBorderlessRows(separators: false)

            Section("Core data use") {
                NavigationLink {
                    CoreDataUseDetailView()
                } label: {
                    SettingsValueRow(
                        title: "App operation and personalization",
                        value: app.coreDataAccepted ? "Accepted" : "Action needed",
                        symbol: "lock.shield"
                    )
                }
            }
            .leafyBorderlessRows()

            Section("Your activity") {
                NavigationLink {
                    MyContributionsView()
                } label: {
                    SettingsValueRow(
                        title: "Product contributions",
                        value: app.catalogContributions.isEmpty ? "None" : "\(app.catalogContributions.count)",
                        symbol: "barcode"
                    )
                }

            }
            .leafyBorderlessRows()

            Section("Privacy") {
                Button("Privacy Policy") { browser = SafariDestination(url: app.configuration.privacyURL) }
            }
            .leafyBorderlessRows()
        }
        .leafyBorderlessList()
        .navigationTitle("Data & Privacy")
        .task {
            await app.loadCatalogContributions()
        }
        .sheet(item: $browser) { SafariWebView(url: $0.url).ignoresSafeArea() }
    }
}

private struct CoreDataUseDetailView: View {
    @Environment(AppModel.self) private var app
    @State private var browser: SafariDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Label(app.coreDataAccepted ? "Accepted" : "Action needed", systemImage: "checkmark.shield.fill")
                        .font(LeafyTypography.headline)
                        .foregroundStyle(LeafyTheme.green)
                    Text("Leafy stores and analyzes the information needed to calculate targets, sync your history, and personalize guidance.")
                        .font(LeafyTypography.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: LeafySpacing.medium) {
                    dataRow("Nutrition plans and preferences", icon: "target")
                    dataRow("Food logs, servings, and corrections", icon: "fork.knife")
                    dataRow("Weight history and progress", icon: "scalemass")
                }

                Text("Leafy does not sell your nutrition, food, weight, or health information.")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)

                Button("Read the Privacy Policy") { browser = SafariDestination(url: app.configuration.privacyURL) }
                    .font(LeafyTypography.headline)
            }
            .padding(LeafyTheme.pageInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LeafyTheme.canvas)
        .navigationTitle("Core data use")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $browser) { SafariWebView(url: $0.url).ignoresSafeArea() }
    }

    private func dataRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(LeafyTypography.bodyMedium)
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        Label {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(LeafyTheme.green)
        }
    }
}
