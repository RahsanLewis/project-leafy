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
            .onChange(of: app.chatMessages.count) { _, _ in
                if let id = app.chatMessages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ask Leafy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("Chat history")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.startNewChat() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .sheet(isPresented: $showingHistory) { history }
        .task { if app.chatThreads.isEmpty { await app.loadChatThreads() } }
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
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                .accessibilityIdentifier("askLeafyField")
            Button { send() } label: {
                Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(LeafyTheme.green, in: .circle)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.isChatLoading)
            .accessibilityLabel("Send")
        }.padding(.horizontal, 16).padding(.vertical, 10).background(.regularMaterial)
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
    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 9) {
            Text(message.content)
                .font(LeafyTypography.body)
                .padding(.horizontal, 15).padding(.vertical, 12)
                .background(message.role == "user" ? LeafyTheme.green : Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
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
        }.frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
    }
}
