import SwiftUI

struct AskLeafyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var retryID: UUID?
    @State private var responseTask: Task<Void, Never>?
    @State private var showingHistory = false
    @State private var reviewDraft: ChatMealReviewDraft?
    @State private var confirmingNewChat = false
    @FocusState private var focused: Bool

    private let starters = [
        "What should I eat for dinner?",
        "How much protein do I have left?",
        "How many calories are in a turkey sandwich?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            conversation
            composer
        }
        .background(LeafyTheme.canvas)
        .navigationTitle("Ask Leafy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { focused = false; showingHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Conversations")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { requestNewChat() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
            }
        }
        .sheet(isPresented: $showingHistory) { ConversationHistoryView(isPresented: $showingHistory) }
        .sheet(item: $reviewDraft) { draft in
            ChatMealReviewView(draft: draft) { updated in
                if await app.confirmChatMeal(updated) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    UIAccessibility.post(notification: .announcement, argument: "Meal logged")
                    reviewDraft = nil
                }
            }
        }
        .confirmationDialog("Start a new chat?", isPresented: $confirmingNewChat) {
            Button("Start New Chat", role: .destructive) { startNewChat() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your current conversation stays in Conversations.") }
        .task { if app.chatThreads.isEmpty { await app.loadChatThreads() } }
        .onDisappear { focused = false; responseTask?.cancel() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LeafySpacing.large) {
                    if app.chatMessages.isEmpty { emptyState }
                    ForEach(app.chatMessages) { message in
                        ChatMessageView(
                            message: message,
                            onReview: { reviewDraft = app.chatMealReviewDraft(messageID: message.id) },
                            onLogDescription: {
                                if let description = message.suggestedLogDescription {
                                    app.presentMealLogger(description: description)
                                }
                            }
                        )
                        .id(message.id)
                    }
                    if app.isChatLoading { thinkingRow }
                    if let error = app.chatErrorMessage { errorRow(error) }
                    Color.clear.frame(height: 1).id("conversationBottom")
                }
                .padding(.horizontal, LeafyTheme.pageInset)
                .padding(.vertical, LeafySpacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { focused = false })
            .onChange(of: app.chatMessages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: app.isChatLoading) { _, _ in scrollToBottom(proxy) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text("Nutrition guidance, made personal")
                    .font(LeafyTypography.title2)
                Text("Ask about meals, calories, protein, or what fits your day.")
                    .font(LeafyTypography.body).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(starters.enumerated()), id: \.element) { index, prompt in
                    Button { send(prompt) } label: {
                        HStack {
                            Text(prompt).font(LeafyTypography.bodyMedium).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(LeafyTheme.green)
                        }
                        .frame(minHeight: LeafyTheme.rowMinHeight)
                    }
                    .buttonStyle(.plain)
                    if index < starters.count - 1 { Divider().overlay(LeafyTheme.hairline) }
                }
            }
            Text("General wellness guidance only—not medical advice.")
                .font(LeafyTypography.footnote).foregroundStyle(.secondary)
                .padding(.top, LeafySpacing.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, LeafySpacing.large)
    }

    private var thinkingRow: some View {
        HStack(spacing: LeafySpacing.compact) {
            ProgressView().controlSize(.small).tint(LeafyTheme.green)
            Text("Leafy is thinking…").font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button("Stop") { cancelResponse() }
                .font(LeafyTypography.subheadlineSemibold).foregroundStyle(LeafyTheme.green)
                .accessibilityIdentifier("stopAskLeafyButton")
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func errorRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(LeafyTypography.subheadline).foregroundStyle(.orange)
            if retryID != nil && !draft.isEmpty {
                Button("Retry") { send(draft, reusing: retryID) }
                    .font(LeafyTypography.subheadlineSemibold).foregroundStyle(LeafyTheme.green)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: LeafySpacing.small) {
            TextField("Ask a nutrition question", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(LeafyTheme.surface, in: .rect(cornerRadius: LeafyRadius.prominent))
                .accessibilityIdentifier("askLeafyField")
            Button { send(draft, reusing: retryID) } label: {
                Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(LeafyTheme.green, in: .circle)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.isChatLoading)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Send")
        }
        .leafyDetachedBottomControl()
    }

    private func send(_ text: String, reusing id: UUID? = nil) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !app.isChatLoading else { return }
        let clientID = id ?? UUID()
        draft = ""; retryID = clientID; focused = false; app.chatErrorMessage = nil
        UISelectionFeedbackGenerator().selectionChanged()
        responseTask = Task { @MainActor in
            let succeeded = await app.sendChatMessage(message, clientMessageID: clientID)
            guard !Task.isCancelled else { return }
            if succeeded {
                retryID = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                UIAccessibility.post(notification: .announcement, argument: "Leafy answered")
            } else {
                draft = message
            }
            responseTask = nil
        }
    }

    private func cancelResponse() {
        let text = app.pendingChatText ?? ""
        responseTask?.cancel(); responseTask = nil
        app.chatMessages.removeAll { $0.id == app.pendingChatClientMessageID }
        app.isChatLoading = false
        draft = text
    }

    private func requestNewChat() {
        focused = false
        if !draft.isEmpty || app.isChatLoading { confirmingNewChat = true }
        else { startNewChat() }
    }

    private func startNewChat() {
        responseTask?.cancel(); responseTask = nil; draft = ""; retryID = nil
        app.startNewChat()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo("conversationBottom", anchor: .bottom) }
        else { withAnimation(LeafyMotion.content) { proxy.scrollTo("conversationBottom", anchor: .bottom) } }
    }
}

private struct ChatMessageView: View {
    let message: NutritionChatMessage
    let onReview: () -> Void
    let onLogDescription: () -> Void

    var body: some View {
        if message.role == "user" {
            Text(message.content)
                .font(LeafyTypography.body)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(LeafyTheme.green, in: .rect(cornerRadius: 18))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 52)
        } else {
            VStack(alignment: .leading, spacing: LeafySpacing.compact) {
                Text(.init(message.content))
                    .font(LeafyTypography.body)
                    .textSelection(.enabled)
                if !message.sources.isEmpty {
                    Text(message.sources.map(\.label).joined(separator: " · "))
                        .font(LeafyTypography.caption).foregroundStyle(.secondary)
                }
                if message.suggestedLogDescription != nil {
                    Button("Review and log") { onLogDescription() }
                        .font(LeafyTypography.subheadlineSemibold).foregroundStyle(LeafyTheme.green)
                }
                if let suggestion = message.mealSuggestion {
                    ChatMealSummaryView(suggestion: suggestion, onReview: onReview)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChatMealSummaryView: View {
    let suggestion: NutritionChatMealSuggestion
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            Divider().overlay(LeafyTheme.hairline)
            HStack(alignment: .firstTextBaseline) {
                Text(suggestion.status == .logged ? "Meal logged" : "Estimated meal")
                    .font(LeafyTypography.headline)
                    .accessibilityIdentifier("chatMealSuggestion")
                Spacer()
                Text("\(suggestion.reviewedTotal) Cal")
                    .font(LeafyTypography.title3).monospacedDigit()
            }
            ForEach(suggestion.items) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(LeafyTypography.bodyMedium)
                        if !item.portion.isEmpty { Text(item.portion).font(LeafyTypography.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text("\(item.calories) Cal").font(LeafyTypography.subheadline).monospacedDigit()
                }
            }
            Text("Estimated range \(suggestion.calorieLow)–\(suggestion.calorieHigh) Cal")
                .font(LeafyTypography.caption).foregroundStyle(.secondary)
            if suggestion.status == .ready {
                Button("Review and log") { onReview() }
                    .font(LeafyTypography.headline).foregroundStyle(LeafyTheme.green)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("reviewChatMealButton")
            } else if suggestion.status == .logged {
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .font(LeafyTypography.headline).foregroundStyle(LeafyTheme.green)
                    .accessibilityIdentifier("chatMealLoggedLabel")
            }
        }
    }
}

private struct ChatMealReviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ChatMealReviewDraft
    let onConfirm: (ChatMealReviewDraft) async -> Void

    init(draft: ChatMealReviewDraft, onConfirm: @escaping (ChatMealReviewDraft) async -> Void) {
        _draft = State(initialValue: draft)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        Text("\(draft.totalCalories) Cal").font(LeafyTypography.metric(42)).monospacedDigit()
                        Text("Review portions and calories before adding this meal.")
                            .font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach($draft.items) { $item in
                            ChatMealReviewRow(item: $item) { draft.items.removeAll { $0.id == item.id } }
                            Divider().overlay(LeafyTheme.hairline)
                        }
                        Button { draft.items.append(ChatMealReviewItem()) } label: {
                            Label("Add another food", systemImage: "plus")
                                .font(LeafyTypography.headline).frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: LeafyTheme.rowMinHeight)
                        }
                    }
                    VStack(spacing: 0) {
                        DatePicker("Date", selection: $draft.consumedAt, displayedComponents: .date)
                            .frame(minHeight: LeafyTheme.rowMinHeight)
                        Divider().overlay(LeafyTheme.hairline)
                        DatePicker("Time", selection: $draft.consumedAt, displayedComponents: .hourAndMinute)
                            .frame(minHeight: LeafyTheme.rowMinHeight)
                    }
                    if let error = app.chatErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("chatMealReviewError")
                    }
                }
                .padding(.horizontal, LeafyTheme.pageInset).padding(.top, LeafySpacing.medium).padding(.bottom, 112)
            }
            .background(LeafyTheme.canvas)
            .navigationTitle("Review meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Log meal · \(draft.totalCalories) Cal") { Task { await onConfirm(draft) } }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!draft.isValid || app.chatMealLoggingMessageID != nil)
                    .opacity(draft.isValid ? 1 : 0.45).leafyDetachedBottomControl()
                    .accessibilityIdentifier("logChatMealButton")
            }
            .interactiveDismissDisabled(app.chatMealLoggingMessageID != nil)
        }
    }
}

private struct ChatMealReviewRow: View {
    @Binding var item: ChatMealReviewItem
    let onRemove: () -> Void
    private var calories: Binding<String> {
        Binding(get: { item.calories == 0 ? "" : String(item.calories) }, set: { item.calories = Int($0) ?? 0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            HStack { TextField("Food", text: $item.name).font(LeafyTypography.headline); Button(role: .destructive, action: onRemove) { Image(systemName: "trash") } }
            TextField("Portion", text: $item.portion).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            HStack { TextField("Calories", text: calories).keyboardType(.numberPad).font(LeafyTypography.title3); Text("Cal").foregroundStyle(.secondary); Spacer() }
        }.padding(.vertical, LeafySpacing.compact)
    }
}

private struct ConversationHistoryView: View {
    @Environment(AppModel.self) private var app
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var deleting: NutritionChatThread?
    private var threads: [NutritionChatThread] {
        query.isEmpty ? app.chatThreads : app.chatThreads.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                if threads.isEmpty { ContentUnavailableView(query.isEmpty ? "No conversations" : "No matches", systemImage: "bubble.left.and.bubble.right") }
                ForEach(threads) { thread in
                    Button {
                        Task { await app.openChatThread(thread); if app.chatErrorMessage == nil { isPresented = false } }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title).font(LeafyTypography.headline).foregroundStyle(.primary)
                            Text(thread.lastMessageAt, style: .relative).font(LeafyTypography.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: LeafyTheme.rowMinHeight, alignment: .leading)
                    }.swipeActions { Button("Delete", role: .destructive) { deleting = thread } }
                }.leafyBorderlessRows()
                if let error = app.chatErrorMessage { Text(error).font(LeafyTypography.subheadline).foregroundStyle(.orange).leafyBorderlessRows(separators: false) }
            }
            .leafyBorderlessList().searchable(text: $query, prompt: "Search conversations")
            .navigationTitle("Conversations")
            .toolbar { Button("Done") { isPresented = false } }
            .confirmationDialog("Delete this conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete Conversation", role: .destructive) { if let deleting { Task { await app.deleteChatThread(deleting) }; self.deleting = nil } }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
        }
    }
}
