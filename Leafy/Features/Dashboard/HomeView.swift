import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorEntry: FoodEntry?
    @State private var showingEditor = false
    @State private var showingLogChoices = false
    @State private var showingProductFinder = false

    var body: some View {
        List {
            Section {
                DateNavigator()
                    .listRowInsets(.init(
                        top: 0,
                        leading: 0,
                        bottom: LeafySpacing.small,
                        trailing: 0
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if let notice = app.planAdjustmentNotice {
                    AdaptiveTargetNotice(notice: notice)
                        .listRowInsets(.init(
                            top: LeafySpacing.small,
                            leading: LeafyTheme.pageInset,
                            bottom: 0,
                            trailing: LeafyTheme.pageInset
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if app.hasMorningCheckInReminder {
                    Button {
                        app.presentMorningCheckIn()
                    } label: {
                        HStack(spacing: LeafySpacing.medium) {
                            Image(systemName: "sunrise.fill")
                                .font(.title2)
                                .foregroundStyle(LeafyTheme.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Finish your morning check-in")
                                    .font(LeafyTypography.headline)
                                    .foregroundStyle(.primary)
                                Text("Review yesterday and add today’s weight.")
                                    .font(LeafyTypography.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(LeafySpacing.medium)
                        .background(LeafyTheme.mint, in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(
                        top: LeafySpacing.small,
                        leading: LeafyTheme.pageInset,
                        bottom: 0,
                        trailing: LeafyTheme.pageInset
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("morningCheckInReminder")
                }

                CalorieBudgetCard(summary: app.dailySummary)
                    .listRowInsets(.init(
                        top: LeafySpacing.small,
                        leading: 0,
                        bottom: 0,
                        trailing: 0
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .leafyBorderlessRows(separators: false)

            Section {
                if app.isDailyLoading && app.foodEntries.isEmpty {
                    HStack { Spacer(); ProgressView("Loading your day…"); Spacer() }
                        .padding(.vertical, 32)
                } else if app.foodEntries.isEmpty {
                    EmptyFoodLog()
                } else {
                    ForEach(app.foodEntries) { entry in
                        FoodEntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorEntry = entry
                                showingEditor = true
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    Task { await app.deleteFoodEntry(entry) }
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Food log")
                    Spacer()
                    Text("\(app.foodEntries.count) \(app.foodEntries.count == 1 ? "item" : "items")")
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            .leafyBorderlessRows()

            if let message = app.dailyErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("We couldn’t update your food log", systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.headline)
                            .foregroundStyle(.orange)
                        Text(message).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await app.loadDailyLog() } }
                    }
                    .padding(.vertical, 6)
                }
                .leafyBorderlessRows(separators: false)
            }
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.xLarge)
        .contentMargins(.top, LeafySpacing.medium, for: .scrollContent)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button("Log Food") {
                showingLogChoices = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, LeafySpacing.compact)
            .padding(.bottom, LeafySpacing.small)
            .background(.regularMaterial)
            .accessibilityIdentifier("logFoodButton")
        }
        .sheet(isPresented: $showingEditor) {
            FoodEntryEditorView(entry: editorEntry, logDate: app.selectedLogDate)
        }
        .sheet(isPresented: $showingProductFinder) {
            NavigationStack { ProductDiscoveryView(intent: .log) }
        }
        .confirmationDialog("How would you like to log food?", isPresented: $showingLogChoices, titleVisibility: .visible) {
            Button("Scan or Search Product") { showingProductFinder = true }
            Button("Enter Manually") { editorEntry = nil; showingEditor = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the catalog for complete nutrition data, or enter calories manually.")
        }
        .task {
            if app.dailyPlan == nil && !app.isDailyLoading { await app.loadDailyLog() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await app.loadDailyLog()
                await app.loadMorningCheckIn(presentWhenNeeded: true)
            }
        }
    }
}

private struct AdaptiveTargetNotice: View {
    @Environment(AppModel.self) private var app
    let notice: PlanAdjustmentNotice

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            HStack(alignment: .top) {
                Label("Your budget was personalized", systemImage: "sparkles")
                    .font(LeafyTypography.headline)
                    .foregroundStyle(LeafyTheme.green)
                Spacer()
                Button {
                    Task { await app.acknowledgePlanAdjustment() }
                } label: {
                    Image(systemName: "xmark")
                        .font(LeafyTypography.captionSemibold)
                        .padding(8)
                        .background(Color(.tertiarySystemGroupedBackground), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss budget update")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(notice.previousCalorieTargetKcal)")
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text("\(notice.newCalorieTargetKcal) Cal")
                    .font(LeafyTypography.title3)
            }
            Text(notice.explanation)
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(LeafySpacing.medium)
        .background(LeafyTheme.mint.opacity(0.75), in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("adaptiveTargetNotice")
    }
}

private struct DateNavigator: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 18) {
            Button { Task { await app.moveLogDate(by: -1) } } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")
            .accessibilityIdentifier("previousDayButton")

            VStack(spacing: 2) {
                Text(app.isViewingToday ? "Today" : app.selectedLogDate.formatted(.dateTime.weekday(.wide)))
                    .font(LeafyTypography.title2)
                Text(app.selectedLogDate.formatted(date: .abbreviated, time: .omitted))
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button { Task { await app.moveLogDate(by: 1) } } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(app.isViewingToday)
            .accessibilityLabel("Next day")
            .accessibilityIdentifier("nextDayButton")
        }
        .tint(LeafyTheme.green)
    }
}

private struct CalorieBudgetCard: View {
    let summary: DailyCalorieSummary

    var body: some View {
        VStack(spacing: LeafySpacing.large) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 20)
                Circle()
                    .trim(from: 0, to: summary.progress)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: LeafySpacing.xSmall) {
                    Text(heroValue)
                        .font(LeafyTypography.metric(48, extraBold: true))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .accessibilityIdentifier("calorieRingValue")

                    Text(heroLabel)
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("calorieRingLabel")
                }
                .padding(.horizontal, LeafySpacing.large)
            }
            .frame(width: 220, height: 220)
            .accessibilityHidden(true)

            HStack(spacing: LeafySpacing.xLarge) {
                BudgetMetric(title: "Eaten", value: "\(summary.consumed)", unit: "Cal")
                BudgetMetric(title: "Daily budget", value: formattedBudget, unit: "Cal")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LeafySpacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("calorieBudgetCard")
    }

    private var heroValue: String {
        guard let remaining = summary.remaining else { return "—" }
        return abs(remaining).formatted()
    }
    private var heroLabel: String {
        guard summary.budget != nil else { return "budget unavailable" }
        return summary.isOverBudget ? "calories over" : "calories remaining"
    }
    private var formattedBudget: String { summary.budget?.formatted() ?? "—" }
    private var progressColor: Color {
        guard summary.budget != nil else { return .secondary }
        return summary.isOverBudget ? .red : LeafyTheme.green
    }
    private var accessibilitySummary: String {
        guard let budget = summary.budget, let remaining = summary.remaining else {
            return "Calorie budget unavailable. \(summary.consumed.formatted()) calories eaten."
        }
        return summary.isOverBudget
            ? "\(abs(remaining).formatted()) calories over. \(summary.consumed.formatted()) of \(budget.formatted()) calories eaten."
            : "\(remaining.formatted()) calories remaining. \(summary.consumed.formatted()) of \(budget.formatted()) calories eaten."
    }
}

private struct BudgetMetric: View {
    let title: String
    let value: String
    let unit: String
    var body: some View {
        VStack(spacing: LeafySpacing.xSmall) {
            Text(title)
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(LeafyTypography.title3)
                    .monospacedDigit()
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(unit).font(LeafyTypography.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FoodEntryRow: View {
    let entry: FoodEntry
    var body: some View {
        HStack(spacing: 14) {
            Text(entry.consumedAt.formatted(date: .omitted, time: .shortened))
                .font(LeafyTypography.caption).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(LeafyTypography.bodyMedium).lineLimit(2)
                if entry.isAIEstimate {
                    Label("AI estimate", systemImage: "sparkles")
                        .font(LeafyTypography.caption2).foregroundStyle(LeafyTheme.green)
                }
            }
            Spacer(minLength: 8)
            Text("\(entry.calories) Cal")
                .font(LeafyTypography.subheadlineSemibold).monospacedDigit()
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to edit")
    }
}

private struct EmptyFoodLog: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 38))
                .foregroundStyle(LeafyTheme.green)
            Text("Nothing logged yet").font(LeafyTypography.headline)
            Text("Add food as you eat to see your calorie budget update throughout the day.")
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
