import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editorEntry: FoodEntry?
    @State private var nutritionEntry: FoodEntry?
    @State private var dayValueOpacity = 1.0
    @State private var isChangingDay = false
    @State private var showDayLoading = false

    var body: some View {
        List {
            Section {
                DateNavigator(
                    isChangingDay: isChangingDay,
                    valueOpacity: dayValueOpacity,
                    move: changeDay
                )
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
                        MorningCheckInReminder()
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

                CalorieBudgetCard(
                    summary: app.dailySummary,
                    supportingValueOpacity: dayValueOpacity,
                    isChangingDay: isChangingDay,
                    canMoveToNextDay: !app.isViewingToday,
                    move: changeDay
                )
                    .listRowInsets(.init(
                        top: LeafySpacing.small,
                        leading: 0,
                        bottom: 0,
                        trailing: 0
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                HStack {
                    Spacer(minLength: 0)
                    Button {
                        app.presentMealLogger()
                    } label: {
                        Label("Log Food", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 230)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("logFoodButton")
                    Spacer(minLength: 0)
                }
                .listRowInsets(.init(
                    top: LeafySpacing.large,
                    leading: LeafyTheme.pageInset,
                    bottom: LeafySpacing.small,
                    trailing: LeafyTheme.pageInset
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let nutrition = app.dailyNutrition {
                    NavigationLink {
                        DailyNutritionView()
                    } label: {
                        TodayMacroSummary(summary: nutrition, plan: app.dailyPlan)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: LeafySpacing.xLarge, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("openDailyNutrition")
                }
            }
            .leafyBorderlessRows(separators: false)

            Section {
                if app.isDailyLoading && app.foodEntries.isEmpty {
                    HStack { Spacer(); ProgressView("Loading your day…"); Spacer() }
                        .padding(.vertical, 32)
                } else if app.foodEntries.isEmpty {
                    EmptyFoodLog()
                        .opacity(dayValueOpacity)
                } else {
                    ForEach(app.foodEntries) { entry in
                        FoodEntryRow(entry: entry, valueOpacity: dayValueOpacity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                nutritionEntry = entry
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    Task { _ = await app.deleteFoodEntry(entry) }
                                }
                                Button {
                                    editorEntry = entry
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(LeafyTheme.green)
                            }
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Food log")
                        .font(LeafyTypography.title3)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    Spacer()
                    Text("\(app.foodEntries.count) \(app.foodEntries.count == 1 ? "item" : "items")")
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .opacity(dayValueOpacity)
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
        .overlay(alignment: .topTrailing) {
            if showDayLoading {
                ProgressView()
                    .controlSize(.regular)
                    .padding(12)
                    .background(.regularMaterial, in: .circle)
                    .padding(.top, LeafySpacing.medium)
                    .padding(.trailing, LeafyTheme.pageInset)
                    .transition(.opacity)
                    .accessibilityLabel("Loading day")
            }
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.xxLarge)
        .contentMargins(.top, LeafySpacing.small, for: .scrollContent)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editorEntry) { entry in
            FoodEntryEditorView(entry: entry, logDate: app.selectedLogDate)
        }
        .navigationDestination(item: $nutritionEntry) { entry in
            FoodEntryNutritionView(entry: entry)
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

    private func changeDay(by days: Int) {
        guard !isChangingDay, days < 0 || !app.isViewingToday else { return }
        isChangingDay = true

        Task {
            let exitDuration = reduceMotion ? 0.14 : 0.18
            withAnimation(.easeOut(duration: exitDuration)) {
                dayValueOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 140 : 180))

            let loadingIndicator = Task {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.15)) { showDayLoading = true }
            }

            let changed = await app.moveLogDate(by: days)
            loadingIndicator.cancel()
            withAnimation(.easeOut(duration: 0.12)) { showDayLoading = false }

            if changed {
                withAnimation(.easeInOut(duration: reduceMotion ? 0.18 : 0.28)) {
                    dayValueOpacity = 1
                }
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: app.selectedLogDate.formatted(date: .complete, time: .omitted)
                    )
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    dayValueOpacity = 1
                }
            }
            isChangingDay = false
        }
    }
}

private struct MorningCheckInReminder: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: LeafySpacing.medium) {
            Image(systemName: "sunrise.fill")
                .font(LeafyTypography.icon(22, relativeTo: .headline))
                .foregroundStyle(LeafyTheme.green)

            VStack(alignment: .leading, spacing: 3) {
                Text(dynamicTypeSize.isAccessibilitySize ? "Morning check-in" : "Finish your morning check-in")
                    .font(LeafyTypography.headline)
                    .foregroundStyle(.primary)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Review yesterday and add today’s weight.")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: LeafySpacing.small)
            Image(systemName: "chevron.right")
                .font(LeafyTypography.icon(15, relativeTo: .headline))
                .foregroundStyle(.secondary)
        }
        .padding(LeafySpacing.medium)
        .background(LeafyTheme.mint, in: .rect(cornerRadius: LeafyRadius.prominent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finish your morning check-in")
        .accessibilityHint("Review yesterday and add today’s weight")
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
                        .background(LeafyTheme.surface, in: .circle)
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
    let isChangingDay: Bool
    let valueOpacity: Double
    let move: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LeafySpacing.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.isViewingToday ? "Today" : app.selectedLogDate.formatted(.dateTime.weekday(.wide)))
                    .font(LeafyTypography.largeTitle)
                    .accessibilityIdentifier("selectedLogDayTitle")
                Text(app.selectedLogDate.formatted(date: .abbreviated, time: .omitted))
                    .font(LeafyTypography.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("selectedLogDate")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(valueOpacity)

            HStack(spacing: LeafySpacing.xSmall) {
                Button { move(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isChangingDay)
                .accessibilityLabel("Previous day")
                .accessibilityIdentifier("previousDayButton")

                Button { move(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(app.isViewingToday || isChangingDay)
                .accessibilityLabel("Next day")
                .accessibilityIdentifier("nextDayButton")
            }
        }
        .padding(.horizontal, LeafyTheme.pageInset)
        .tint(LeafyTheme.green)
    }
}

private struct CalorieBudgetCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: DailyCalorieSummary
    let supportingValueOpacity: Double
    let isChangingDay: Bool
    let canMoveToNextDay: Bool
    let move: (Int) -> Void

    var body: some View {
        VStack(spacing: LeafySpacing.xLarge) {
            ZStack {
                Circle()
                    .stroke(LeafyTheme.track, lineWidth: 18)
                Circle()
                    .trim(from: 0, to: summary.progress)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.44, bounce: 0.06),
                        value: summary.progress
                    )

                VStack(spacing: LeafySpacing.xSmall) {
                    Text(heroValue)
                        .font(LeafyTypography.metric(54, extraBold: true))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .contentTransition(
                            reduceMotion
                                ? .opacity
                                : .numericText(value: Double(heroNumericValue ?? 0))
                        )
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.16)
                                : .spring(duration: 0.42, bounce: 0.05),
                            value: heroNumericValue
                        )
                        .accessibilityIdentifier("calorieRingValue")

                    Text(heroLabel)
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: heroLabel)
                        .accessibilityIdentifier("calorieRingLabel")
                }
                .padding(.horizontal, LeafySpacing.large)
            }
            .frame(width: ringSize, height: ringSize)
            .contentShape(Circle())
            .accessibilityHidden(true)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: LeafySpacing.medium) {
                        eatenMetric
                        budgetMetric
                    }
                } else {
                    HStack(spacing: 0) {
                        eatenMetric
                        Rectangle()
                            .fill(LeafyTheme.hairline)
                            .frame(width: 1, height: 38)
                        budgetMetric
                    }
                }
            }
            .padding(.horizontal, LeafyTheme.pageInset)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LeafySpacing.small)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 20)
                .onEnded(handleRingDrag)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("calorieBudgetCard")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where canMoveToNextDay: move(1)
            case .decrement: move(-1)
            default: break
            }
        }
    }

    private var heroValue: String {
        heroNumericValue?.formatted() ?? "—"
    }
    private var heroNumericValue: Int? { summary.remaining.map(abs) }
    private var heroLabel: String {
        guard summary.budget != nil else { return "budget unavailable" }
        return summary.isOverBudget ? "calories over" : "calories remaining"
    }
    private var formattedBudget: String { summary.budget?.formatted() ?? "—" }
    private var ringSize: CGFloat { dynamicTypeSize.isAccessibilitySize ? 268 : 244 }
    private var eatenMetric: some View {
        BudgetMetric(title: "Eaten", value: "\(summary.consumed)", unit: "Cal", valueOpacity: supportingValueOpacity)
    }
    private var budgetMetric: some View {
        BudgetMetric(title: "Daily budget", value: formattedBudget, unit: "Cal", valueOpacity: supportingValueOpacity)
    }
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

    private func handleRingDrag(_ value: DragGesture.Value) {
        guard !isChangingDay else { return }
        let horizontal = value.predictedEndTranslation.width
        let vertical = value.predictedEndTranslation.height
        guard abs(horizontal) >= 55, abs(horizontal) > abs(vertical) * 1.35 else { return }
        let days = horizontal < 0 ? 1 : -1
        guard days < 0 || canMoveToNextDay else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        move(days)
    }
}

private struct BudgetMetric: View {
    let title: String
    let value: String
    let unit: String
    let valueOpacity: Double
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
                    .opacity(valueOpacity)
                Text(unit).font(LeafyTypography.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FoodEntryRow: View {
    let entry: FoodEntry
    let valueOpacity: Double
    var body: some View {
        HStack(spacing: 14) {
            Text(entry.consumedAt.formatted(date: .omitted, time: .shortened))
                .font(LeafyTypography.caption).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
                .opacity(valueOpacity)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(LeafyTypography.bodyMedium)
                    .lineLimit(2)
                    .opacity(valueOpacity)
            }
            Spacer(minLength: 8)
            Text("\(entry.calories) Cal")
                .font(LeafyTypography.subheadlineSemibold).monospacedDigit()
                .opacity(valueOpacity)
        }
        .padding(.vertical, LeafySpacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("foodEntryRow-\(entry.id.uuidString)")
        .accessibilityHint("Double tap for nutrition details. Swipe left for edit or delete actions.")
    }
}

private struct TodayMacroSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: DailyNutritionSummary
    let plan: NutritionPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nutrition")
                    .font(LeafyTypography.title3)
                    .foregroundStyle(.primary)
                Spacer()
                Text("Details")
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(LeafyTheme.green)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: LeafySpacing.medium) {
                    macro("Protein", code: "protein_g", target: plan.map { Double($0.proteinG) })
                    macro("Carbs", code: "carbohydrate_g", target: plan.map { Double($0.carbohydrateG) })
                    macro("Fat", code: "fat_g", target: plan.map { Double($0.fatG) })
                }
            } else {
                HStack(alignment: .top, spacing: LeafySpacing.medium) {
                    macro("Protein", code: "protein_g", target: plan.map { Double($0.proteinG) })
                    macro("Carbs", code: "carbohydrate_g", target: plan.map { Double($0.carbohydrateG) })
                    macro("Fat", code: "fat_g", target: plan.map { Double($0.fatG) })
                }
            }

            if let coverage = summary.macroCoverage, coverage < 0.999 {
                Text("Macro details available for \(coverage.formatted(.percent.precision(.fractionLength(0)))) of logged calories")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, LeafyTheme.pageInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeMacroSummary")
    }

    private func macro(_ title: String, code: String, target: Double?) -> some View {
        let amount = summary.nutrient(code)?.amount ?? 0
        let progress = target.map { target in
            guard target.isFinite, target > 0, amount.isFinite else { return 0 }
            return min(max(amount / target, 0), 1)
        } ?? 0

        return VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(title)
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
            Text("\(format(amount))g")
                .font(LeafyTypography.headline)
                .monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LeafyTheme.track)
                    Capsule().fill(LeafyTheme.green).frame(width: max(proxy.size.width, 0) * progress)
                }
            }
            .frame(height: 4)
            Text(target.map { "of \(format($0))g" } ?? "No target")
                .font(LeafyTypography.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(format(amount)) grams, target \(target.map(format) ?? "unavailable") grams")
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
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
