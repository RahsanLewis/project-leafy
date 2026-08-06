import SwiftUI

struct ProductDiscoveryView: View {
    @Environment(AppModel.self) private var app
    let intent: ProductDiscoveryIntent
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showingScanner = false
    @State private var selectedProduct: ProductSummary?
    @State private var detail: ProductDetail?
    @State private var scannedNotFound = false

    var body: some View {
        List {
            if query.isEmpty && !app.productHistory.isEmpty {
                Section("Recently analyzed") { productRows(app.productHistory) }
                    .leafyBorderlessRows()
            } else if query.count >= 2 {
                Section("Products") {
                    if app.isProductLoading && app.productSearchResults.isEmpty {
                        HStack { Spacer(); ProgressView("Searching USDA and Leafy…"); Spacer() }.padding()
                    } else if app.productSearchResults.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else { productRows(app.productSearchResults) }
                }
                .leafyBorderlessRows()
            } else {
                Section {
                    ContentUnavailableView(
                        "Scan or search packaged food",
                        systemImage: "barcode.viewfinder",
                        description: Text("Get a nutrition score, inspect nutrients, or add a verified serving to your food log.")
                    )
                    .listRowBackground(Color.clear)
                }
                .leafyBorderlessRows(separators: false)
            }

            if let message = app.productErrorMessage {
                Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    .leafyBorderlessRows(separators: false)
            }
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.large)
        .navigationTitle(intent == .analyze ? "Scan" : "Find Food")
        .searchable(text: $query, prompt: "Product, brand, or barcode")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingScanner = true } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
            }
            if intent == .log {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task(id: query) {
            guard query.count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await app.searchProducts(query)
        }
        .task { if intent == .analyze { await app.loadProductHistory() } }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                BarcodeScannerView { code in
                    showingScanner = false
                    Task {
                        if let product = await app.lookupProduct(barcode: code) { await open(product) }
                        else { scannedNotFound = true }
                    }
                }
                .ignoresSafeArea()
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingScanner = false } } }
            }
        }
        .navigationDestination(item: $detail) { product in
            ProductDetailView(product: product, intent: intent) {
                if intent == .log { dismiss() }
            }
        }
        .alert("Product not found", isPresented: $scannedNotFound) {
            Button("Search instead") { }
            Button("Scan again") { showingScanner = true }
        } message: {
            Text("This barcode isn’t in the USDA or Leafy catalog yet. Product label contribution is coming next.")
        }
    }

    @ViewBuilder private func productRows(_ products: [ProductSummary]) -> some View {
        ForEach(products) { product in
            Button { Task { await open(product) } } label: {
                HStack(spacing: 14) {
                    ScoreBadge(score: product.score?.score, label: product.score?.label)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name.capitalized).font(LeafyTypography.headline).foregroundStyle(.primary).lineLimit(2)
                        Text([product.brand, product.servingSize.map { "\($0.formatted()) \(product.servingUnit ?? "g")" }].compactMap { $0 }.joined(separator: " • "))
                            .font(LeafyTypography.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
        }
    }

    private func open(_ product: ProductSummary) async {
        selectedProduct = product
        detail = await app.loadProductDetail(product)
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
