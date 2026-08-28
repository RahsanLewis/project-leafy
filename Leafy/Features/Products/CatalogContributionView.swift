import PhotosUI
import SwiftUI
import UIKit

private enum CatalogContributionStep { case capture, submitted }
private enum CatalogPhotoTarget: String, Identifiable, CaseIterable {
    case front
    case backLabel = "back_label"

    var id: String { rawValue }
    var title: String { self == .front ? "Package front" : "Nutrition Facts and ingredients" }
    var instruction: String {
        self == .front
            ? "Show the full product name and brand"
            : "Keep the Nutrition Facts and complete ingredients list readable"
    }
}

struct CatalogContributionWaitEstimator {
    private static let key = "leafy.catalogContribution.wait"

    static func estimatedSeconds(defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.double(forKey: key)
        return clamp(stored > 0 ? stored : 25)
    }

    static func record(_ duration: TimeInterval, defaults: UserDefaults = .standard) {
        guard duration.isFinite, duration > 0 else { return }
        let previous = estimatedSeconds(defaults: defaults)
        defaults.set(clamp(previous * 0.7 + duration * 0.3), forKey: key)
    }

    private static func clamp(_ value: Double) -> Double { min(60, max(8, value)) }
}

struct CatalogContributionView: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(\.dismiss) private var dismiss
    let barcode: String
    let intent: ProductDiscoveryIntent
    let onCompleted: (() -> Void)?
    let refreshExisting: Bool
    @Binding private var hasUnsavedDraft: Bool

    @AppStorage("leafy.catalogContributionDisclosure.v1") private var acceptedDisclosure = false
    @State private var contribution: CatalogContribution?
    @State private var step: CatalogContributionStep = .capture
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var cameraTarget: CatalogPhotoTarget?
    @State private var photos: [CatalogPhotoTarget: Data] = [:]
    @State private var previews: [CatalogPhotoTarget: UIImage] = [:]
    @State private var acceptedDetail: ProductDetail?
    @State private var servingCount = "1"
    @State private var consumedAt = Date()
    @State private var mealType: MealType = .unspecified
    @State private var showingDisclosure = false
    @State private var showingUploadWait = false
    @State private var uploadTask: Task<Void, Never>?

    init(
        barcode: String,
        intent: ProductDiscoveryIntent,
        onCompleted: (() -> Void)?,
        refreshExisting: Bool = false,
        hasUnsavedDraft: Binding<Bool> = .constant(false)
    ) {
        self.barcode = barcode
        self.intent = intent
        self.onCompleted = onCompleted
        self.refreshExisting = refreshExisting
        _hasUnsavedDraft = hasUnsavedDraft
    }

    var body: some View {
        Group {
            if contribution == nil && acceptedDetail == nil {
                ProgressView("Preparing product…")
            } else if step == .submitted {
                submittedView
            } else {
                captureView
            }
        }
        .background(LeafyTheme.canvas)
        .navigationTitle("Add Product")
        .navigationBarTitleDisplayMode(.inline)
        .task { await start() }
        .onChange(of: frontItem) { _, item in Task { await load(item, target: .front) } }
        .onChange(of: backItem) { _, item in Task { await load(item, target: .backLabel) } }
        .sheet(item: $cameraTarget) { target in
            MealCameraPicker { image in save(image, target: target) }
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingUploadWait) {
            LeafyAnalysisLoadingView(
                title: "Leafy is sending the package",
                facts: Self.packageFacts,
                startedAt: .now,
                estimatedSeconds: 12,
                loadingAccessibilityIdentifier: "catalogUploadLoadingScreen",
                cancelAccessibilityIdentifier: "cancelCatalogUploadButton",
                onCancel: cancelUpload
            )
        }
        .alert("Help improve Leafy", isPresented: $showingDisclosure) {
            Button("Continue") {
                acceptedDisclosure = true
                beginSubmission()
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Leafy uses the structured facts read from these private package photos to identify this product and improve its shared food catalog. The photos are not shown publicly.")
        }
        .navigationDestination(item: $acceptedDetail) { product in
            ProductDetailView(product: product, intent: intent, logDate: app.selectedLogDate, onLogged: { onCompleted?() })
        }
        .alert("Couldn’t add product", isPresented: Binding(
            get: { app.catalogContributionErrorMessage != nil },
            set: { if !$0 { app.catalogContributionErrorMessage = nil } }
        )) { Button("OK") {} } message: { Text(app.catalogContributionErrorMessage ?? "") }
    }

    private static let packageFacts = [
        "Leafy checks the barcode against trusted product sources.",
        "The package label remains the source for nutrition and ingredients.",
        "Clear photos help Leafy read small values accurately.",
        "You can leave after the photos finish uploading.",
    ]

    private var captureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Text(isRetake ? "One clearer photo" : "Photograph the package")
                        .font(LeafyTypography.title2)
                    Text(retakeMessage ?? "Take a photo of the front and back. Leafy will identify the product and read the label for you.")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Barcode \(barcode)")
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.secondary)
                }

                if shouldShow(.front) { photoSlot(.front, item: $frontItem) }
                if shouldShow(.backLabel) { photoSlot(.backLabel, item: $backItem) }

                Label("Package photos stay private and are used as verification evidence.", systemImage: "lock.shield")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)

                if intent == .log {
                    VStack(alignment: .leading, spacing: LeafySpacing.medium) {
                        Text("Add to food log").font(LeafyTypography.headline)
                        servingEditor
                        DatePicker("Time", selection: $consumedAt, displayedComponents: .hourAndMinute)
                            .frame(minHeight: LeafyTheme.rowMinHeight)
                        Picker("Meal", selection: $mealType) {
                            ForEach(MealType.allCases) { Text($0.label).tag($0) }
                        }
                        .frame(minHeight: LeafyTheme.rowMinHeight)
                    }
                }
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.vertical, LeafySpacing.medium)
            .padding(.bottom, 112)
        }
        .safeAreaInset(edge: .bottom) {
            Button(intent == .log ? "Add and Log When Ready" : "Add Product") {
                if acceptedDisclosure { beginSubmission() } else { showingDisclosure = true }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!readyToSubmit || app.isCatalogContributionLoading)
            .opacity(readyToSubmit ? 1 : 0.45)
            .leafyDetachedBottomControl()
            .accessibilityIdentifier("submitAutomatedProductButton")
        }
    }

    private func photoSlot(_ target: CatalogPhotoTarget, item: Binding<PhotosPickerItem?>) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                    Text(target.title).font(LeafyTypography.headline)
                    Text(target.instruction).font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: hasPhoto(target) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(hasPhoto(target) ? LeafyTheme.green : Color.secondary.opacity(0.5))
            }
            if let image = previews[target] {
                Image(uiImage: image)
                    .resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 170)
                    .clipShape(.rect(cornerRadius: LeafyRadius.control))
            }
            HStack(spacing: LeafySpacing.small) {
                Button { cameraTarget = target } label: {
                    Label(hasPhoto(target) ? "Retake" : "Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity, minHeight: LeafyTheme.minimumTouchTarget)
                }
                PhotosPicker(selection: item, matching: .images) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: LeafyTheme.minimumTouchTarget)
                }
            }
            .font(LeafyTypography.subheadlineSemibold)
            .foregroundStyle(LeafyTheme.green)
        }
    }

    private var servingEditor: some View {
        HStack {
            Text("How many servings did you eat?")
            Spacer()
            Button { adjustServing(-ProductServingQuantity.step) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            TextField("1", text: $servingCount)
                .keyboardType(.decimalPad).multilineTextAlignment(.center)
                .font(LeafyTypography.headline).frame(width: 56)
            Button { adjustServing(ProductServingQuantity.step) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(LeafyTheme.green)
        .frame(minHeight: LeafyTheme.rowMinHeight)
    }

    private var submittedView: some View {
        VStack(spacing: LeafySpacing.large) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58)).foregroundStyle(LeafyTheme.green)
            Text("Leafy is identifying it").font(LeafyTypography.title2)
            Text(intent == .log
                 ? "Added to your food log. Leafy is reading the label now, and nutrition will appear when it’s ready."
                 : "Leafy will verify the package and add it to the catalog when it is ready.")
                .font(LeafyTypography.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") {
                hasUnsavedDraft = false
                onCompleted?()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(LeafyTheme.pageInset)
    }

    private var isRetake: Bool { contribution?.status == .needsReview }
    private var retakeMessage: String? { isRetake ? contribution?.reviewReason : nil }
    private var requestedAssets: Set<String> { Set(contribution?.extractionDiagnostics?.requestedAssets ?? []) }
    private func shouldShow(_ target: CatalogPhotoTarget) -> Bool {
        guard isRetake, !requestedAssets.isEmpty else { return true }
        if target == .front { return requestedAssets.contains("front") }
        return requestedAssets.contains("back_label") || requestedAssets.contains("nutrition_facts") || requestedAssets.contains("ingredients")
    }
    private func hasPhoto(_ target: CatalogPhotoTarget) -> Bool {
        if isRetake, shouldShow(target) { return photos[target] != nil }
        return photos[target] != nil || contribution?.assets?.contains(where: { $0.assetKind == target.rawValue }) == true
    }
    private var readyToSubmit: Bool {
        let required = CatalogPhotoTarget.allCases.filter(shouldShow)
        return required.allSatisfy(hasPhoto) && (intent != .log || ProductServingQuantity.count(from: servingCount) != nil)
    }

    private func start() async {
        guard contribution == nil, acceptedDetail == nil else { return }
        guard let response = await app.startCatalogContribution(barcode: barcode, refreshExisting: refreshExisting) else { return }
        if let id = response.foodVersionID {
            acceptedDetail = await app.loadProductDetail(foodVersionID: id)
            return
        }
        guard let value = response.contribution else { return }
        contribution = value
        hasUnsavedDraft = value.status.isEditable
        if value.status == .processing || value.status == .pendingReview { step = .submitted }
    }

    private func load(_ item: PhotosPickerItem?, target: CatalogPhotoTarget) async {
        guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            app.catalogContributionErrorMessage = "Leafy couldn’t open that photo. Choose another image or take a new one."
            return
        }
        save(image, target: target)
    }

    private func save(_ image: UIImage, target: CatalogPhotoTarget) {
        guard let data = image.leafyMealJPEG(maxDimension: 3000, maxBytes: 8 * 1024 * 1024) else {
            app.catalogContributionErrorMessage = "Choose a clearer package photo smaller than 8 MB."
            return
        }
        photos[target] = data
        previews[target] = image
        hasUnsavedDraft = true
    }

    private func beginSubmission() {
        uploadTask?.cancel()
        showingUploadWait = true
        uploadTask = Task { @MainActor in
            guard var current = contribution else { showingUploadWait = false; return }
            for target in CatalogPhotoTarget.allCases {
                guard let data = photos[target] else { continue }
                guard let updated = await app.uploadCatalogPhoto(data, contributionID: current.id, assetKind: target.rawValue) else {
                    showingUploadWait = false
                    return
                }
                current = updated
            }
            contribution = current
            let count = intent == .log ? ProductServingQuantity.count(from: servingCount) : nil
            guard let result = await app.enqueueCatalogContribution(
                id: current.id,
                servingCount: count,
                consumedAt: intent == .log ? consumedAt : nil,
                mealType: intent == .log ? mealType : nil
            ) else {
                showingUploadWait = false
                return
            }
            contribution = result.contribution
            hasUnsavedDraft = false
            showingUploadWait = false
            step = .submitted
        }
    }

    private func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        showingUploadWait = false
    }

    private func adjustServing(_ delta: Double) {
        let current = ProductServingQuantity.count(from: servingCount) ?? 1
        let value = min(max(current + delta, ProductServingQuantity.allowedRange.lowerBound), ProductServingQuantity.allowedRange.upperBound)
        servingCount = ProductServingQuantity.formatted(value)
    }
}
