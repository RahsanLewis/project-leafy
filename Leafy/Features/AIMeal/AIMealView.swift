import PhotosUI
import SwiftUI
import UIKit

struct AIMealView: View {
    @Environment(AppModel.self) private var app
    let onSaved: () -> Void
    let embedded: Bool
    let logDay: Date
    @State private var description: String
    @State private var selectedImage: UIImage?
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var mealDate = Date.now
    @State private var mealType: MealType = .unspecified
    @State private var followUpAnswer = ""
    @FocusState private var descriptionIsFocused: Bool

    init(logDate: Date = .now, embedded: Bool = false, initialDescription: String = "", onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        self.embedded = embedded
        self.logDay = logDate
        _description = State(initialValue: initialDescription)
        _mealDate = State(initialValue: Self.logDate(logDate, usingTimeFrom: .now))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.large) {
                if let estimate = app.mealEstimate {
                    review(estimate)
                } else {
                    composer
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, LeafySpacing.medium)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(embedded ? "Log Food" : (app.mealEstimate == nil ? "AI Meal" : "Review estimate"))
        .navigationBarTitleDisplayMode(embedded ? .inline : .large)
        .sheet(isPresented: $showingCamera) {
            MealCameraPicker { image in setImage(image) }
                .ignoresSafeArea()
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { descriptionIsFocused = false }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tell Leafy what you ate")
                    .font(LeafyTypography.title2)
                Text("Describe the foods, portions, and extras you remember. Add a photo if it helps.")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT DID YOU EAT?").font(LeafyTypography.caption).foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .focused($descriptionIsFocused)
                    .frame(minHeight: 105)
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                    .overlay(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Example: Two chicken tacos with cheese, salsa, and a small horchata")
                                .foregroundStyle(.tertiary).padding(.horizontal, 17).padding(.vertical, 20)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier("aiMealDescription")
            }

            photoInput
            mealDetails

            if let message = app.mealEstimateErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(LeafyTypography.subheadline).foregroundStyle(.orange)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            }

            Text("AI estimates can be inaccurate. You’ll review every item before it is added to your calorie budget.")
                .font(LeafyTypography.footnote).foregroundStyle(.secondary)

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

    private var photoInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHOTO · OPTIONAL").font(LeafyTypography.caption).foregroundStyle(.secondary)
            if let selectedImage {
                HStack(spacing: 14) {
                    Image(uiImage: selectedImage).resizable().scaledToFill()
                        .frame(width: 82, height: 82).clipShape(.rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Photo added").font(LeafyTypography.headline)
                        Text("Used together with your description")
                            .font(LeafyTypography.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { clearPhoto() }
                }
            } else {
                HStack(spacing: 12) {
                    Button { showingCamera = true } label: {
                        Label("Take photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(AIMealInputButtonStyle())
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(AIMealInputButtonStyle())
                }
            }
        }
    }

    private var mealDetails: some View {
        VStack(spacing: 0) {
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases) { type in Text(type.label).tag(type) }
            }
            .padding(14)
            Divider().padding(.leading, 14)
            DatePicker("Date and time", selection: $mealDate, in: ...Date.now)
                .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
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
                Text("\(estimate.reviewedTotal) calories")
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
                        .lineLimit(2...4).padding(13)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    HStack {
                        Button("Skip") { Task { await app.answerMealFollowUp(nil, skip: true) } }
                        Spacer()
                        Button("Update estimate") {
                            let answer = followUpAnswer
                            followUpAnswer = ""
                            Task { await app.answerMealFollowUp(answer) }
                        }
                        .buttonStyle(.borderedProminent).tint(LeafyTheme.green)
                        .disabled(followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(18).background(LeafyTheme.mint, in: .rect(cornerRadius: 20))
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

            if estimate.status == .ready {
                Button { confirm() } label: {
                    if app.isMealEstimateLoading { ProgressView().tint(.white) }
                    else { Text("Log \(estimate.reviewedTotal) calories") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(estimate.items.isEmpty || app.isMealEstimateLoading)
                .accessibilityIdentifier("confirmMealEstimateButton")
            }

            Button("Start over", role: .destructive) {
                Task { await app.discardMealEstimate(); resetInputs() }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay { if app.isMealEstimateLoading { ProgressView().controlSize(.large) } }
    }

    private var canAnalyze: Bool {
        photoData != nil || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        Task {
            _ = await app.analyzeMeal(
                description: inputDescription, photoData: photo,
                consumedAt: date, localDate: date, mealType: type
            )
        }
    }

    private func confirm() {
        Task {
            if await app.confirmMealEstimate() {
                resetInputs()
                onSaved()
            }
        }
    }

    private func resetInputs() {
        description = ""; selectedImage = nil; photoData = nil; photoItem = nil
        followUpAnswer = ""; mealDate = Self.logDate(logDay, usingTimeFrom: .now); mealType = .unspecified
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

private struct AIMealInputButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LeafyTypography.button).foregroundStyle(LeafyTheme.green).padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
