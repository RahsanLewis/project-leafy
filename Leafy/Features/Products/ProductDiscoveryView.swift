import SwiftUI
import UIKit

struct ProductDiscoveryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let intent: ProductDiscoveryIntent
    let embedded: Bool
    let onLogged: (() -> Void)?
    @Binding private var hasUnsavedDraft: Bool
    @State private var query = ""
    @State private var isSearchPresented = false
    @State private var showingScanner = false
    @State private var detail: ProductDetail?
    @State private var unknownBarcode: String?
    @State private var showingUnknownProduct = false
    @State private var showingContribution = false
    @State private var openContributionAfterUnknownProduct = false
    @State private var reopenScannerAfterUnknownProduct = false
    @State private var scannerStatus: BarcodeScannerStatus = .requestingPermission
    @Environment(\.openURL) private var openURL

    init(intent: ProductDiscoveryIntent, embedded: Bool = false, onLogged: (() -> Void)? = nil, hasUnsavedDraft: Binding<Bool> = .constant(false)) {
        self.intent = intent
        self.embedded = embedded
        self.onLogged = onLogged
        _hasUnsavedDraft = hasUnsavedDraft
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isSearchPresented || !query.isEmpty { searchContent }
                else { scanLanding }
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.bottom, LeafySpacing.xxLarge)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LeafyTheme.canvas)
        .navigationTitle(embedded ? "Log Food" : "Scan")
        .searchable(text: $query, isPresented: $isSearchPresented, prompt: "Product, brand, or barcode")
        .toolbar {
            if intent == .log && !embedded {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task(id: query) {
            guard query.count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await app.searchProducts(query)
        }
        .task { await app.loadProductHistory() }
        .sheet(isPresented: $showingScanner) { scannerSheet }
        .sheet(isPresented: $showingUnknownProduct, onDismiss: finishUnknownProductSheet) {
            if let unknownBarcode {
                UnknownProductSheet(
                    barcode: unknownBarcode,
                    addProduct: {
                        openContributionAfterUnknownProduct = true
                        showingUnknownProduct = false
                    },
                    scanAnother: {
                        reopenScannerAfterUnknownProduct = true
                        showingUnknownProduct = false
                    }
                )
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
                .presentationBackground(LeafyTheme.canvas)
            }
        }
        .navigationDestination(item: $detail) { product in
            ProductDetailView(product: product, intent: intent, logDate: app.selectedLogDate) { completeLog() }
        }
        .navigationDestination(isPresented: $showingContribution) {
            if let unknownBarcode {
                CatalogContributionView(barcode: unknownBarcode, intent: intent, onCompleted: { completeLog() }, hasUnsavedDraft: $hasUnsavedDraft)
            }
        }
    }

    private var scanLanding: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Image(systemName: "barcode.viewfinder")
                    .font(LeafyTypography.icon(36))
                    .foregroundStyle(LeafyTheme.green)
                Text("Scan a packaged food")
                    .font(LeafyTypography.title2)
                Text("Point your camera at the barcode to find its nutrition, ingredients, and Leafy score.")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { showingScanner = true } label: {
                Label("Scan Barcode", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("scanBarcodeButton")
        }
        .padding(.top, LeafySpacing.xLarge)
        .frame(maxWidth: 520, alignment: .leading)
    }

    @ViewBuilder private var searchContent: some View {
        if query.isEmpty {
            if !app.productHistory.isEmpty {
                sectionTitle("Recently viewed")
                productRows(app.productHistory)
            } else if !app.isProductLoading {
                emptySearchState
            }
        } else if query.count >= 2 {
            sectionTitle("Results")
            if app.isProductLoading && app.productSearchResults.isEmpty {
                searchLoading
            } else if app.productSearchResults.isEmpty && app.productErrorMessage == nil {
                ContentUnavailableView.search(text: query).padding(.top, LeafySpacing.large)
            } else {
                productRows(app.productSearchResults)
            }
        } else {
            Text("Enter at least two characters")
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, LeafySpacing.medium)
        }

        if let message = app.productErrorMessage {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.orange)
                Button("Try Again") { Task { await app.searchProducts(query) } }
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
            }
            .padding(.top, LeafySpacing.large)
        }
    }

    private var searchLoading: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            ForEach(0..<3, id: \.self) { _ in
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(.secondary.opacity(0.15)).frame(width: 190, height: 16)
                        Capsule().fill(.secondary.opacity(0.1)).frame(width: 130, height: 12)
                    }
                    Spacer()
                    Circle().fill(.secondary.opacity(0.1)).frame(width: 38, height: 38)
                }
                .frame(minHeight: 64)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Searching products")
    }

    @ViewBuilder private func productRows(_ products: [ProductSummary]) -> some View {
        ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
            Button { Task { await open(product) } } label: {
                HStack(spacing: LeafySpacing.compact) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name.capitalized)
                            .font(LeafyTypography.headline).foregroundStyle(.primary).lineLimit(2)
                        Text(productMetadata(product))
                            .font(LeafyTypography.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: LeafySpacing.compact)
                    if let score = product.score, score.isAvailable {
                        scoreView(score.score)
                    }
                    Image(systemName: "chevron.right").font(LeafyTypography.caption).foregroundStyle(.tertiary)
                }
                .frame(minHeight: 68)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if index < products.count - 1 { Divider().overlay(LeafyTheme.hairline) }
        }
    }

    private func scoreView(_ score: Int?) -> some View {
        VStack(spacing: 1) {
            Text(score.map(String.init) ?? "—")
                .font(LeafyTypography.headline)
                .foregroundStyle(score.map(scoreColor) ?? .secondary)
            Text("Leafy Score")
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Leafy Score \($0) out of 100" } ?? "Leafy Score unavailable")
    }

    private var emptySearchState: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            Text("Search packaged foods")
                .font(LeafyTypography.title2)
            Text("Look up a product or brand, or enter the numbers beneath its barcode.")
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, LeafySpacing.xLarge)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var scannerSheet: some View {
        NavigationStack {
            BarcodeScannerView(onCode: handleScannedCode, onStatusChange: { scannerStatus = $0 })
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingScanner = false } }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: LeafySpacing.xSmall) {
                        if scannerStatus == .denied {
                            Button("Open Settings") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                openURL(url)
                            }
                            .font(LeafyTypography.subheadlineSemibold)
                            .foregroundStyle(.white)
                            .frame(minHeight: 44)
                        }
                        Button("Search Instead") {
                            showingScanner = false
                            presentSearch()
                        }
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, LeafyTheme.pageInset)
                }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(LeafyTypography.captionSemibold).foregroundStyle(.secondary).tracking(0.6)
            .padding(.top, LeafySpacing.medium).padding(.bottom, LeafySpacing.small)
    }

    private func presentSearch() {
        Task { @MainActor in isSearchPresented = true }
    }

    private func handleScannedCode(_ code: String) {
        showingScanner = false
        Task {
            if let product = await app.lookupProduct(barcode: code) { await open(product) }
            else if app.productErrorMessage == nil {
                unknownBarcode = code
                showingUnknownProduct = true
            }
        }
    }

    private func finishUnknownProductSheet() {
        if openContributionAfterUnknownProduct {
            openContributionAfterUnknownProduct = false
            showingContribution = true
        } else if reopenScannerAfterUnknownProduct {
            reopenScannerAfterUnknownProduct = false
            unknownBarcode = nil
            showingScanner = true
        } else if !showingContribution {
            unknownBarcode = nil
        }
    }

    private func productMetadata(_ product: ProductSummary) -> String {
        var parts = [product.brand].compactMap { $0 }
        if let serving = product.servingSize { parts.append("\(serving.formatted()) \(product.servingUnit ?? "g")") }
        if let calories = product.caloriesPer100G { parts.append("\(Int(calories.rounded())) Cal / 100 g") }
        return parts.joined(separator: " • ")
    }

    private func scoreColor(_ score: Int) -> Color { score >= 60 ? LeafyTheme.green : score >= 40 ? .orange : .red }

    private func completeLog() {
        detail = nil; showingContribution = false; hasUnsavedDraft = false
        if let onLogged { onLogged() } else if intent == .log { dismiss() }
    }

    private func open(_ product: ProductSummary) async { detail = await app.loadProductDetail(product) }
}

private struct UnknownProductSheet: View {
    let barcode: String
    let addProduct: () -> Void
    let scanAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            Image(systemName: "barcode.viewfinder")
                .font(LeafyTypography.icon(34))
                .foregroundStyle(LeafyTheme.green)

            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("We couldn’t find this product")
                    .font(LeafyTypography.title2)
                Text("Add the package to help Leafy recognize it next time.")
                    .font(LeafyTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Barcode \(barcode)")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            VStack(spacing: LeafySpacing.small) {
                Button("Add product", action: addProduct)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("addUnknownProductButton")
                Button("Scan another", action: scanAnother)
                    .font(LeafyTypography.button)
                    .foregroundStyle(LeafyTheme.green)
                    .frame(maxWidth: .infinity, minHeight: LeafyTheme.minimumTouchTarget)
                    .accessibilityIdentifier("scanAnotherUnknownProductButton")
            }
        }
        .padding(.horizontal, LeafyTheme.pageInset)
        .padding(.top, LeafySpacing.small)
        .padding(.bottom, LeafySpacing.medium)
        .accessibilityIdentifier("unknownProductSheet")
    }
}

struct ScoreBadge: View {
    let score: Int?
    let label: String?
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.14)).frame(width: 52, height: 52)
            Text(score.map(String.init) ?? "—").font(LeafyTypography.headline).foregroundStyle(color)
        }
        .accessibilityLabel(score.map { "Nutrition score \($0) out of 100" } ?? "Nutrition score unavailable")
    }
    private var color: Color {
        guard let score else { return .secondary }
        return score >= 60 ? LeafyTheme.green : score >= 40 ? .orange : .red
    }
}
