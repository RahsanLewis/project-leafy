import SwiftUI

struct DataContributionView: View {
    @Environment(AppModel.self) private var app
    @State private var countryCode = Locale.current.region?.identifier ?? "US"
    @State private var regionCode = ""
    @State private var confirmLeaving = false

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusTitle).font(LeafyTypography.headline)
                        Text(statusDetail).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: app.dataContributionStatus?.isParticipating == true ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(LeafyTheme.green)
                }
            }
            .leafyBorderlessRows(separators: false)

            Section("What may be included") {
                dataRow("Food and calorie logs", icon: "fork.knife")
                dataRow("Weights recorded in Leafy", icon: "scalemass")
                dataRow("Serving details and corrections", icon: "checkmark.bubble")
                dataRow("Screened meal-photo crops", icon: "photo")
            }
            .leafyBorderlessRows()

            Section("What is never included") {
                dataRow("Your email or account identifiers", icon: "person.crop.circle.badge.xmark")
                dataRow("Original meal photos", icon: "photo.badge.exclamationmark")
                dataRow("HealthKit or Health Connect data", icon: "heart.slash")
            }
            .leafyBorderlessRows()

            Section("How access works") {
                Text("Leafy may let lawful organizations analyze coded row-level records for a declared purpose inside a controlled data environment. Partners do not receive unrestricted production-database access or original photos. Leafy may be paid for this access.")
                Text("Joining is optional. It does not change your Leafy features or recommendations, and you may leave at any time to stop future access.")
                    .foregroundStyle(.secondary)
            }
            .leafyBorderlessRows()

            if app.dataContributionStatus?.isParticipating != true {
                Section("Your jurisdiction") {
                    TextField("Country code", text: $countryCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("State or region code (optional)", text: $regionCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Text("Leafy uses this only to apply the consent and buyer-authorization rules that protect you.")
                        .font(LeafyTypography.footnote)
                        .foregroundStyle(.secondary)
                }
                .leafyBorderlessRows()
            }

            Section {
                if app.dataContributionStatus?.isParticipating == true {
                    Button("Leave data program", role: .destructive) { confirmLeaving = true }
                } else {
                    Button("Join data program") {
                        Task {
                            _ = await app.joinDataContribution(
                                countryCode: countryCode,
                                regionCode: regionCode.isEmpty ? nil : regionCode
                            )
                        }
                    }
                    .disabled(countryCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 2)
                }
            } footer: {
                Text("This authorization covers participation in Leafy’s data program. If your jurisdiction requires authorization for a specific buyer, Leafy must ask separately before that buyer can access your records.")
            }
            .leafyBorderlessRows(separators: false)

            if let error = app.dataContributionErrorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .leafyBorderlessRows(separators: false)
            }
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.large)
        .navigationTitle("Data program")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if app.isDataContributionLoading { ProgressView().controlSize(.large) } }
        .task { await app.loadDataContributionStatus() }
        .confirmationDialog("Leave the nutrition data program?", isPresented: $confirmLeaving, titleVisibility: .visible) {
            Button("Leave program", role: .destructive) { Task { await app.leaveDataContribution() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your records will be removed from future commercial access. Your private Leafy history will remain unless you delete it separately.")
        }
    }

    private var statusTitle: String {
        app.dataContributionStatus?.isParticipating == true ? "You’re contributing" : "Participation is off"
    }

    private var statusDetail: String {
        app.dataContributionStatus?.isParticipating == true
            ? "New eligible records can support nutrition research and commercial analysis."
            : "Your records are used only to operate and personalize Leafy."
    }

    private func dataRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
    }
}
