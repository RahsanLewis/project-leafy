import PhotosUI
import SwiftUI
import UIKit

struct AIMealView: View {
    @Environment(AppModel.self) private var app
    let onSaved: () -> Void
    let embedded: Bool
    let logDay: Date
    @Binding private var hasUnsavedDraft: Bool
    @State private var description: String
    @State private var selectedImage: UIImage?
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var mealDate = Date.now
    @State private var mealType: MealType = .unspecified
    @State private var followUpAnswer = ""
    @State private var analysisTask: Task<Void, Never>?
    @State private var showingAnalysisWait = false
    @State private var waitStartedAt = Date.now
    @State private var waitEstimateSeconds = 12.0
    @State private var showingMealDetails = false
    @State private var servingAmount = ""
    @State private var servingUnit = "serving"
    @State private var selectedProduct: ProductDetail?
    @State private var productServingCount = "1"
    @State private var showingScanner = false
    @State private var scannerStatus: BarcodeScannerStatus = .requestingPermission
    @State private var unknownBarcode: String?
    @State private var showingUnknownProduct = false
    @State private var showingContribution = false
    @State private var openContributionAfterUnknownProduct = false
    @State private var reopenScannerAfterUnknownProduct = false
    @FocusState private var descriptionIsFocused: Bool
    @FocusState private var clarificationIsFocused: Bool
    @Environment(\.openURL) private var openURL

    init(
        logDate: Date = .now,
        embedded: Bool = false,
        initialDescription: String = "",
        onSaved: @escaping () -> Void,
        hasUnsavedDraft: Binding<Bool> = .constant(false)
    ) {
        self.onSaved = onSaved
        self.embedded = embedded
        self.logDay = logDate
        _hasUnsavedDraft = hasUnsavedDraft
        _description = State(initialValue: initialDescription)
        _mealDate = State(initialValue: Self.logDate(logDate, usingTimeFrom: .now))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.large) {
                flowContent
            }
            .padding(.horizontal, 20)
            .padding(.top, LeafySpacing.medium)
            .padding(.bottom, 120)
        }
        .background(LeafyTheme.canvas)
        .animation(LeafyMotion.content, value: app.mealEstimate != nil || selectedProduct != nil)
        .navigationTitle(embedded ? "Log Food" : (app.mealEstimate == nil ? "Describe Food" : "Review nutrition"))
        .navigationBarTitleDisplayMode(embedded ? .inline : .large)
        .safeAreaInset(edge: .bottom) {
            primaryAction
                .leafyDetachedBottomControl()
        }
        .sheet(isPresented: $showingCamera) {
            MealCameraPicker { image in setImage(image) }
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showingPhotoLibrary,
            selection: $photoItem,
            matching: .images
        )
        .sheet(isPresented: $showingScanner) { scannerSheet }
        .sheet(isPresented: $showingUnknownProduct, onDismiss: finishUnknownProductSheet) {
            if let unknownBarcode {
                UnifiedUnknownProductSheet(
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
        .navigationDestination(isPresented: $showingContribution) {
            if let unknownBarcode {
                CatalogContributionView(
                    barcode: unknownBarcode,
                    intent: .log,
                    onCompleted: { onSaved() },
                    hasUnsavedDraft: $hasUnsavedDraft
                )
            }
        }
        .fullScreenCover(isPresented: $showingAnalysisWait) {
            AIMealLoadingView(
                startedAt: waitStartedAt,
                estimatedSeconds: waitEstimateSeconds,
                onCancel: cancelAnalysis
            )
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    app.mealEstimateErrorMessage = "Leafy couldn’t read that photo."
                    return
                }
                setImage(image)
            }
        }
        .onChange(of: description) { _, _ in updateDraftState() }
        .onChange(of: photoData) { _, _ in updateDraftState() }
        .onChange(of: servingAmount) { _, _ in updateDraftState() }
        .onChange(of: servingUnit) { _, _ in updateDraftState() }
        .onChange(of: app.mealEstimate?.followUp?.id) { _, _ in
            followUpAnswer = ""
            clarificationIsFocused = false
        }
        .onAppear { updateDraftState() }
        .task { await app.loadRecentLoggingFoods() }
        .task(id: description.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let query = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2, photoData == nil, selectedProduct == nil, app.mealEstimate == nil else {
                if query.count < 2 { app.productSearchResults = [] }
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await app.searchProducts(query)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    descriptionIsFocused = false
                    clarificationIsFocused = false
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var flowContent: some View {
        if let selectedProduct {
            knownProductReview(selectedProduct)
        } else if let estimate = app.mealEstimate {
            estimateContent(estimate)
        } else {
            composer
        }
    }

    @ViewBuilder private func estimateContent(_ estimate: MealEstimate) -> some View {
        if estimate.status == .needsClarification {
            clarification(estimate)
        } else {
            review(estimate)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("What did you eat?")
                    .font(LeafyTypography.title2)
                Text("Search for a known food, scan a package, or describe a meal for Leafy to estimate.")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("SEARCH OR DESCRIBE FOOD")
                    .font(LeafyTypography.captionSemibold)
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                TextField("Food, product, or meal", text: $description, axis: .vertical)
                    .focused($descriptionIsFocused)
                    .lineLimit(1...4)
                    .font(LeafyTypography.title3)
                    .padding(.vertical, LeafySpacing.small)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(descriptionIsFocused ? LeafyTheme.green : LeafyTheme.hairline)
                            .frame(height: descriptionIsFocused ? 2 : 1)
                            .animation(LeafyMotion.state, value: descriptionIsFocused)
                    }
                    .accessibilityIdentifier("aiMealDescription")

                HStack(spacing: LeafySpacing.compact) {
                    Text("Serving")
                        .font(LeafyTypography.body)
                    Spacer()
                    TextField("Typical", text: $servingAmount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 92)
                        .accessibilityIdentifier("describeServingAmount")
                    Picker("Serving unit", selection: $servingUnit) {
                        ForEach(["serving", "g", "oz", "cup", "piece", "tbsp", "tsp"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(minHeight: LeafyTheme.rowMinHeight)
                .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }

                Text(servingAmount.isEmpty
                     ? "Leafy will suggest a common serving for you to confirm."
                     : "You can adjust the serving and nutrition before logging.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: LeafySpacing.medium) {
                    photoInput
                    Button { showingScanner = true } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity, minHeight: LeafyTheme.minimumTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                    .accessibilityIdentifier("scanBarcodeButton")
                }
            }

            discoveryContent

            DisclosureGroup("Meal details", isExpanded: $showingMealDetails) {
                mealDetails.padding(.top, LeafySpacing.small)
            }
            .font(LeafyTypography.headline)
            .tint(LeafyTheme.green)

            if let message = app.mealEstimateErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("You’ll review the serving and nutrition before anything is added to your calorie budget.")
                .font(LeafyTypography.footnote).foregroundStyle(.secondary)

        }
    }

    private var photoInput: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            if let selectedImage {
                HStack(spacing: LeafySpacing.compact) {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: LeafyRadius.control))
                    VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                        Text("Photo added").font(LeafyTypography.headline)
                        Text("Leafy will use it with your description")
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { clearPhoto() }
                        .font(LeafyTypography.subheadlineSemibold)
                }
            } else {
                Menu {
                    Button { showingCamera = true } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    Button { showingPhotoLibrary = true } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Label("Add photo", systemImage: "camera")
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                    .frame(maxWidth: .infinity, minHeight: LeafyTheme.minimumTouchTarget)
                    .contentShape(.rect)
                }
                .accessibilityIdentifier("addMealPhotoButton")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var discoveryContent: some View {
        let query = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if photoData == nil && query.isEmpty && !app.recentLoggingFoods.isEmpty {
            foodResultSection("Recent foods", products: app.recentLoggingFoods)
        } else if photoData == nil && query.count >= 2 {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                HStack {
                    Text("MATCHES")
                        .font(LeafyTypography.captionSemibold)
                        .foregroundStyle(.secondary)
                        .tracking(0.6)
                    Spacer()
                    if app.isProductLoading { ProgressView().controlSize(.small) }
                }
                if app.productSearchResults.isEmpty && !app.isProductLoading {
                    Text("No known food matches yet. Leafy can estimate the description below.")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    foodResultRows(app.productSearchResults)
                }
            }
        }
    }

    private func foodResultSection(_ title: String, products: [ProductSummary]) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(title.uppercased())
                .font(LeafyTypography.captionSemibold)
                .foregroundStyle(.secondary)
                .tracking(0.6)
            foodResultRows(products)
        }
    }

    private func foodResultRows(_ products: [ProductSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(products.prefix(8).enumerated()), id: \.element.id) { index, product in
                Button { open(product) } label: {
                    HStack(spacing: LeafySpacing.compact) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(product.name.capitalized)
                                .font(LeafyTypography.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(foodResultMetadata(product))
                                .font(LeafyTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: LeafySpacing.small)
                        Image(systemName: "chevron.right")
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 64)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if index < min(products.count, 8) - 1 { Divider().overlay(LeafyTheme.hairline) }
            }
        }
    }

    private func foodResultMetadata(_ product: ProductSummary) -> String {
        var values: [String] = []
        if let brand = product.brand, !brand.isEmpty { values.append(brand) }
        values.append(product.foodKind == "packaged" ? "Packaged food" : "Known food")
        if let serving = product.servingSize {
            values.append("\(serving.formatted(.number.precision(.fractionLength(0...1)))) \(product.servingUnit ?? "g")")
        }
        return values.joined(separator: " · ")
    }

    private func open(_ product: ProductSummary) {
        descriptionIsFocused = false
        Task {
            guard let detail = await app.loadProductDetail(product) else { return }
            productServingCount = "1"
            selectedProduct = detail
            updateDraftState()
        }
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
                    if scannerStatus == .denied {
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(.white)
                        .frame(minHeight: LeafyTheme.minimumTouchTarget)
                    }
                }
        }
    }

    private func handleScannedCode(_ code: String) {
        showingScanner = false
        Task {
            if let product = await app.lookupProduct(barcode: code) { open(product) }
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

    private func knownProductReview(_ product: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
            ServingNutritionHero(
                name: product.name,
                subtitle: [product.brand, product.source].compactMap { $0 }.joined(separator: " · "),
                calories: knownProductCalories(product),
                nutrients: knownProductNutrients(product)
            )

            VStack(alignment: .leading, spacing: 0) {
                Text("Serving").font(LeafyTypography.title3).padding(.bottom, LeafySpacing.small)
                HStack(spacing: LeafySpacing.compact) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("How many servings did you eat?")
                            .font(LeafyTypography.bodyMedium)
                        Text("1 serving = \(knownServingLabel(product))")
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: LeafySpacing.small)
                    knownServingButton("minus", delta: -ProductServingQuantity.step)
                    TextField("1", text: $productServingCount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(LeafyTypography.headline)
                        .monospacedDigit()
                        .frame(width: 62, height: LeafyTheme.minimumTouchTarget)
                        .background(LeafyTheme.track, in: .rect(cornerRadius: LeafyRadius.control))
                        .accessibilityIdentifier("unifiedServingCountField")
                    knownServingButton("plus", delta: ProductServingQuantity.step)
                }
                .frame(minHeight: 72)
                Divider().overlay(LeafyTheme.hairline)
                DatePicker("Time", selection: $mealDate, displayedComponents: .hourAndMinute)
                    .frame(minHeight: LeafyTheme.rowMinHeight)
                Divider().overlay(LeafyTheme.hairline)
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                .frame(minHeight: LeafyTheme.rowMinHeight)
            }

            NutritionValueDisclosure(title: "Nutrition", nutrients: knownProductNutrients(product))

            if let score = product.score, score.isAvailable {
                DisclosureGroup("Leafy Score") {
                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        Text("\(score.score ?? 0)/100 · \(score.rating ?? "Rated")")
                            .font(LeafyTypography.title2)
                        ForEach(score.explanation.prefix(3), id: \.self) { value in
                            Text("• \(value)").font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, LeafySpacing.small)
                }
                .font(LeafyTypography.headline)
                .tint(LeafyTheme.green)
            }

            if let ingredients = product.ingredients, !ingredients.isEmpty || !product.allergens.isEmpty {
                DisclosureGroup("Ingredients & allergens") {
                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        if !ingredients.isEmpty { Text(ingredients).foregroundStyle(.secondary) }
                        if !product.allergens.isEmpty {
                            Text("Allergens: \(product.allergens.joined(separator: ", "))")
                                .font(LeafyTypography.subheadlineSemibold)
                        }
                    }
                    .font(LeafyTypography.subheadline)
                    .padding(.top, LeafySpacing.small)
                }
                .font(LeafyTypography.headline)
                .tint(LeafyTheme.green)
            }

            Text("Nutrition comes from \(product.source) and scales with the serving you choose.")
                .font(LeafyTypography.footnote)
                .foregroundStyle(.secondary)

            Button("Start over", role: .destructive) {
                selectedProduct = nil
                productServingCount = "1"
                app.productErrorMessage = nil
                updateDraftState()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var validProductServingCount: Double? {
        ProductServingQuantity.count(from: productServingCount)
    }

    private func knownProductGrams(_ product: ProductDetail) -> Double {
        ProductServingQuantity.grams(
            servings: validProductServingCount ?? 0,
            servingGrams: max(product.defaultGrams, 1)
        )
    }

    private func knownProductCalories(_ product: ProductDetail) -> Int {
        Int(((product.caloriesPer100G ?? 0) * knownProductGrams(product) / 100).rounded())
    }

    private func knownProductNutrients(_ product: ProductDetail) -> [NutrientAmountInput] {
        let grams = knownProductGrams(product)
        return product.nutrients.map {
            NutrientAmountInput(
                code: $0.code,
                amount: $0.amountPer100G * grams / 100,
                derivationMethod: product.foodKind == "packaged" ? .label : .calculated,
                sourceVersion: product.source,
                confidence: product.verificationStatus == "verified" ? 1 : 0.8
            )
        }
    }

    private func knownServingLabel(_ product: ProductDetail) -> String {
        if let portion = product.portions.first {
            let label = portion.description ?? "\(portion.amount.formatted()) \(portion.unit)"
            return "\(label) (\(portion.gramWeight.formatted(.number.precision(.fractionLength(0...1)))) g)"
        }
        return "\(product.defaultGrams.formatted(.number.precision(.fractionLength(0...1)))) g"
    }

    private func knownServingButton(_ symbol: String, delta: Double) -> some View {
        Button {
            let current = validProductServingCount ?? 1
            let value = min(max(current + delta, ProductServingQuantity.allowedRange.lowerBound), ProductServingQuantity.allowedRange.upperBound)
            productServingCount = ProductServingQuantity.formatted(value)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: symbol)
                .frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LeafyTheme.green)
    }

    private var mealDetails: some View {
        VStack(spacing: 0) {
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases) { type in Text(type.label).tag(type) }
            }
            .frame(minHeight: LeafyTheme.rowMinHeight)
            Divider()
            DatePicker("Date and time", selection: $mealDate, in: ...Date.now)
                .frame(minHeight: LeafyTheme.rowMinHeight)
        }
        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
    }

    @ViewBuilder private func review(_ estimate: MealEstimate) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            if let selectedImage {
                Image(uiImage: selectedImage).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 170)
                    .clipShape(.rect(cornerRadius: 20))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Nutrition review")
                    .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                Text("\(estimate.reviewedTotal) Cal")
                    .font(LeafyTypography.metric(42, extraBold: true))
                Text("Likely \(estimate.calorieLow)–\(estimate.calorieHigh) Cal")
                    .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("ITEMS").font(LeafyTypography.caption).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(estimate.items.enumerated()), id: \.element.id) { index, item in
                        MealEstimateItemCard(item: item) { name, portion, calories, estimatedGrams, nutrients in
                            app.updateMealEstimateItem(
                                id: item.id,
                                name: name,
                                portion: portion,
                                calories: calories,
                                estimatedGrams: estimatedGrams,
                                nutrients: nutrients
                            )
                        } onRemove: {
                            app.removeMealEstimateItem(id: item.id)
                        }
                        if index < estimate.items.count - 1 {
                            Divider().overlay(LeafyTheme.hairline)
                        }
                    }
                }
            }

            if !estimate.assumptions.isEmpty {
                DisclosureGroup("Assumptions") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(estimate.assumptions, id: \.self) { Text("• \($0)") }
                    }
                    .font(LeafyTypography.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                }
                .padding(.vertical, LeafySpacing.small)
            }

            if let message = app.mealEstimateErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(LeafyTypography.subheadline).foregroundStyle(.orange)
            }

            Text("Nutrition values can vary by recipe, preparation, and serving size. Review them before logging.")
                .font(LeafyTypography.footnote).foregroundStyle(.secondary)

            Button("Start over", role: .destructive) {
                Task {
                    await app.discardMealEstimate()
                    resetInputs()
                    hasUnsavedDraft = false
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay { if app.isMealEstimateLoading { ProgressView().controlSize(.large) } }
    }

    @ViewBuilder private func clarification(_ estimate: MealEstimate) -> some View {
        if let followUp = estimate.followUp {
            VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Label("One quick detail", systemImage: "questionmark.bubble.fill")
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(LeafyTheme.green)
                    Text("Help Leafy narrow the estimate")
                        .font(LeafyTypography.title2)
                        .accessibilityIdentifier("mealClarificationScreen")
                    Text("Your answer will be used to update the nutrition estimate before you review or log anything.")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: LeafySpacing.large) {
                    Text(followUp.question)
                        .font(LeafyTypography.title3)
                        .accessibilityIdentifier("mealClarificationQuestion")

                    TextField("Type your answer", text: $followUpAnswer, axis: .vertical)
                        .focused($clarificationIsFocused)
                        .lineLimit(2...5)
                        .font(LeafyTypography.body)
                        .padding(.vertical, LeafySpacing.small)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(clarificationIsFocused ? LeafyTheme.green : LeafyTheme.hairline)
                                .frame(height: clarificationIsFocused ? 2 : 1)
                                .animation(LeafyMotion.state, value: clarificationIsFocused)
                        }
                        .accessibilityIdentifier("mealClarificationAnswer")
                }

                if let message = app.mealEstimateErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            .background {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { clarificationIsFocused = false }
            }
        }
    }

    private var canAnalyze: Bool {
        photoData != nil || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder private var primaryAction: some View {
        if let product = selectedProduct {
            Button {
                Task {
                    if await app.logProduct(
                        product,
                        grams: knownProductGrams(product),
                        consumedAt: mealDate,
                        mealType: mealType
                    ) {
                        resetInputs()
                        hasUnsavedDraft = false
                        onSaved()
                    }
                }
            } label: {
                if app.isFoodMutationInProgress { ProgressView().tint(.white) }
                else { Text("Log \(knownProductCalories(product)) calories") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(app.isFoodMutationInProgress || validProductServingCount == nil)
            .opacity(validProductServingCount == nil ? 0.45 : 1)
            .accessibilityIdentifier("confirmKnownFoodButton")
        } else if let estimate = app.mealEstimate {
            if estimate.status == .needsClarification {
                VStack(spacing: LeafySpacing.compact) {
                    Button {
                        clarificationIsFocused = false
                        refineEstimate(answer: followUpAnswer, skip: false)
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmedFollowUpAnswer.isEmpty || app.isMealEstimateLoading)
                    .opacity(trimmedFollowUpAnswer.isEmpty ? 0.45 : 1)
                    .accessibilityIdentifier("submitMealClarificationButton")

                    Button("I’m not sure") {
                        clarificationIsFocused = false
                        refineEstimate(answer: nil, skip: true)
                    }
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                    .frame(minHeight: LeafyTheme.minimumTouchTarget)
                    .disabled(app.isMealEstimateLoading)
                    .accessibilityIdentifier("skipMealClarificationButton")
                }
            } else {
                Button { confirm() } label: {
                    if app.isMealEstimateLoading { ProgressView().tint(.white) }
                    else { Text("Log \(estimate.reviewedTotal) calories") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(estimate.items.isEmpty || app.isMealEstimateLoading)
                .accessibilityIdentifier("confirmMealEstimateButton")
            }
        } else if app.mealEstimate == nil {
            Button { analyze() } label: {
                if app.isMealEstimateLoading { ProgressView().tint(.white) }
                else { Text("Analyze nutrition") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAnalyze || app.isMealEstimateLoading)
            .opacity(canAnalyze ? 1 : 0.45)
            .accessibilityIdentifier("analyzeMealButton")
        }
    }

    private func setImage(_ image: UIImage) {
        guard let data = image.leafyMealJPEG(), let normalized = UIImage(data: data) else {
            app.mealEstimateErrorMessage = "Choose a smaller meal photo."
            return
        }
        selectedImage = normalized
        photoData = data
    }

    private func clearPhoto() { selectedImage = nil; photoData = nil; photoItem = nil }

    private func analyze() {
        let inputDescription = resolvedDescription
        let photo = photoData
        let date = mealDate
        let type = mealType
        beginAnalysis(hasPhoto: photo != nil) {
            await app.analyzeMeal(
                description: inputDescription, photoData: photo,
                consumedAt: date, localDate: date, mealType: type
            )
        }
    }

    private func refineEstimate(answer: String?, skip: Bool) {
        beginAnalysis(hasPhoto: photoData != nil) {
            await app.answerMealFollowUp(answer, skip: skip)
        }
    }

    private var trimmedFollowUpAnswer: String {
        followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginAnalysis(hasPhoto: Bool, operation: @escaping @MainActor () async -> Bool) {
        analysisTask?.cancel()
        waitStartedAt = .now
        waitEstimateSeconds = AIMealWaitEstimator.estimatedSeconds(hasPhoto: hasPhoto)
        showingAnalysisWait = true
        analysisTask = Task { @MainActor in
            let startedAt = Date.now
            let succeeded = await operation()
            guard !Task.isCancelled else { return }
            if succeeded {
                AIMealWaitEstimator.record(Date.now.timeIntervalSince(startedAt), hasPhoto: hasPhoto)
            }
            showingAnalysisWait = false
            analysisTask = nil
        }
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        showingAnalysisWait = false
        Task { await app.cancelMealEstimateAnalysis() }
    }

    private func confirm() {
        Task {
            if await app.confirmMealEstimate() {
                resetInputs()
                hasUnsavedDraft = false
                onSaved()
            }
        }
    }

    private func resetInputs() {
        description = ""; selectedImage = nil; photoData = nil; photoItem = nil
        selectedProduct = nil; productServingCount = "1"
        servingAmount = ""; servingUnit = "serving"
        followUpAnswer = ""; mealDate = Self.logDate(logDay, usingTimeFrom: .now); mealType = .unspecified
    }

    private func updateDraftState() {
        hasUnsavedDraft = selectedProduct != nil || app.mealEstimate != nil || photoData != nil
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !servingAmount.isEmpty
    }

    private var resolvedDescription: String {
        let base = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !servingAmount.isEmpty else { return base }
        return "\(base)\nServing consumed: \(servingAmount) \(servingUnit)"
    }

    private static func logDate(_ day: Date, usingTimeFrom time: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components) ?? day
    }
}

private struct MealEstimateItemCard: View {
    @Environment(AppModel.self) private var app
    let item: MealEstimateItem
    let onChange: (String, String, Int, Double?, [NutrientAmountInput]) -> Void
    let onRemove: () -> Void
    @State private var name: String
    @State private var portion: String
    @State private var calories: String
    @State private var nutrients: [NutrientAmountInput]
    @State private var servingCount = "1"
    @State private var showingNutrients = false

    private let baseName: String
    private let basePortion: String
    private let baseCalories: Int
    private let baseGrams: Double?
    private let baseNutrients: [NutrientAmountInput]

    init(
        item: MealEstimateItem,
        onChange: @escaping (String, String, Int, Double?, [NutrientAmountInput]) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.item = item; self.onChange = onChange; self.onRemove = onRemove
        baseName = item.name; basePortion = item.portion; baseCalories = item.calories
        baseGrams = item.estimatedGrams; baseNutrients = item.nutrients ?? []
        _name = State(initialValue: item.name); _portion = State(initialValue: item.portion)
        _calories = State(initialValue: String(item.calories))
        _nutrients = State(initialValue: item.nutrients ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                if isResolvedFood {
                    Text(name).font(LeafyTypography.headline)
                } else {
                    TextField("Food", text: $name).font(LeafyTypography.headline)
                }
                Button(role: .destructive, action: onRemove) { Image(systemName: "trash") }
                    .accessibilityLabel("Remove \(name)")
            }
            Text(item.sourceLabel)
                .font(LeafyTypography.captionSemibold)
                .foregroundStyle(LeafyTheme.green)
            if isResolvedFood {
                servingEditor
                Text(resolvedPortionDescription)
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Estimated portion", text: $portion)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                if isResolvedFood {
                    Text("\(Int(calories) ?? 0)")
                        .font(LeafyTypography.title2)
                        .monospacedDigit()
                } else {
                    TextField("Calories", text: $calories)
                        .keyboardType(.numberPad).font(LeafyTypography.title2).frame(maxWidth: 110)
                }
                Text("Cal").foregroundStyle(.secondary)
                Spacer()
                if !isResolvedFood {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.confidenceLabel).font(LeafyTypography.captionSemibold)
                        Text("Range \(item.calorieLow)–\(item.calorieHigh)").font(LeafyTypography.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !nutrients.isEmpty {
                HStack(spacing: LeafySpacing.large) {
                    macro("Protein", code: "protein_g", nutrients: nutrients)
                    macro("Carbs", code: "carbohydrate_g", nutrients: nutrients)
                    macro("Fat", code: "fat_g", nutrients: nutrients)
                }
                .padding(.top, LeafySpacing.xSmall)
                Button {
                    showingNutrients = true
                } label: {
                    HStack {
                        Text("Review nutrition")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                    .frame(minHeight: LeafyTheme.rowMinHeight)
                }
                if app.configuration.isFoodImpactEnabled {
                    NavigationLink {
                        AIItemImpactView(item: item)
                    } label: {
                        HStack {
                            Text("View food impact")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(LeafyTheme.green)
                        .padding(.top, LeafySpacing.small)
                    }
                    .accessibilityIdentifier("aiItemFoodImpact")
                }
            }
        }
        .padding(.vertical, LeafySpacing.medium)
        .frame(minHeight: LeafyTheme.rowMinHeight)
        .onChange(of: name) { _, _ in publish() }
        .onChange(of: portion) { _, _ in publish() }
        .onChange(of: calories) { _, _ in publish() }
        .sheet(isPresented: $showingNutrients) {
            MealNutrientReviewSheet(nutrients: $nutrients, editable: !isResolvedFood)
        }
        .onChange(of: nutrients) { _, _ in publish() }
        .onChange(of: servingCount) { _, _ in applyServingScale() }
    }

    private var isResolvedFood: Bool {
        item.resolutionSource == "usda" || item.resolutionSource == "leafy_catalog"
    }

    private var validServingCount: Double? { ProductServingQuantity.count(from: servingCount) }

    private var resolvedPortionDescription: String {
        guard let count = validServingCount else { return "Enter a serving amount" }
        if count == 1 { return basePortion }
        return "\(ProductServingQuantity.formatted(count)) × \(basePortion)"
    }

    private var servingEditor: some View {
        HStack(spacing: LeafySpacing.small) {
            Text("Servings").font(LeafyTypography.subheadlineSemibold)
            Spacer()
            servingButton("minus", delta: -ProductServingQuantity.step)
            TextField("1", text: $servingCount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(LeafyTypography.headline)
                .frame(width: 62)
                .frame(minHeight: LeafyTheme.minimumTouchTarget)
                .accessibilityIdentifier("resolvedFoodServingCount")
            servingButton("plus", delta: ProductServingQuantity.step)
        }
    }

    private func servingButton(_ symbol: String, delta: Double) -> some View {
        Button {
            let current = validServingCount ?? 1
            servingCount = ProductServingQuantity.formatted(
                min(max(current + delta, ProductServingQuantity.allowedRange.lowerBound), ProductServingQuantity.allowedRange.upperBound)
            )
        } label: {
            Image(systemName: symbol).frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LeafyTheme.green)
    }

    private func applyServingScale() {
        guard isResolvedFood, let count = validServingCount else { return }
        name = baseName
        portion = resolvedPortionDescription
        calories = String(Int((Double(baseCalories) * count).rounded()))
        nutrients = baseNutrients.map {
            var nutrient = $0
            nutrient.amount = $0.amount * count
            return nutrient
        }
        onChange(name, portion, Int(calories) ?? 0, baseGrams.map { $0 * count }, nutrients)
    }

    private func publish() {
        guard !isResolvedFood else { return }
        onChange(name, portion, Int(calories) ?? 0, item.estimatedGrams, nutrients)
    }

    private func macro(_ title: String, code: String, nutrients: [NutrientAmountInput]) -> some View {
        let value = nutrients.first { $0.code == code }?.amount ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(LeafyTypography.caption).foregroundStyle(.secondary)
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(LeafyTypography.subheadlineSemibold).monospacedDigit()
        }
    }
}

private struct MealNutrientReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var nutrients: [NutrientAmountInput]
    let editable: Bool

    private let coreCodes = [
        "protein_g", "carbohydrate_g", "fat_g", "fiber_g", "sugars_g", "added_sugars_g",
        "saturated_fat_g", "trans_fat_g", "cholesterol_mg", "sodium_mg", "potassium_mg",
        "calcium_mg", "iron_mg", "vitamin_d_mcg",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(coreCodes, id: \.self) { code in
                        if let definition = NutrientCatalog.items.first(where: { $0.code == code }) {
                            HStack {
                                Text(definition.name)
                                Spacer()
                                TextField("0", text: binding(for: definition))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 88)
                                    .disabled(!editable)
                                Text(definition.unit).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text(editable
                         ? "Values describe the serving shown on the review screen."
                         : "Nutrition is supplied by the matched food source. Change servings on the review screen to adjust these values.")
                }
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for definition: NutrientCatalog.Item) -> Binding<String> {
        Binding(
            get: {
                guard let value = nutrients.first(where: { $0.code == definition.code })?.amount else { return "" }
                return value.formatted(.number.precision(.fractionLength(0...2)))
            },
            set: { text in
                let normalized = text.replacingOccurrences(of: ",", with: ".")
                guard let value = Double(normalized), value >= 0 else {
                    if text.isEmpty { nutrients.removeAll { $0.code == definition.code } }
                    return
                }
                if let index = nutrients.firstIndex(where: { $0.code == definition.code }) {
                    nutrients[index].amount = value
                    nutrients[index].derivationMethod = .userEntered
                    nutrients[index].sourceVersion = "ios-nutrition-review-v1"
                    nutrients[index].confidence = nil
                } else {
                    nutrients.append(NutrientAmountInput(
                        code: definition.code,
                        amount: value,
                        derivationMethod: .userEntered,
                        sourceVersion: "ios-nutrition-review-v1"
                    ))
                }
            }
        )
    }
}

private struct UnifiedUnknownProductSheet: View {
    let barcode: String
    let addProduct: () -> Void
    let scanAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            Image(systemName: "barcode.viewfinder")
                .font(LeafyTypography.icon(34))
                .foregroundStyle(LeafyTheme.green)
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("We couldn’t find this product").font(LeafyTypography.title2)
                Text("Add the package to help Leafy recognize it next time.")
                    .font(LeafyTypography.body).foregroundStyle(.secondary)
                Text("Barcode \(barcode)")
                    .font(LeafyTypography.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            Button("Add product", action: addProduct)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("addUnknownProductButton")
            Button("Scan another", action: scanAnother)
                .font(LeafyTypography.button).foregroundStyle(LeafyTheme.green)
                .frame(maxWidth: .infinity, minHeight: LeafyTheme.minimumTouchTarget)
        }
        .padding(.horizontal, LeafyTheme.pageInset)
        .padding(.top, LeafySpacing.small)
        .padding(.bottom, LeafySpacing.medium)
    }
}

private struct AIItemImpactView: View {
    let item: MealEstimateItem
    @State private var servingScale = 1.0

    var body: some View {
        ScrollView {
            FoodImpactDashboard(
                input: FoodImpactInput(
                    name: item.name,
                    baseCalories: Double(item.calories),
                    nutrients: item.nutrients ?? [],
                    provenance: "AI-assisted estimate",
                    confidence: item.confidence,
                    context: .prospective
                ),
                servingScale: $servingScale,
                servingDescription: { scale in
                    if let grams = item.estimatedGrams {
                        return "\((grams * scale).formatted(.number.precision(.fractionLength(0...1)))) g"
                    }
                    return "\(scale.formatted(.number.precision(.fractionLength(0...2))))× estimated serving"
                }
            )
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.vertical, LeafySpacing.medium)
        }
        .background(LeafyTheme.canvas)
        .navigationTitle(item.name.capitalized)
        .navigationBarTitleDisplayMode(.inline)
    }
}
