import PhotosUI
import SwiftUI
import UIKit

struct AIMealView: View {
    @Environment(AppModel.self) private var app
    let onSaved: () -> Void
    @State private var description = ""
    @State private var voiceTranscript = ""
    @State private var selectedImage: UIImage?
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var mealDate = Date.now
    @State private var mealType: MealType = .unspecified
    @State private var followUpAnswer = ""
    @State private var recorder = MealVoiceRecorder()
    @FocusState private var descriptionIsFocused: Bool

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
        .navigationTitle(app.mealEstimate == nil ? "AI Meal" : "Review estimate")
        .navigationBarTitleDisplayMode(.large)
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
        .onDisappear { if recorder.isRecording { recorder.cancel() } }
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
                Text("Use a photo, type a description, or speak. Combining details gives Leafy a better estimate.")
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: selectedImage)
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 240)
                        .clipShape(.rect(cornerRadius: 22))
                    Button { clearPhoto() } label: {
                        Image(systemName: "xmark").font(.headline)
                            .padding(10).background(.ultraThinMaterial, in: .circle)
                    }
                    .padding(12)
                    .accessibilityLabel("Remove meal photo")
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.system(size: 46)).foregroundStyle(LeafyTheme.green)
                    Text("Add a meal photo")
                        .font(LeafyTypography.headline)
                    Text("Try to include the full plate in good lighting.")
                        .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 220)
                .background(LeafyTheme.mint, in: .rect(cornerRadius: 22))
            }

            HStack(spacing: 12) {
                Button { showingCamera = true } label: {
                    Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(AIMealInputButtonStyle())
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(AIMealInputButtonStyle())
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("DESCRIPTION").font(LeafyTypography.caption).foregroundStyle(.secondary)
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

            voiceSection
            mealDetails

            if let message = recorder.errorMessage ?? app.mealEstimateErrorMessage {
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

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VOICE DESCRIPTION").font(LeafyTypography.caption).foregroundStyle(.secondary)
            Button {
                if recorder.isRecording {
                    if let url = recorder.stop() { transcribe(url) }
                } else {
                    Task { await recorder.start() }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2).foregroundStyle(recorder.isRecording ? .red : LeafyTheme.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recorder.isRecording ? "Stop recording" : app.isMealTranscribing ? "Transcribing…" : "Describe by voice")
                            .font(LeafyTypography.headline).foregroundStyle(.primary)
                        Text(recorder.isRecording ? "0:\(String(format: "%02d", recorder.elapsedSeconds)) of 1:00" : "Audio is deleted after transcription")
                            .font(LeafyTypography.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if app.isMealTranscribing { ProgressView() }
                }
                .padding(14).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(app.isMealTranscribing)

            if !voiceTranscript.isEmpty {
                TextField("Voice transcript", text: $voiceTranscript, axis: .vertical)
                    .lineLimit(2...5).padding(14)
                    .background(LeafyTheme.mint, in: .rect(cornerRadius: 16))
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
        photoData != nil || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !voiceTranscript.isEmpty
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

    private func transcribe(_ url: URL) {
        Task {
            if let transcript = await app.transcribeMealAudio(at: url) {
                voiceTranscript = transcript
            }
        }
    }

    private func analyze() {
        let inputDescription = description
        let transcript = voiceTranscript
        let photo = photoData
        let date = mealDate
        let type = mealType
        Task {
            _ = await app.analyzeMeal(
                description: inputDescription, voiceTranscript: transcript, photoData: photo,
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
        description = ""; voiceTranscript = ""; selectedImage = nil; photoData = nil; photoItem = nil
        followUpAnswer = ""; mealDate = .now; mealType = .unspecified; recorder.cancel()
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
        }
        .padding(.vertical, LeafySpacing.medium)
        .frame(minHeight: LeafyTheme.rowMinHeight)
        .onChange(of: name) { _, _ in publish() }
        .onChange(of: portion) { _, _ in publish() }
        .onChange(of: calories) { _, _ in publish() }
    }

    private func publish() { onChange(name, portion, Int(calories) ?? 0) }
}

private struct AIMealInputButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LeafyTypography.button).foregroundStyle(LeafyTheme.green).padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
