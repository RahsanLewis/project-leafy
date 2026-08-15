import PhotosUI
import SwiftUI
import UIKit

private enum CatalogContributionStep { case capture, review, submitted }
private enum CatalogPhotoTarget: String, Identifiable {
    case front, backLabel = "back_label", nutritionFacts = "nutrition_facts", ingredients
    var id: String { rawValue }
    var title: String {
        switch self {
        case .front: "Package front"
        case .backLabel: "Nutrition Facts and ingredients"
        case .nutritionFacts: "Nutrition Facts close-up"
        case .ingredients: "Ingredients close-up"
        }
    }
}

private struct LabelNutrientDefinition: Identifiable {
    let code: String; let title: String; let unit: String
    var id: String { code }
    static let standard = [
        Self(code: "energy_kcal", title: "Calories", unit: "Cal"),
        Self(code: "fat_g", title: "Total fat", unit: "g"),
        Self(code: "saturated_fat_g", title: "Saturated fat", unit: "g"),
        Self(code: "trans_fat_g", title: "Trans fat", unit: "g"),
        Self(code: "cholesterol_mg", title: "Cholesterol", unit: "mg"),
        Self(code: "sodium_mg", title: "Sodium", unit: "mg"),
        Self(code: "carbohydrate_g", title: "Carbohydrate", unit: "g"),
        Self(code: "fiber_g", title: "Dietary fiber", unit: "g"),
        Self(code: "sugars_g", title: "Total sugars", unit: "g"),
        Self(code: "added_sugars_g", title: "Added sugars", unit: "g"),
        Self(code: "protein_g", title: "Protein", unit: "g"),
        Self(code: "vitamin_d_mcg", title: "Vitamin D", unit: "mcg"),
        Self(code: "calcium_mg", title: "Calcium", unit: "mg"),
        Self(code: "iron_mg", title: "Iron", unit: "mg"),
        Self(code: "potassium_mg", title: "Potassium", unit: "mg"),
    ]
}

private struct LabelNutrientDraft: Identifiable {
    let code: String; let title: String; let unit: String
    var amount: String; var dailyValue: String; var confidence: Double
    var id: String { code }
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

    private static func clamp(_ value: Double) -> Double {
        min(60, max(8, value))
    }
}

struct CatalogContributionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let barcode: String
    let intent: ProductDiscoveryIntent
    let onCompleted: (() -> Void)?
    @Binding private var hasUnsavedDraft: Bool

    @State private var contribution: CatalogContribution?
    @State private var step: CatalogContributionStep = .capture
    @State private var fields = CatalogContributionFields.empty
    @State private var nutrientDrafts: [LabelNutrientDraft] = []
    @State private var photoTarget: CatalogPhotoTarget?
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var factsItem: PhotosPickerItem?
    @State private var ingredientsItem: PhotosPickerItem?
    @State private var photos: [CatalogPhotoTarget: Data] = [:]
    @State private var previews: [CatalogPhotoTarget: UIImage] = [:]
    @State private var acceptedDetail: ProductDetail?
    @State private var consumedAt = Date()
    @State private var mealType: MealType = .unspecified
    @State private var grams = 0.0
    @State private var servingCount = "1"
    @State private var isEditingExtractedFields = false
    @State private var isNutritionExpanded = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var showingAnalysisWait = false
    @State private var waitStartedAt = Date.now
    @State private var waitEstimateSeconds = 25.0

    init(
        barcode: String,
        intent: ProductDiscoveryIntent,
        onCompleted: (() -> Void)?,
        hasUnsavedDraft: Binding<Bool> = .constant(false)
    ) {
        self.barcode = barcode
        self.intent = intent
        self.onCompleted = onCompleted
        _hasUnsavedDraft = hasUnsavedDraft
    }

    var body: some View {
        Group {
            if contribution == nil && acceptedDetail == nil {
                ProgressView("Preparing contribution…")
            } else {
                switch step {
                case .capture: captureContent
                case .review: reviewContent
                case .submitted: submittedView
                }
            }
        }
        .navigationTitle(step == .review ? "Review Product" : "Add Product")
        .navigationBarTitleDisplayMode(.inline)
        .task { await start() }
        .onChange(of: frontItem) { _, item in Task { await load(item, target: .front) } }
        .onChange(of: backItem) { _, item in Task { await load(item, target: .backLabel) } }
        .onChange(of: factsItem) { _, item in Task { await load(item, target: .nutritionFacts) } }
        .onChange(of: ingredientsItem) { _, item in Task { await load(item, target: .ingredients) } }
        .sheet(item: $photoTarget) { target in
            MealCameraPicker { image in save(image, target: target) }
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingAnalysisWait) {
            LeafyAnalysisLoadingView(
                title: "Leafy is reading the package",
                facts: Self.packageFacts,
                startedAt: waitStartedAt,
                estimatedSeconds: waitEstimateSeconds,
                loadingAccessibilityIdentifier: "catalogAnalysisLoadingScreen",
                cancelAccessibilityIdentifier: "cancelCatalogAnalysisButton",
                onCancel: cancelAnalysis
            )
        }
        .navigationDestination(item: $acceptedDetail) { product in
            ProductDetailView(product: product, intent: intent, logDate: app.selectedLogDate, onLogged: { onCompleted?() })
        }
        .alert("Couldn’t add product", isPresented: Binding(
            get: { app.catalogContributionErrorMessage != nil },
            set: { if !$0 { app.catalogContributionErrorMessage = nil } }
        )) { Button("OK") {} } message: { Text(app.catalogContributionErrorMessage ?? "") }
    }

    @ViewBuilder private var captureContent: some View { loggingCaptureView }

    @ViewBuilder private var reviewContent: some View {
        if isEditingExtractedFields { loggingReviewView }
        else { extractedReviewView }
    }

    private static let packageFacts = [
        "Ingredients are listed from greatest to smallest amount by weight.",
        "Nutrition Facts describe one labeled serving, which may differ from the amount you eat.",
        "A sharp label close-up helps Leafy capture small values like added sugar and micronutrients.",
        "Leafy keeps package photos private and uses them to verify the product details.",
        "Serving size and servings per container describe two different things.",
        "Reviewing the result helps keep Leafy’s shared food catalog accurate.",
    ]

    private var captureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.large) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Help Leafy recognize this product").font(LeafyTypography.title)
                    Text("Photograph the label once, then check the information before it joins the catalog.")
                        .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                    Text("Barcode \(barcode)").font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
                photoSlot(.front, item: $frontItem)
                photoSlot(.backLabel, item: $backItem)
                if needsFactsCloseup { photoSlot(.nutritionFacts, item: $factsItem) }
                if needsIngredientsCloseup { photoSlot(.ingredients, item: $ingredientsItem) }
                Label("Photos stay private and are used only to verify structured label data.", systemImage: "lock.shield")
                    .font(LeafyTypography.footnote).foregroundStyle(.secondary)
            }
            .padding(LeafyTheme.pageInset)
            .padding(.bottom, 96)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Read Label", action: beginAnalysis)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!hasPhoto(.front) || !hasPhoto(.backLabel) || app.isCatalogContributionLoading)
                .opacity(hasPhoto(.front) && hasPhoto(.backLabel) ? 1 : 0.45)
                .leafyDetachedBottomControl()
                .accessibilityIdentifier("readProductLabelButton")
        }
    }

    private var loggingCaptureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                if let diagnostics = contribution?.extractionDiagnostics, diagnostics.status == .needsPhotos {
                    Label(diagnostics.message, systemImage: "camera.fill")
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("catalogRetakeMessage")
                }
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Text("Help Leafy recognize this product")
                        .font(LeafyTypography.title2)
                    Text("Photograph the package front, Nutrition Facts, and ingredients. Leafy will fill in the product details for you.")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Barcode \(barcode)")
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.secondary)
                }

                loggingPhotoSlot(.front, item: $frontItem)
                loggingPhotoSlot(.nutritionFacts, item: $factsItem)
                loggingPhotoSlot(.ingredients, item: $ingredientsItem)

                Label("Photos remain private and are used to verify label data.", systemImage: "lock.shield")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)

                if contribution?.extractionDiagnostics?.status == .needsPhotos {
                    Button("Enter details manually") {
                        isEditingExtractedFields = true
                        step = .review
                    }
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                    .frame(minHeight: LeafyTheme.minimumTouchTarget)
                    .accessibilityIdentifier("manualCatalogFallbackButton")
                }
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.vertical, LeafySpacing.medium)
            .padding(.bottom, 112)
        }
        .background(LeafyTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            Button("Read Package", action: beginAnalysis)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!readyToReadPackage || app.isCatalogContributionLoading)
                .opacity(readyToReadPackage ? 1 : 0.45)
                .leafyDetachedBottomControl()
                .accessibilityIdentifier("readProductLabelButton")
        }
    }

    private var reviewView: some View {
        List {
            if let reason = contribution?.reviewReason, contribution?.status == .needsReview {
                Section { Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    .leafyBorderlessRows(separators: false)
            }
            Section("Product") {
                TextField("Product name", text: $fields.productName)
                Toggle("Brand is not shown", isOn: $fields.brandNotShown)
                if !fields.brandNotShown { TextField("Brand", text: $fields.brandName) }
                Text("Barcode \(barcode)").foregroundStyle(.secondary)
            }.leafyBorderlessRows()
            Section("Serving") {
                TextField("Serving description", text: $fields.servingDescription)
                LabeledContent("Serving weight") {
                    HStack { TextField("28", value: $fields.servingGrams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("g").foregroundStyle(.secondary) }.frame(width: 130)
                }
                TextField("Servings per container", text: $fields.servingsPerContainer)
            }.leafyBorderlessRows()
            Section("Nutrition per serving") {
                ForEach($nutrientDrafts) { $nutrient in
                    LabeledContent(nutrient.title) {
                        HStack(spacing: 6) {
                            TextField("Required", text: $nutrient.amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Text(nutrient.unit).foregroundStyle(.secondary)
                        }.frame(width: 145)
                    }
                }
            }.leafyBorderlessRows()
            Section("Ingredients · Required") {
                TextEditor(text: $fields.ingredients).frame(minHeight: 110)
                TextField("Declared allergens, separated by commas", text: allergensBinding)
            }.leafyBorderlessRows()
            if intent == .log {
                Section("Add to food log") {
                    LabeledContent("Amount") { HStack { TextField("28", value: $grams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("g").foregroundStyle(.secondary) }.frame(width: 130) }
                    DatePicker("Time", selection: $consumedAt, displayedComponents: .hourAndMinute)
                    Picker("Meal", selection: $mealType) { ForEach(MealType.allCases) { Text($0.label).tag($0) } }
                }.leafyBorderlessRows()
            }
            Section {
                Button("Improve label photos") { step = .capture }
            } footer: {
                Text("By submitting, you confirm this matches the package. Leafy may use the structured label data in its shared catalog. Photos remain private verification evidence.")
            }.leafyBorderlessRows(separators: false)
        }
        .leafyBorderlessList().listSectionSpacing(LeafySpacing.large)
        .safeAreaInset(edge: .bottom) {
            Button(intent == .log ? "Submit and Log Food" : "Submit Product") { Task { await submit() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit || app.isCatalogContributionLoading)
                .opacity(canSubmit ? 1 : 0.45)
                .leafyDetachedBottomControl()
                .accessibilityIdentifier("submitProductContributionButton")
        }
    }

    private var extractedReviewView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Text("Check what Leafy found")
                        .font(LeafyTypography.title2)
                    Text("Confirm the details Leafy read from your package photos.")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                }

                contributionSection("Product") {
                    contributionValueRow("Name", fields.productName)
                    contributionValueRow("Brand", fields.brandNotShown ? "Not shown" : fields.brandName)
                    contributionValueRow("Barcode", barcode)
                }

                contributionSection("Serving") {
                    contributionValueRow("Serving", fields.servingDescription)
                    contributionValueRow("Serving weight", "\(format(fields.servingGrams)) g")
                    if !fields.servingsPerContainer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        contributionValueRow("Per container", fields.servingsPerContainer)
                    }
                }

                contributionSection("Nutrition per serving") {
                    HStack(alignment: .firstTextBaseline, spacing: LeafySpacing.large) {
                        nutritionMetric("Calories", code: "energy_kcal", unit: "Cal")
                        nutritionMetric("Protein", code: "protein_g", unit: "g")
                        nutritionMetric("Carbs", code: "carbohydrate_g", unit: "g")
                        nutritionMetric("Fat", code: "fat_g", unit: "g")
                    }
                    .padding(.vertical, LeafySpacing.small)

                    DisclosureGroup("Full Nutrition Facts", isExpanded: $isNutritionExpanded) {
                        VStack(spacing: 0) {
                            ForEach(nutrientDrafts) { nutrient in
                                contributionValueRow(
                                    nutrient.title,
                                    "\(nutrient.amount) \(nutrient.unit)"
                                )
                            }
                        }
                        .padding(.top, LeafySpacing.xSmall)
                    }
                    .font(LeafyTypography.subheadlineSemibold)
                    .tint(LeafyTheme.green)
                    .frame(minHeight: LeafyTheme.rowMinHeight)
                }

                contributionSection("Ingredients") {
                    Text(fields.ingredients)
                        .font(LeafyTypography.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, LeafySpacing.small)
                    if !fields.allergens.isEmpty {
                        Text("Contains: \(fields.allergens.joined(separator: ", "))")
                            .font(LeafyTypography.subheadlineSemibold)
                            .foregroundStyle(.secondary)
                    }
                }

                if intent == .log {
                    contributionSection("Add to food log") {
                        servingCountEditor
                        DatePicker("Time", selection: $consumedAt, displayedComponents: .hourAndMinute)
                            .frame(minHeight: LeafyTheme.rowMinHeight)
                            .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
                        Picker("Meal", selection: $mealType) {
                            ForEach(MealType.allCases) { Text($0.label).tag($0) }
                        }
                        .frame(minHeight: LeafyTheme.rowMinHeight)
                    }
                }

                HStack(spacing: LeafySpacing.large) {
                    Button("Something looks wrong") { isEditingExtractedFields = true }
                    Button("Retake photos") { step = .capture }
                }
                .font(LeafyTypography.subheadlineSemibold)
                .foregroundStyle(LeafyTheme.green)

                Text("By submitting, you confirm this matches the package. Structured label data may join Leafy’s shared catalog; photos remain private verification evidence.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.vertical, LeafySpacing.medium)
            .padding(.bottom, 112)
        }
        .background(LeafyTheme.canvas)
        .safeAreaInset(edge: .bottom) { contributionSubmitButton }
        .accessibilityIdentifier("catalogExtractedReview")
    }

    private var loggingReviewView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                if let reason = contribution?.reviewReason, contribution?.status == .needsReview {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.orange)
                }

                contributionSection("Product") {
                    contributionTextField("Product name", text: $fields.productName)
                    Toggle("Brand is not shown", isOn: $fields.brandNotShown)
                        .frame(minHeight: LeafyTheme.rowMinHeight)
                        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
                    if !fields.brandNotShown {
                        contributionTextField("Brand", text: $fields.brandName)
                    }
                    contributionValueRow("Barcode", barcode)
                }

                contributionSection("Serving") {
                    contributionTextField("Serving description", text: $fields.servingDescription)
                    HStack {
                        Text("Serving weight")
                        Spacer()
                        TextField("28", value: $fields.servingGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("g").foregroundStyle(.secondary)
                    }
                    .frame(minHeight: LeafyTheme.rowMinHeight)
                    .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
                    contributionTextField("Servings per container", text: $fields.servingsPerContainer)
                }

                contributionSection("Nutrition per serving") {
                    ForEach($nutrientDrafts) { $nutrient in
                        HStack {
                            Text(nutrient.title)
                            Spacer()
                            TextField("Required", text: $nutrient.amount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text(nutrient.unit)
                                .font(LeafyTypography.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 34, alignment: .leading)
                        }
                        .frame(minHeight: LeafyTheme.rowMinHeight)
                        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
                    }
                }

                contributionSection("Ingredients · Required") {
                    TextEditor(text: $fields.ingredients)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
                    contributionTextField("Declared allergens", text: allergensBinding)
                }

                if intent == .log { contributionSection("Add to food log") {
                    servingCountEditor
                    DatePicker("Time", selection: $consumedAt, displayedComponents: .hourAndMinute)
                        .frame(minHeight: LeafyTheme.rowMinHeight)
                    Divider().overlay(LeafyTheme.hairline)
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { Text($0.label).tag($0) }
                    }
                    .frame(minHeight: LeafyTheme.rowMinHeight)
                } }

                Button("Improve label photos") { step = .capture }
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)

                Text("By submitting, you confirm this matches the package. Structured label data may join Leafy’s shared catalog; photos remain private verification evidence.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.vertical, LeafySpacing.medium)
            .padding(.bottom, 112)
        }
        .background(LeafyTheme.canvas)
        .safeAreaInset(edge: .bottom) { contributionSubmitButton }
    }

    private var submittedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: contribution?.status == .accepted ? "checkmark.circle.fill" : "clock.badge.checkmark.fill")
                .font(.system(size: 58)).foregroundStyle(LeafyTheme.green)
            Text(contribution?.status == .accepted ? "Product added" : "Submitted for review").font(LeafyTypography.title)
            Text(contribution?.reviewReason ?? "You can follow its status in My Contributions.")
                .font(LeafyTypography.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Done") {
                hasUnsavedDraft = false
                onCompleted?()
                dismiss()
            }.buttonStyle(PrimaryButtonStyle())
        }.padding(LeafyTheme.pageInset)
    }

    private func photoSlot(_ target: CatalogPhotoTarget, item: Binding<PhotosPickerItem?>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.title).font(LeafyTypography.headline)
                    Text(target == .front ? "Show the product name and brand" : "Make all small print readable")
                        .font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if hasPhoto(target) { Image(systemName: "checkmark.circle.fill").foregroundStyle(LeafyTheme.green) }
            }
            if let image = previews[target] {
                Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 150).clipShape(.rect(cornerRadius: 18))
            }
            HStack(spacing: 12) {
                Button { photoTarget = target } label: { Label(hasPhoto(target) ? "Retake" : "Take Photo", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(CatalogPhotoButtonStyle())
                PhotosPicker(selection: item, matching: .images) { Label("Choose", systemImage: "photo.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(CatalogPhotoButtonStyle())
            }
        }
    }

    private func loggingPhotoSlot(_ target: CatalogPhotoTarget, item: Binding<PhotosPickerItem?>) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
                    Text(target.title).font(LeafyTypography.headline)
                    Text(photoInstruction(target))
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: needsRetake(target) ? "exclamationmark.circle.fill" : hasPhoto(target) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(needsRetake(target) ? .orange : hasPhoto(target) ? LeafyTheme.green : Color.secondary.opacity(0.55))
            }

            if let image = previews[target] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(.rect(cornerRadius: LeafyRadius.control))
            }

            Menu {
                Button { photoTarget = target } label: {
                    Label(hasPhoto(target) ? "Retake Photo" : "Take Photo", systemImage: "camera")
                }
                PhotosPicker(selection: item, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                }
            } label: {
                HStack {
                    Label(hasPhoto(target) ? "Replace photo" : "Add photo", systemImage: "camera")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.tertiary)
                }
                .font(LeafyTypography.subheadlineSemibold)
                .foregroundStyle(LeafyTheme.green)
                .frame(minHeight: LeafyTheme.rowMinHeight)
            }
            .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
        }
    }

    private var servingCountEditor: some View {
        HStack(spacing: LeafySpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How many servings did you eat?")
                Text("\(format(consumedGrams)) g total")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            servingCountButton("minus", delta: -ProductServingQuantity.step)
            TextField("1", text: $servingCount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(LeafyTypography.headline)
                .frame(width: 62)
                .frame(minHeight: LeafyTheme.minimumTouchTarget)
                .accessibilityIdentifier("contributionServingCount")
            servingCountButton("plus", delta: ProductServingQuantity.step)
        }
        .frame(minHeight: LeafyTheme.rowMinHeight)
        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
    }

    private func servingCountButton(_ symbol: String, delta: Double) -> some View {
        Button {
            let current = validServingCount ?? 1
            servingCount = ProductServingQuantity.formatted(
                min(max(current + delta, ProductServingQuantity.allowedRange.lowerBound), ProductServingQuantity.allowedRange.upperBound)
            )
        } label: {
            Image(systemName: symbol)
                .frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LeafyTheme.green)
    }

    private func nutritionMetric(_ title: String, code: String, unit: String) -> some View {
        let value = nutrientDrafts.first(where: { $0.code == code })?.amount ?? "—"
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(LeafyTypography.caption).foregroundStyle(.secondary)
            Text("\(value) \(unit)")
                .font(LeafyTypography.subheadlineSemibold)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var contributionSubmitButton: some View {
        Button { Task { await submit() } } label: {
            HStack(spacing: LeafySpacing.small) {
                if app.isCatalogContributionLoading {
                    ProgressView().tint(.white)
                }
                Text(app.isCatalogContributionLoading
                     ? "Submitting…"
                     : (intent == .log ? "Submit and Log Food" : "Submit Product"))
            }
        }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit || (intent == .log && validServingCount == nil) || app.isCatalogContributionLoading)
            .opacity(canSubmit && (intent != .log || validServingCount != nil) ? 1 : 0.45)
            .leafyDetachedBottomControl()
            .accessibilityIdentifier("submitProductContributionButton")
    }

    private func contributionSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(LeafyTypography.captionSemibold)
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.bottom, LeafySpacing.small)
            content()
        }
    }

    private func contributionTextField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .frame(minHeight: LeafyTheme.rowMinHeight)
            .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
    }

    private func contributionValueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .frame(minHeight: LeafyTheme.rowMinHeight)
        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
    }

    private var needsFactsCloseup: Bool { contribution?.extractedFields?.evidence?.nutritionFactsLegible == false }
    private var needsIngredientsCloseup: Bool { contribution?.extractedFields?.evidence?.ingredientsLegible == false }
    private func hasPhoto(_ target: CatalogPhotoTarget) -> Bool { photos[target] != nil || contribution?.assets?.contains(where: { $0.assetKind == target.rawValue }) == true }
    private var hasRequiredPhotoSet: Bool {
        hasPhoto(.front) && ((hasPhoto(.nutritionFacts) && hasPhoto(.ingredients)) || hasPhoto(.backLabel))
    }
    private var readyToReadPackage: Bool {
        guard hasRequiredPhotoSet else { return false }
        let requested = contribution?.extractionDiagnostics?.requestedAssets ?? []
        return requested.allSatisfy { rawValue in
            guard let target = CatalogPhotoTarget(rawValue: rawValue) else { return true }
            return photos[target] != nil
        }
    }
    private func needsRetake(_ target: CatalogPhotoTarget) -> Bool {
        contribution?.extractionDiagnostics?.requestedAssets.contains(target.rawValue) == true
    }
    private func photoInstruction(_ target: CatalogPhotoTarget) -> String {
        switch target {
        case .front: "Show the complete product name and brand"
        case .nutritionFacts: "Fill the frame and keep every number sharp"
        case .ingredients: "Show the full ingredients and allergen statement"
        case .backLabel: "Make all small print readable"
        }
    }
    private var validServingCount: Double? { ProductServingQuantity.count(from: servingCount) }
    private var consumedGrams: Double { fields.servingGrams * (validServingCount ?? 0) }
    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
    private var allergensBinding: Binding<String> { Binding(get: { fields.allergens.joined(separator: ", ") }, set: { fields.allergens = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }) }
    private var canSubmit: Bool {
        !fields.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (fields.brandNotShown || !fields.brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        !fields.ingredients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fields.servingGrams > 0 &&
        !fields.servingDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        nutrientDrafts.count == LabelNutrientDefinition.standard.count && nutrientDrafts.allSatisfy { Double($0.amount) != nil }
    }

    private func start() async {
        guard contribution == nil, acceptedDetail == nil else { return }
        guard let response = await app.startCatalogContribution(barcode: barcode) else { return }
        if let id = response.foodVersionID { acceptedDetail = await app.loadProductDetail(foodVersionID: id); return }
        guard let contribution = response.contribution else { return }
        configure(contribution)
        hasUnsavedDraft = true
    }

    private func load(_ item: PhotosPickerItem?, target: CatalogPhotoTarget) async {
        guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        save(image, target: target)
    }

    private func save(_ image: UIImage, target: CatalogPhotoTarget) {
        guard let data = image.leafyMealJPEG(maxDimension: 3000, maxBytes: 8 * 1024 * 1024) else {
            app.catalogContributionErrorMessage = "Choose a clearer label photo smaller than 8 MB."; return
        }
        photos[target] = data; previews[target] = image; hasUnsavedDraft = true
    }

    private func analyze() async -> Bool {
        guard var current = contribution else { return false }
        let pendingPhotos = photos
        for target in CatalogPhotoTarget.allCases where pendingPhotos[target] != nil {
            guard let data = pendingPhotos[target],
                  let updated = await app.uploadCatalogPhoto(data, contributionID: current.id, assetKind: target.rawValue)
            else { return false }
            guard !Task.isCancelled else { return false }
            current = updated
        }
        guard let extracted = await app.extractCatalogContribution(id: current.id) else { return false }
        guard !Task.isCancelled else { return false }
        for target in pendingPhotos.keys where photos[target] == pendingPhotos[target] {
            photos[target] = nil
        }
        configure(extracted)
        return true
    }

    private func beginAnalysis() {
        analysisTask?.cancel()
        waitStartedAt = .now
        waitEstimateSeconds = CatalogContributionWaitEstimator.estimatedSeconds()
        showingAnalysisWait = true
        analysisTask = Task { @MainActor in
            let startedAt = Date.now
            let succeeded = await analyze()
            guard !Task.isCancelled else { return }
            if succeeded {
                CatalogContributionWaitEstimator.record(Date.now.timeIntervalSince(startedAt))
            }
            showingAnalysisWait = false
            analysisTask = nil
        }
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        showingAnalysisWait = false
    }

    private func configure(_ value: CatalogContribution) {
        contribution = value
        fields = value.confirmedFields ?? value.extractedFields ?? .empty
        let values = value.nutrients?.isEmpty == false ? value.nutrients! : value.extractedFields?.nutrients ?? []
        nutrientDrafts = LabelNutrientDefinition.standard.map { definition in
            let found = values.first { $0.code == definition.code }
            return LabelNutrientDraft(code: definition.code, title: definition.title, unit: definition.unit, amount: found.map { $0.amountPerServing.formatted(.number.precision(.fractionLength(0...3))) } ?? "", dailyValue: found?.percentDailyValue.map { $0.formatted() } ?? "", confidence: found?.confidence ?? 1)
        }
        if grams <= 0 { grams = fields.servingGrams }
        if value.status == .needsReview {
            isEditingExtractedFields = true
            step = .review
        } else if value.extractionDiagnostics?.status == .needsPhotos {
            isEditingExtractedFields = false
            step = .capture
        } else if let extracted = value.extractedFields,
                  !extracted.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  extracted.servingGrams > 0,
                  extracted.nutrients?.isEmpty == false {
            isEditingExtractedFields = false
            step = .review
        } else {
            isEditingExtractedFields = false
            step = .capture
        }
    }

    private func submit() async {
        guard let contribution else { return }
        let nutrients = nutrientDrafts.compactMap { draft -> CatalogContributionNutrient? in
            guard let amount = Double(draft.amount) else { return nil }
            return .init(code: draft.code, amountPerServing: amount, unit: draft.unit == "Cal" ? "kcal" : draft.unit, percentDailyValue: Double(draft.dailyValue), confidence: draft.confidence)
        }
        guard let result = await app.submitCatalogContribution(id: contribution.id, fields: fields, nutrients: nutrients) else { return }
        configure(result.contribution)
        if result.outcome == "needs_review" { step = .review; return }
        if intent == .log {
            let logged: Bool
            if let id = result.foodVersionID, let detail = await app.loadProductDetail(foodVersionID: id) {
                logged = await app.logProduct(detail, grams: consumedGrams, consumedAt: consumedAt, mealType: mealType)
            } else {
                logged = await app.logCatalogContribution(result.contribution, grams: consumedGrams, consumedAt: consumedAt, mealType: mealType)
            }
            if logged { hasUnsavedDraft = false; onCompleted?(); dismiss() }
        } else if let id = result.foodVersionID {
            acceptedDetail = await app.loadProductDetail(foodVersionID: id)
        } else { hasUnsavedDraft = false; step = .submitted }
    }
}

extension CatalogPhotoTarget: CaseIterable {}

private struct CatalogPhotoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LeafyTypography.subheadline)
            .foregroundStyle(LeafyTheme.green)
            .padding(.vertical, 13)
            .background(LeafyTheme.green.opacity(configuration.isPressed ? 0.16 : 0.09), in: .rect(cornerRadius: 14))
    }
}
