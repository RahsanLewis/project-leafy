import Charts
import SwiftUI

struct WeightView: View {
    enum ChartRange: String, CaseIterable {
        case week = "1W"
        case month = "1M"
        case quarter = "3M"
        case yearToDate = "YTD"
        case year = "1Y"
        case all = "All"

        func startDate(relativeTo now: Date, calendar: Calendar) -> Date? {
            switch self {
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: now)
            case .month:
                return calendar.date(byAdding: .day, value: -30, to: now)
            case .quarter:
                return calendar.date(byAdding: .day, value: -90, to: now)
            case .yearToDate:
                return calendar.date(from: calendar.dateComponents([.calendar, .timeZone, .year], from: now))
            case .year:
                return calendar.date(byAdding: .day, value: -365, to: now)
            case .all:
                return nil
            }
        }
    }

    @Environment(AppModel.self) private var app
    @State private var chartRange: ChartRange = .month
    @State private var selectedEntryID: UUID?
    @State private var editingEntry: WeightEntry?
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                hero
                    .listRowInsets(.init(
                        top: 0,
                        leading: LeafyTheme.pageInset,
                        bottom: 0,
                        trailing: LeafyTheme.pageInset
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .leafyBorderlessRows(separators: false)

            if let status = app.weightStatusMessage, let outcome = app.lastWeightOutcome {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(status, systemImage: statusIcon(outcome))
                            .font(LeafyTypography.headline)
                            .foregroundStyle(outcome == .reviewRequired ? .orange : LeafyTheme.green)
                        if outcome == .reviewRequired {
                            Button("Review Plan") { app.editPlan() }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .leafyBorderlessRows(separators: false)
            }

            Section {
                VStack(alignment: .leading, spacing: LeafySpacing.compact) {
                    HStack {
                        Text("Weight trend")
                            .font(LeafyTypography.headline)
                        Spacer()
                        Text(unitLabel)
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.secondary)
                    }

                    if filteredEntries.isEmpty {
                        VStack(spacing: LeafySpacing.small) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(LeafyTypography.icon(24))
                                .foregroundStyle(.secondary)
                            Text(app.weightEntries.isEmpty ? "Log your weight to begin tracking progress." : "No weigh-ins in this range.")
                                .font(LeafyTypography.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .accessibilityIdentifier("emptyWeightChart")
                    } else {
                        weightChart.frame(height: 200)
                    }

                    chartRangePicker
                }
                .padding(.vertical, LeafySpacing.small)
            }
            .leafyBorderlessRows(separators: false)

            Section("Insights") {
                statsGrid
                    .padding(.vertical, LeafySpacing.small)
            }
            .leafyBorderlessRows(separators: false)

            Section("History") {
                if app.isWeightLoading && app.weightEntries.isEmpty {
                    HStack { Spacer(); ProgressView("Loading weights…"); Spacer() }.padding(.vertical, 24)
                } else {
                    ForEach(app.weightEntries) { entry in
                        WeightHistoryRow(entry: entry, unitSystem: app.draft.unitSystem)
                            .contentShape(Rectangle())
                            .onTapGesture { editingEntry = entry; showingEditor = true }
                            .swipeActions {
                                if entry.source != .baseline {
                                    Button("Delete", role: .destructive) { Task { await app.deleteWeightEntry(entry) } }
                                }
                            }
                    }
                }
            }
            .leafyBorderlessRows()

            if let error = app.weightErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("We couldn’t update your weight", systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.headline).foregroundStyle(.orange)
                        Text(error).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await app.loadWeightHistory() } }
                    }.padding(.vertical, 4)
                }
                .leafyBorderlessRows(separators: false)
            }
        }
        .leafyBorderlessList()
        .listSectionSpacing(LeafySpacing.xLarge)
        .contentMargins(.top, LeafySpacing.medium, for: .scrollContent)
        .contentMargins(.bottom, LeafySpacing.medium, for: .scrollContent)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button("Log Weight") { editingEntry = nil; showingEditor = true }
                .buttonStyle(PrimaryButtonStyle())
                .clipShape(Capsule())
                .leafyDetachedBottomControl()
                .accessibilityIdentifier("logWeightButton")
        }
        .sheet(isPresented: $showingEditor) {
            WeightEntryEditorView(entry: editingEntry)
        }
        .onChange(of: chartRange) { _, _ in selectedEntryID = nil }
        .task { if app.weightEntries.isEmpty && !app.isWeightLoading { await app.loadWeightHistory() } }
    }

    private var hero: some View {
        let progress = app.weightProgress
        return VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(heroLabel)
                .font(LeafyTypography.subheadline)
                .foregroundStyle(.secondary)
            Text(displayedEntry.map { formatWeight($0.weightKG) } ?? "—")
                .font(LeafyTypography.metric(42, extraBold: true))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            if let change = rangeChangeKG {
                (
                    Text(changeSummary(change))
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundColor(changeColor(change))
                    + Text("  ·  ")
                        .font(LeafyTypography.footnote)
                        .foregroundColor(.secondary)
                    + Text(changePeriodLabel)
                        .font(LeafyTypography.footnote)
                        .foregroundColor(.secondary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("\(changeSummary(change)), \(changePeriodLabel)")
            } else if let latest = filteredEntries.first {
                (
                    Text("Latest check-in")
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundColor(LeafyTheme.green)
                    + Text("  ·  ")
                        .font(LeafyTypography.footnote)
                        .foregroundColor(.secondary)
                    + Text(latest.recordedOn.formatted(date: .abbreviated, time: .omitted))
                        .font(LeafyTypography.footnote)
                        .foregroundColor(.secondary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            if let target = progress.targetKG, let remaining = progress.remainingKG {
                HStack(spacing: 0) {
                    goalDatum(label: "Goal", value: formatWeight(target))

                    Divider()
                        .frame(height: 38)
                        .padding(.horizontal, LeafySpacing.large)

                    goalDatum(label: "Remaining", value: formatWeight(remaining))
                }
                .padding(.top, LeafySpacing.medium)
            } else {
                Label(
                    "Maintaining around \(formatWeight(progress.targetKG ?? progress.latestKG ?? app.draft.currentWeightKG))",
                    systemImage: "equal.circle.fill"
                )
                .font(LeafyTypography.subheadlineSemibold)
                .foregroundStyle(LeafyTheme.green)
            }
        }
        .padding(.vertical, LeafySpacing.small)
        .accessibilityIdentifier("weightSummaryCard")
    }

    private func goalDatum(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text(label)
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(LeafyTypography.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var weightChart: some View {
        Chart {
            ForEach(filteredEntries.reversed()) { entry in
                LineMark(x: .value("Date", entry.recordedOn), y: .value("Weight", displayValue(entry.weightKG)))
                    .foregroundStyle(LeafyTheme.green)
                    .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", entry.recordedOn), y: .value("Weight", displayValue(entry.weightKG)))
                    .foregroundStyle(LeafyTheme.green)
                    .symbolSize(34)
            }
            if app.draft.goal != .maintain {
                RuleMark(y: .value("Target", displayValue(app.draft.targetWeightKG)))
                    .foregroundStyle(LeafyTheme.green.opacity(0.38))
                    .lineStyle(.init(lineWidth: 1, dash: [6, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal")
                            .font(LeafyTypography.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            if let selectedEntry {
                RuleMark(x: .value("Selected date", selectedEntry.recordedOn))
                    .foregroundStyle(LeafyTheme.green.opacity(0.45))
                    .lineStyle(.init(lineWidth: 1, dash: [3]))
                PointMark(
                    x: .value("Selected date", selectedEntry.recordedOn),
                    y: .value("Selected weight", displayValue(selectedEntry.weightKG))
                )
                .foregroundStyle(LeafyTheme.green)
                .symbolSize(90)
            }
        }
        .chartYScale(domain: chartScale.domain)
        .chartXScale(domain: chartDateDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: xAxisLabelCount)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(xAxisLabel(for: date))
                            .font(LeafyTypography.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: .init(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.16))
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.background(Color.clear)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in selectEntry(at: value.location, proxy: proxy, geometry: geometry) }
                            .onEnded { _ in selectedEntryID = nil }
                    )
            }
        }
        .accessibilityIdentifier("weightChart")
    }

    private var chartRangePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: LeafySpacing.large) {
                ForEach(ChartRange.allCases, id: \.self) { range in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            chartRange = range
                        }
                    } label: {
                        Text(range.rawValue)
                            .font(LeafyTypography.subheadlineSemibold)
                            .foregroundStyle(chartRange == range ? LeafyTheme.green : .primary)
                            .frame(minWidth: 36)
                            .padding(.vertical, LeafySpacing.small)
                            .overlay(alignment: .bottom) {
                                if chartRange == range {
                                    Capsule()
                                        .fill(LeafyTheme.green)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chartRange == range ? .isSelected : [])
                    .accessibilityIdentifier("weightRange\(range.rawValue)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart range")
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: LeafySpacing.large
        ) {
            WeightStat(
                label: "7-day average",
                value: insights.trendWeightKG.map(formatWeight) ?? "More Data Needed",
                explanation: "Your average weight from weigh-ins recorded during the latest seven days. This smooths normal day-to-day changes so the underlying trend is easier to see.",
                identifier: "sevenDayAverage"
            )
            WeightStat(
                label: "\(chartRange.rawValue) change",
                value: insights.periodChangeKG.map(formatChange) ?? "More Data Needed",
                explanation: "The difference between your first and latest weigh-in in the selected \(chartRange.rawValue) chart range.",
                status: insights.periodChangeKG == nil ? "Add at least two weigh-ins in this range to calculate your change." : nil,
                identifier: "rangeChange"
            )
            WeightStat(
                label: "Weekly trend",
                value: insights.weeklyPaceKG.map { "\(formatChange($0))/week" } ?? "More Data Needed",
                explanation: "Your estimated weekly rate of weight change. Leafy uses the overall pattern in your weigh-ins so a single unusually high or low day has less influence.",
                status: insights.weeklyPaceKG == nil ? "Add at least three weigh-ins spanning seven days to estimate your weekly trend." : nil,
                identifier: "weeklyTrend"
            )
            WeightStat(
                label: "Goal pace",
                value: paceComparisonLabel,
                explanation: "Compares your observed weekly trend with the weekly change in your nutrition plan. A pace within 20% of the plan is considered on pace.",
                status: paceComparisonDetail,
                identifier: "goalPace",
                valueColor: paceComparisonColor
            )
            WeightStat(
                label: "Days logged",
                value: insights.consistency.map { "\(Int(($0 * 100).rounded()))%" } ?? "More Data Needed",
                explanation: "The percentage of days in the selected range that include a weigh-in. Leafy counts no more than one weigh-in per day.",
                status: insights.periodDayCount > 0 ? "You logged weight on \(insights.weighInDayCount) of \(insights.periodDayCount) days." : "Log your first weight to begin measuring consistency.",
                identifier: "daysLogged"
            )
            WeightStat(
                label: "Projected goal",
                value: forecastLabel,
                explanation: "An estimated date for reaching your target if your observed weekly trend continues. It is a projection, not a deadline or guarantee.",
                status: forecastDetail,
                identifier: "projectedGoal"
            )
        }
    }

    private var insights: WeightTrendInsights {
        let now = Date.now
        return WeightTrendInsights(
            entries: filteredEntries,
            periodStart: chartRange.startDate(relativeTo: now, calendar: .current),
            periodEnd: now,
            targetKG: app.draft.targetWeightKG,
            goal: app.draft.goal,
            plannedWeeklyChangeKG: app.currentPlan?.projectedWeeklyChangeKG,
            calendar: .current
        )
    }

    private var paceComparisonLabel: String {
        switch insights.paceComparison {
        case .learning: "More Data Needed"
        case .onPace: "On pace"
        case .fasterThanPlan: "Faster than plan"
        case .slowerThanPlan: "Slower than plan"
        case .movingAway: app.draft.goal == .maintain ? "Outside range" : "Moving away"
        }
    }

    private var paceComparisonDetail: String? {
        switch insights.paceComparison {
        case .learning: "Add at least three weigh-ins spanning seven days to compare your trend with your plan."
        case .onPace: "Your observed trend is within 20% of your planned pace."
        case .fasterThanPlan: "Your observed trend is faster than planned. Review your plan if this pace feels difficult to sustain."
        case .slowerThanPlan: "Your observed trend is slower than your planned pace."
        case .movingAway: "Your observed trend is currently moving in the opposite direction from your goal."
        }
    }

    private var paceComparisonColor: Color {
        switch insights.paceComparison {
        case .onPace: LeafyTheme.green
        case .fasterThanPlan, .movingAway: .orange
        case .learning, .slowerThanPlan: .primary
        }
    }

    private var forecastLabel: String {
        switch insights.goalForecast {
        case .learning: "More Data Needed"
        case .ongoing: "Ongoing"
        case .notTrendingTowardGoal: "Not available"
        case let .date(date): date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private var forecastDetail: String? {
        switch insights.goalForecast {
        case .learning: "Add at least seven weigh-ins spanning 14 days before Leafy projects a goal date."
        case .ongoing: "Maintenance is ongoing, so there is no finish date to project."
        case .notTrendingTowardGoal: "A date cannot be projected while your observed trend is not moving toward your target."
        case .date: "This projection uses your current target and observed weekly trend."
        }
    }

    private var selectedEntry: WeightEntry? {
        guard let selectedEntryID else { return nil }
        return filteredEntries.first { $0.id == selectedEntryID }
    }

    private var displayedEntry: WeightEntry? { selectedEntry ?? filteredEntries.first ?? app.weightEntries.first }

    private var rangeStartEntry: WeightEntry? { filteredEntries.last }

    private var rangeChangeKG: Double? {
        guard filteredEntries.count > 1, let displayedEntry, let rangeStartEntry else { return nil }
        return displayedEntry.weightKG - rangeStartEntry.weightKG
    }

    private var heroLabel: String {
        selectedEntry?.recordedOn.formatted(date: .abbreviated, time: .omitted) ?? "Current weight"
    }

    private func changeSummary(_ changeKG: Double) -> String {
        guard abs(changeKG) >= 0.0001 else { return "No change" }
        let direction = changeKG > 0 ? "Up" : "Down"
        return "\(direction) \(formatWeightValue(abs(changeKG))) \(unitLabel)"
    }

    private var changePeriodLabel: String {
        guard let start = rangeStartEntry else { return "Selected range" }
        return "Since \(start.recordedOn.formatted(date: .abbreviated, time: .omitted))"
    }

    private func changeColor(_ changeKG: Double) -> Color {
        switch WeightDashboardStats.movement(for: changeKG, goal: app.draft.goal) {
        case .towardGoal: LeafyTheme.green
        case .awayFromGoal: .orange
        case .neutral: .secondary
        }
    }

    private func selectEntry(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frameAnchor = proxy.plotFrame else { return }
        let frame = geometry[frameAnchor]
        let plotX = location.x - frame.origin.x
        guard plotX >= 0, plotX <= frame.width,
              let date = proxy.value(atX: plotX, as: Date.self)
        else { return }
        selectedEntryID = filteredEntries.min {
            abs($0.recordedOn.timeIntervalSince(date)) < abs($1.recordedOn.timeIntervalSince(date))
        }?.id
    }

    private var chartScale: WeightChartScale {
        WeightChartScale(
            weightsKG: filteredEntries.map(\.weightKG),
            targetKG: app.draft.targetWeightKG,
            goal: app.draft.goal,
            unitSystem: app.draft.unitSystem
        )
    }

    private var filteredEntries: [WeightEntry] {
        guard let cutoff = chartRange.startDate(relativeTo: .now, calendar: .current) else { return app.weightEntries }
        return app.weightEntries.filter { $0.recordedOn >= cutoff }
    }

    private var chartDateDomain: ClosedRange<Date> {
        let now = Date.now
        if let start = chartRange.startDate(relativeTo: now, calendar: .current) {
            let end: Date
            end = now
            return start...max(end, start.addingTimeInterval(60))
        }

        let dates = filteredEntries.map(\.recordedOn)
        guard let earliest = dates.min(), let latest = dates.max() else {
            return Calendar.current.date(byAdding: .day, value: -30, to: now)!...now
        }
        guard earliest != latest else {
            let start = Calendar.current.date(byAdding: .day, value: -1, to: earliest) ?? earliest.addingTimeInterval(-86_400)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: latest) ?? latest.addingTimeInterval(86_400)
            return start...end
        }
        return earliest...latest
    }

    private var xAxisLabelCount: Int {
        switch chartRange {
        case .week: 4
        case .month, .quarter: 4
        case .yearToDate, .year, .all: 5
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        switch chartRange {
        case .week, .month:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .quarter, .yearToDate, .year:
            return date.formatted(.dateTime.month(.abbreviated))
        case .all:
            return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    private func displayValue(_ kg: Double) -> Double { app.draft.unitSystem == .imperial ? kg * 2.20462 : kg }
    private var unitLabel: String { app.draft.unitSystem == .imperial ? "lb" : "kg" }
    private func formatWeight(_ kg: Double) -> String { "\(formatWeightValue(kg)) \(app.draft.unitSystem == .imperial ? "lb" : "kg")" }
    private func formatWeightValue(_ kg: Double) -> String { String(format: "%.1f", displayValue(kg)) }
    private func formatChange(_ kg: Double) -> String {
        let value = displayValue(kg)
        return String(format: "%@%.1f %@", value > 0 ? "+" : "", value, app.draft.unitSystem == .imperial ? "lb" : "kg")
    }
    private func statusIcon(_ outcome: WeightMutationOutcome) -> String {
        switch outcome {
        case .tracked: "checkmark.circle.fill"
        case .planUpdated: "arrow.triangle.2.circlepath.circle.fill"
        case .goalReached: "trophy.fill"
        case .reviewRequired: "exclamationmark.triangle.fill"
        }
    }
}

private struct WeightStat: View {
    let label: String
    let value: String
    let explanation: String
    var status: String? = nil
    let identifier: String
    var valueColor: Color = .primary
    @State private var showingExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            HStack(spacing: 0) {
                Text(label)
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button {
                    showingExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(LeafyTypography.icon(14))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(label)")
                .accessibilityIdentifier("weightInsightInfo-\(identifier)")
                .popover(isPresented: $showingExplanation, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        Text(label)
                            .font(LeafyTypography.headline)
                        Text(explanation)
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.secondary)
                        if let status {
                            Divider()
                            Text(status)
                                .font(LeafyTypography.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(LeafySpacing.medium)
                    .frame(width: 280, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
            }

            Text(value)
                .font(LeafyTypography.headline)
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .accessibilityLabel("\(label), \(value)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeightHistoryRow: View {
    let entry: WeightEntry
    let unitSystem: UnitSystem
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.recordedOn.formatted(date: .abbreviated, time: .omitted)).font(LeafyTypography.bodyMedium)
                if entry.source == .baseline { Text("Starting weight").font(LeafyTypography.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(String(format: "%.1f %@", unitSystem == .imperial ? entry.weightKG * 2.20462 : entry.weightKG, unitSystem == .imperial ? "lb" : "kg"))
                .font(LeafyTypography.headline).monospacedDigit()
        }.padding(.vertical, 5)
    }
}
