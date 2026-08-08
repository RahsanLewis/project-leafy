import SwiftUI

struct AskLeafyView: View {
    @Environment(AppModel.self) private var app
    @State private var draft = ""
    @State private var showingHistory = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if app.chatMessages.isEmpty { emptyState }
                    ForEach(app.chatMessages) { message in
                        ChatBubble(message: message) {
                            if let description = message.suggestedLogDescription {
                                app.presentMealLogger(description: description)
                            }
                        } onItemChange: { itemID, name, portion, calories in
                            app.updateChatMealItem(
                                messageID: message.id, itemID: itemID,
                                name: name, portion: portion, calories: calories
                            )
                        } onItemRemove: { itemID in
                            app.removeChatMealItem(messageID: message.id, itemID: itemID)
                        } onLogMeal: {
                            Task { await app.confirmChatMeal(messageID: message.id) }
                        }
                        .id(message.id)
                    }
                    if app.isChatLoading { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                    if let error = app.chatErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.subheadline).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, LeafyTheme.pageInset).padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: app.chatMessages.count) { _, _ in
                if let id = app.chatMessages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
        .background(LeafyTheme.canvas)
        .navigationTitle("Ask Leafy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    focused = false
                    showingHistory = true
                } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("Chat history")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    focused = false
                    app.startNewChat()
                } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
                    .accessibilityIdentifier("dismissAskLeafyKeyboardButton")
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .sheet(isPresented: $showingHistory) { history }
        .task { if app.chatThreads.isEmpty { await app.loadChatThreads() } }
        .onDisappear { focused = false }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "leaf.fill").font(.system(size: 40)).foregroundStyle(LeafyTheme.green)
            Text("Nutrition guidance that knows your plan")
                .font(LeafyTypography.title2)
            Text("Ask about meals, calories, protein, or what fits your day. Leafy uses your plan and recent logs—not sensitive profile details—to personalize answers.")
                .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            ForEach(["What should I eat for dinner?", "How much protein do I have left?", "How many calories are in a turkey sandwich?"], id: \.self) { prompt in
                Button(prompt) { draft = prompt; send() }
                    .buttonStyle(.bordered).tint(LeafyTheme.green)
            }
            Text("General wellness guidance only—not medical advice.")
                .font(LeafyTypography.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 30)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask a nutrition question", text: $draft, axis: .vertical)
                .lineLimit(1...5).focused($focused).padding(12)
                .background(LeafyTheme.surface, in: .rect(cornerRadius: 18))
                .accessibilityIdentifier("askLeafyField")
            Button { send() } label: {
                Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(LeafyTheme.green, in: .circle)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.isChatLoading)
            .accessibilityLabel("Send")
        }
        .leafyDetachedBottomControl()
    }

    private var history: some View {
        NavigationStack {
            List {
                if app.chatThreads.isEmpty { ContentUnavailableView("No saved chats", systemImage: "bubble.left.and.bubble.right") }
                ForEach(app.chatThreads) { thread in
                    Button {
                        showingHistory = false
                        Task { await app.openChatThread(thread) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title).font(LeafyTypography.headline).foregroundStyle(.primary)
                            Text(thread.lastMessageAt, style: .relative).font(LeafyTypography.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("Delete", role: .destructive) { Task { await app.deleteChatThread(thread) } } }
                }
            }.navigationTitle("Chat history").toolbar { Button("Done") { showingHistory = false } }
        }
    }

    private func send() {
        let text = draft
        draft = ""
        focused = false
        Task { await app.sendChatMessage(text) }
    }
}

private struct ChatBubble: View {
    let message: NutritionChatMessage
    let onReviewAndLog: () -> Void
    let onItemChange: (UUID, String, String, Int) -> Void
    let onItemRemove: (UUID) -> Void
    let onLogMeal: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 9) {
            Text(message.content)
                .font(LeafyTypography.body)
                .padding(.horizontal, 15).padding(.vertical, 12)
                .background(message.role == "user" ? LeafyTheme.green : LeafyTheme.surface, in: .rect(cornerRadius: 18))
                .foregroundStyle(message.role == "user" ? .white : .primary)
            if !message.sources.isEmpty {
                Text(message.sources.map(\.label).joined(separator: " · "))
                    .font(LeafyTypography.caption).foregroundStyle(.secondary)
            }
            if message.suggestedLogDescription != nil {
                Button("Review and log") { onReviewAndLog() }
                    .font(LeafyTypography.headline).foregroundStyle(LeafyTheme.green)
                    .accessibilityIdentifier("reviewAndLogButton")
            }
            if let suggestion = message.mealSuggestion {
                ChatMealSuggestionView(
                    suggestion: suggestion,
                    isLogging: app.chatMealLoggingMessageID == message.id,
                    onItemChange: onItemChange,
                    onItemRemove: onItemRemove,
                    onLogMeal: onLogMeal
                )
            }
        }.frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
    }
}

private struct ChatMealSuggestionView: View {
    let suggestion: NutritionChatMealSuggestion
    let isLogging: Bool
    let onItemChange: (UUID, String, String, Int) -> Void
    let onItemRemove: (UUID) -> Void
    let onLogMeal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated meal")
                        .font(LeafyTypography.headline)
                        .accessibilityIdentifier("chatMealSuggestion")
                    Text("Review before logging")
                        .font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(suggestion.reviewedTotal) Cal")
                    .font(LeafyTypography.title3).monospacedDigit()
            }

            VStack(spacing: 0) {
                ForEach(Array(suggestion.items.enumerated()), id: \.element.id) { index, item in
                    ChatMealItemRow(item: item, onChange: onItemChange) {
                        onItemRemove(item.id)
                    }
                    if index < suggestion.items.count - 1 {
                        Divider().overlay(LeafyTheme.hairline)
                    }
                }
            }

            Text("Estimated range \(suggestion.calorieLow)–\(suggestion.calorieHigh) Cal")
                .font(LeafyTypography.caption).foregroundStyle(.secondary)

            switch suggestion.status {
            case .ready:
                Button(action: onLogMeal) {
                    if isLogging { ProgressView().tint(.white) }
                    else { Text("Log meal · \(suggestion.reviewedTotal) Cal") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLogging || suggestion.items.isEmpty)
                .accessibilityIdentifier("logChatMealButton")
            case .logged:
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .font(LeafyTypography.headline).foregroundStyle(LeafyTheme.green)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .accessibilityIdentifier("chatMealLoggedLabel")
            case .unavailable:
                Label("This estimate is no longer available", systemImage: "clock.badge.exclamationmark")
                    .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            }

            Text("AI estimate for general wellness. Portions and nutrition may be inaccurate.")
                .font(LeafyTypography.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(LeafyTheme.surface, in: .rect(cornerRadius: 20))
    }
}

private struct ChatMealItemRow: View {
    let item: MealEstimateItem
    let onChange: (UUID, String, String, Int) -> Void
    let onRemove: () -> Void
    @State private var name: String
    @State private var portion: String
    @State private var calories: String

    init(
        item: MealEstimateItem,
        onChange: @escaping (UUID, String, String, Int) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.item = item
        self.onChange = onChange
        self.onRemove = onRemove
        _name = State(initialValue: item.name)
        _portion = State(initialValue: item.portion)
        _calories = State(initialValue: String(item.calories))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Food", text: $name).font(LeafyTypography.headline)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Remove \(name)")
            }
            TextField("Portion", text: $portion)
                .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                TextField("Calories", text: $calories)
                    .keyboardType(.numberPad)
                    .font(LeafyTypography.title3).monospacedDigit()
                Text("Cal").font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(item.calorieLow)–\(item.calorieHigh)")
                    .font(LeafyTypography.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, LeafySpacing.compact)
        .onChange(of: name) { _, _ in publish() }
        .onChange(of: portion) { _, _ in publish() }
        .onChange(of: calories) { _, _ in publish() }
    }

    private func publish() {
        onChange(item.id, name, portion, Int(calories) ?? 0)
    }
}
