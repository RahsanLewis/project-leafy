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
    @State private var showingCamera = false
    @State private var mealDate = Date.now
    @State private var mealType: MealType = .unspecified
    @State private var followUpAnswer = ""
    @State private var analysisTask: Task<Void, Never>?
    @State private var showingAnalysisWait = false
    @State private var waitStartedAt = Date.now
    @State private var waitEstimateSeconds = 12.0
    @State private var showingMealDetails = false
    @FocusState private var descriptionIsFocused: Bool

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
                if let estimate = app.mealEstimate {
                    review(estimate)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    composer
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, LeafySpacing.medium)
            .padding(.bottom, 120)
        }
        .background(LeafyTheme.canvas)
        .animation(LeafyMotion.content, value: app.mealEstimate != nil)
        .navigationTitle(embedded ? "Log Food" : (app.mealEstimate == nil ? "AI Meal" : "Review estimate"))
        .navigationBarTitleDisplayMode(embedded ? .inline : .large)
        .safeAreaInset(edge: .bottom) {
            if app.mealEstimate == nil || app.mealEstimate?.status == .ready {
                primaryAction
                    .leafyDetachedBottomControl()
            }
        }
        .sheet(isPresented: $showingCamera) {
            MealCameraPicker { image in setImage(image) }
                .ignoresSafeArea()
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
        .onAppear { updateDraftState() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { descriptionIsFocused = false }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("Tell Leafy what you ate")
                    .font(LeafyTypography.title2)
                Text("Include portions, sauces, drinks, and anything else you remember.")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("DESCRIPTION")
                    .font(LeafyTypography.captionSemibold)
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                TextEditor(text: $description)
                    .focused($descriptionIsFocused)
                    .frame(minHeight: 132)
                    .padding(.vertical, LeafySpacing.small)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Example: Two chicken tacos with cheese, salsa, and a small horchata")
                                .font(LeafyTypography.body)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 16)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(descriptionIsFocused ? LeafyTheme.green : LeafyTheme.hairline)
                            .frame(height: descriptionIsFocused ? 2 : 1)
                            .animation(LeafyMotion.state, value: descriptionIsFocused)
                    }
                    .accessibilityIdentifier("aiMealDescription")

                photoInput
            }

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

            Text("AI estimates can be inaccurate. You’ll review every item before it is added to your calorie budget.")
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
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    HStack {
                        Label("Add a photo", systemImage: "camera")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
                    .frame(minHeight: LeafyTheme.rowMinHeight)
                    .contentShape(.rect)
                }
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
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
                Text("Estimated meal")
                    .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                Text("\(estimate.reviewedTotal) Cal")
                    .font(LeafyTypography.metric(42, extraBold: true))
                Text("Likely \(estimate.calorieLow)–\(estimate.calorieHigh) Cal")
                    .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            }

            if let followUp = estimate.followUp, estimate.status == .needsClarification {
                VStack(alignment: .leading, spacing: 14) {
                    Label("One detail would help", systemImage: "questionmark.bubble.fill")
                        .font(LeafyTypography.headline).foregroundStyle(LeafyTheme.green)
                    Text(followUp.question).font(LeafyTypography.title3)
                    TextField("Your answer", text: $followUpAnswer, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(.vertical, LeafySpacing.small)
                        .overlay(alignment: .bottom) { Divider().overlay(LeafyTheme.hairline) }
                    HStack {
                        Button("Skip") { refineEstimate(answer: nil, skip: true) }
                        Spacer()
                        Button("Update estimate") {
                            let answer = followUpAnswer
                            followUpAnswer = ""
                            refineEstimate(answer: answer, skip: false)
                        }
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(LeafyTheme.green)
                        .disabled(followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.leading, LeafySpacing.medium)
                .padding(.vertical, LeafySpacing.small)
                .overlay(alignment: .leading) {
                    Rectangle().fill(LeafyTheme.green).frame(width: 3)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("ITEMS").font(LeafyTypography.caption).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(estimate.items.enumerated()), id: \.element.id) { index, item in
                        MealEstimateItemCard(item: item) { name, portion, calories in
                            app.updateMealEstimateItem(
                                id: item.id,
                                name: name,
                                portion: portion,
                                calories: calories
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

            Text("This is an AI estimate for general wellness, not a measurement or medical advice.")
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

    private var canAnalyze: Bool {
        photoData != nil || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder private var primaryAction: some View {
        if let estimate = app.mealEstimate, estimate.status == .ready {
            Button { confirm() } label: {
                if app.isMealEstimateLoading { ProgressView().tint(.white) }
                else { Text("Log \(estimate.reviewedTotal) calories") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(estimate.items.isEmpty || app.isMealEstimateLoading)
            .accessibilityIdentifier("confirmMealEstimateButton")
        } else if app.mealEstimate == nil {
            Button { analyze() } label: {
                if app.isMealEstimateLoading { ProgressView().tint(.white) }
                else { Text("Estimate calories") }
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
        let inputDescription = description
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
        followUpAnswer = ""
        beginAnalysis(hasPhoto: photoData != nil) {
            await app.answerMealFollowUp(answer, skip: skip)
        }
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
        followUpAnswer = ""; mealDate = Self.logDate(logDay, usingTimeFrom: .now); mealType = .unspecified
    }

    private func updateDraftState() {
        hasUnsavedDraft = photoData != nil || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    let onChange: (String, String, Int) -> Void
    let onRemove: () -> Void
    @State private var name: String
    @State private var portion: String
    @State private var calories: String

    init(item: MealEstimateItem, onChange: @escaping (String, String, Int) -> Void, onRemove: @escaping () -> Void) {
        self.item = item; self.onChange = onChange; self.onRemove = onRemove
        _name = State(initialValue: item.name); _portion = State(initialValue: item.portion)
        _calories = State(initialValue: String(item.calories))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                TextField("Food", text: $name).font(LeafyTypography.headline)
                Button(role: .destructive, action: onRemove) { Image(systemName: "trash") }
                    .accessibilityLabel("Remove \(name)")
            }
            TextField("Estimated portion", text: $portion)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                TextField("Calories", text: $calories)
                    .keyboardType(.numberPad).font(LeafyTypography.title2).frame(maxWidth: 110)
                Text("Cal").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.confidenceLabel).font(LeafyTypography.captionSemibold)
                    Text("Range \(item.calorieLow)–\(item.calorieHigh)").font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
            }
            if let nutrients = item.nutrients {
                HStack(spacing: LeafySpacing.large) {
                    macro("Protein", code: "protein_g", nutrients: nutrients)
                    macro("Carbs", code: "carbohydrate_g", nutrients: nutrients)
                    macro("Fat", code: "fat_g", nutrients: nutrients)
                }
                .padding(.top, LeafySpacing.xSmall)
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
    }

    private func publish() { onChange(name, portion, Int(calories) ?? 0) }

    private func macro(_ title: String, code: String, nutrients: [NutrientAmountInput]) -> some View {
        let value = nutrients.first { $0.code == code }?.amount ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(LeafyTypography.caption).foregroundStyle(.secondary)
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(LeafyTypography.subheadlineSemibold).monospacedDigit()
        }
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
