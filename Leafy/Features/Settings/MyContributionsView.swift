import SwiftUI

struct MyContributionsView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedProduct: ProductDetail?

    var body: some View {
        List {
            if app.catalogContributions.isEmpty && !app.isCatalogContributionLoading {
                ContentUnavailableView(
                    "No product contributions",
                    systemImage: "barcode.viewfinder",
                    description: Text("When a barcode is missing, scan its label to help build Leafy’s food catalog.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(app.catalogContributions) { contribution in
                        row(for: contribution)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if contribution.status.isEditable {
                                    Button("Delete", role: .destructive) { Task { _ = await app.deleteCatalogContribution(id: contribution.id) } }
                                }
                            }
                    }
                }
                .leafyBorderlessRows()
            }
            if let error = app.catalogContributionErrorMessage {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    .leafyBorderlessRows(separators: false)
            }
        }
        .leafyBorderlessList()
        .navigationTitle("My Contributions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.loadCatalogContributions() }
        .refreshable { await app.loadCatalogContributions() }
        .overlay { if app.isCatalogContributionLoading && app.catalogContributions.isEmpty { ProgressView() } }
        .navigationDestination(item: $selectedProduct) { product in
            ProductDetailView(product: product, intent: .analyze, onLogged: {})
        }
    }

    @ViewBuilder private func row(for contribution: CatalogContribution) -> some View {
        if contribution.status.isEditable {
            NavigationLink {
                CatalogContributionView(barcode: contribution.gtin, intent: .analyze, onCompleted: nil)
            } label: { contributionLabel(contribution) }
        } else if contribution.status == .accepted, let foodVersionID = contribution.acceptedFoodVersionID {
            Button { Task { selectedProduct = await app.loadProductDetail(foodVersionID: foodVersionID) } } label: {
                HStack { contributionLabel(contribution); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
            }.buttonStyle(.plain)
        } else {
            NavigationLink { ContributionStatusView(contribution: contribution) } label: { contributionLabel(contribution) }
        }
    }

    private func contributionLabel(_ contribution: CatalogContribution) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(contribution.displayName.capitalized).font(LeafyTypography.headline).foregroundStyle(.primary)
                Spacer()
                Text(contribution.status.title).font(LeafyTypography.captionSemibold).foregroundStyle(statusColor(contribution.status))
            }
            Text("\(contribution.gtin) • Updated \(contribution.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(LeafyTypography.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }

    private func statusColor(_ status: CatalogContributionStatus) -> Color {
        switch status {
        case .accepted: LeafyTheme.green
        case .needsReview, .rejected: .orange
        case .draft, .pendingReview: .secondary
        }
    }
}

private struct ContributionStatusView: View {
    let contribution: CatalogContribution
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: contribution.status == .rejected ? "xmark.circle" : "clock.badge.checkmark")
                .font(.system(size: 48)).foregroundStyle(contribution.status == .rejected ? .orange : LeafyTheme.green)
            Text(contribution.status.title).font(LeafyTypography.title)
            Text(contribution.reviewReason ?? "Leafy is checking the submitted label before making it available to everyone.")
                .font(LeafyTypography.body).foregroundStyle(.secondary)
            Divider()
            LabeledContent("Product", value: contribution.displayName.capitalized)
            LabeledContent("Barcode", value: contribution.gtin)
            LabeledContent("Revision", value: String(contribution.revision))
            Spacer()
            Text("Private label photos are used only as verification evidence.")
                .font(LeafyTypography.footnote).foregroundStyle(.secondary)
        }
        .padding(LeafyTheme.pageInset)
        .navigationTitle("Contribution")
        .navigationBarTitleDisplayMode(.inline)
    }
}
