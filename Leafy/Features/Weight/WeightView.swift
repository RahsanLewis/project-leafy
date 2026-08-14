import Charts
import SwiftUI
import UIKit

struct WeightView: View {
    enum DisplayMode: String, CaseIterable {
        case trend
        case actual

        var title: String {
            switch self {
            case .trend: "Trend"
            case .actual: "Actual"
            }
        }

        var metricTitle: String {
            switch self {
            case .trend: "Trend weight"
            case .actual: "Actual weight"
            }
        }
    }

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("weightDisplayMode") private var displayModeRawValue = DisplayMode.actual.rawValue
    @State private var chartRange: ChartRange = .month
    @State private var selectedChartDate: Date?
    @State private var lastHapticChartDate: Date?
    @State private var editingEntry: WeightEntry?
    @State private var showingEditor = false
    @State private var showingHistory = false
    @State private var showingWeightExplanation = false
    @State private var showingFluctuationExplanation = false
    @State private var showingPlanEditor = false

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
                            Button("Review Plan") { showingPlanEditor = true }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .leafyBorderlessRows(separators: false)
            }

            Section {
                VStack(alignment: .leading, spacing: LeafySpacing.medium) {
                    HStack {
                        Text("Weight history")
                            .font(LeafyTypography.title3)
                        Spacer()
                        Text(unitLabel)
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.secondary)
                    }

                    chartLegend

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
                        weightChart.frame(height: 240)
                    }

                    chartRangePicker
                }
                .padding(.vertical, LeafySpacing.small)
            }
            .leafyBorderlessRows(separators: false)

            Section {
                VStack(alignment: .leading, spacing: LeafySpacing.large) {
                    Text("Insights")
                        .font(LeafyTypography.title3)
                    statsGrid
                }
                .padding(.vertical, LeafySpacing.small)
            }
            .leafyBorderlessRows(separators: false)

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent weigh-ins")
                        .font(LeafyTypography.title3)
                    Spacer()
                    if app.weightEntries.count > 5 {
                        Button("View all") { showingHistory = true }
                            .font(LeafyTypography.subheadlineSemibold)
                    }
                }
                .listRowSeparator(.hidden)

                if app.isWeightLoading && app.weightEntries.isEmpty {
                    HStack { Spacer(); ProgressView("Loading weights…"); Spacer() }.padding(.vertical, 24)
                } else if app.weightEntries.isEmpty {
                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        Text("Your trend starts with one check-in.")
                            .font(LeafyTypography.headline)
                        Text("Log weight consistently and Leafy will smooth normal day-to-day changes.")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, LeafySpacing.large)
                } else {
                    ForEach(app.weightEntries.prefix(5)) { entry in
                        WeightHistoryRow(entry: entry, unitSystem: app.draft.unitSystem)
                            .contentShape(Rectangle())
                            .onTapGesture { editingEntry = entry; showingEditor = true }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if entry.source != .baseline {
                                    Button("Delete", role: .destructive) { Task { await app.deleteWeightEntry(entry) } }
                                }
                                Button {
                                    editingEntry = entry
                                    showingEditor = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(LeafyTheme.green)
                            }
                    }
                }
            }
            .leafyBorderlessRows()

            if let error = app.weightErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(app.weightErrorTitle, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.headline).foregroundStyle(.orange)
                        Text(error).font(LeafyTypography.subheadline).foregroundStyle(.secondary)
                        Button("Refresh history") { Task { await app.loadWeightHistory() } }
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
        .fullScreenCover(isPresented: $showingPlanEditor) {
            PlanEditView(onSaved: {})
        }
        .navigationDestination(isPresented: $showingHistory) {
            WeightHistoryView()
        }
        .onChange(of: chartRange) { _, _ in selectedChartDate = nil }
        .onChange(of: insights.hasTrend, initial: true) { _, hasTrend in
            if !hasTrend { displayModeRawValue = DisplayMode.actual.rawValue }
        }
        .task { if app.weightEntries.isEmpty && !app.isWeightLoading { await app.loadWeightHistory() } }
    }

    private var hero: some View {
        let progress = app.weightProgress
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LeafySpacing.xSmall) {
                if let selectedDataDate {
                    Text(selectedDataDate.formatted(date: .abbreviated, time: .omitted))
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if insights.hasTrend {
                        displayModeMenu
                    } else {
                        Text(DisplayMode.actual.metricTitle)
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: LeafyTheme.minimumTouchTarget)
                    }
                }

                if selectedChartDate == nil {
                    Button {
                        showingWeightExplanation = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(LeafyTypography.icon(14))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .padding(10)
                            .contentShape(Rectangle())
                            .padding(-10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About \(displayMode.metricTitle.lowercased())")
                    .accessibilityIdentifier(displayMode == .trend ? "trendWeightInfo" : "actualWeightInfo")
                }
            }
            .frame(height: 24, alignment: .leading)
            Text(displayedWeightKG.map(formatWeight) ?? "—")
                .font(LeafyTypography.metric(48, extraBold: true))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
                .padding(.top, LeafySpacing.small)
                .padding(.bottom, -10)
            if let supportingWeightKG {
                HStack(alignment: .firstTextBaseline, spacing: LeafySpacing.small) {
                    Text(supportingMetricLabel)
                        .font(LeafyTypography.footnote)
                        .foregroundStyle(.secondary)
                    Text(formatWeight(supportingWeightKG))
                        .font(LeafyTypography.subheadlineSemibold)
                        .monospacedDigit()
                    if let supportingMetricDate, selectedChartDate == nil {
                        Text(supportingMetricDate.formatted(date: .abbreviated, time: .omitted))
                            .font(LeafyTypography.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.top, 12)

            }
            if selectedChartDate == nil, let context = fluctuationContextMessage {
                Label(context, systemImage: "drop.fill")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, LeafySpacing.small)
            }
            if let target = progress.targetKG {
                HStack(spacing: 0) {
                    goalDatum(
                        label: "Goal",
                        value: formatWeight(target)
                    )
                    .padding(.trailing, LeafySpacing.medium)

                    Divider()
                        .frame(height: 38)

                    goalDatum(
                        label: displayMode == .trend ? "Trend remaining" : "Actual remaining",
                        value: displayedRemainingKG.map(formatWeight) ?? "Learning"
                    )
                    .padding(.leading, LeafySpacing.medium)
                }
                .padding(.top, LeafySpacing.large)
            } else {
                Label(
                    "Maintaining around \(formatWeight(progress.targetKG ?? progress.latestKG ?? app.draft.currentWeightKG))",
                    systemImage: "equal.circle.fill"
                )
                .font(LeafyTypography.subheadlineSemibold)
                .foregroundStyle(LeafyTheme.green)
            }
        }
        .padding(.vertical, LeafySpacing.medium)
        .sheet(isPresented: $showingWeightExplanation) {
            WeightExplanationView(mode: displayMode)
                .presentationDetents([.height(270)])
                .presentationDragIndicator(.visible)
        }
    }

    private func goalDatum(
        label: String,
        value: String
    ) -> some View {
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

    private var displayModeMenu: some View {
        Menu {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Button {
                    guard displayMode != mode else { return }
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.18)) {
                        displayModeRawValue = mode.rawValue
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Label(mode.metricTitle, systemImage: displayMode == mode ? "checkmark" : "")
                }
                .accessibilityIdentifier("weightDisplay\(mode.title)")
            }
        } label: {
            HStack(spacing: LeafySpacing.xSmall) {
                Text(displayMode.metricTitle)
                Image(systemName: "chevron.down")
                    .font(LeafyTypography.icon(11))
            }
            .font(LeafyTypography.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: LeafyTheme.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Weight view, \(displayMode.metricTitle)")
        .accessibilityHint("Choose trend weight or actual weight")
        .accessibilityIdentifier("weightDisplayMenu")
    }

    private var chartLegend: some View {
        HStack(spacing: LeafySpacing.large) {
            chartLegendItem(label: "Actual", showsPoint: true)
            if insights.fluctuationOffsetsKG != nil {
                Button {
                    showingFluctuationExplanation = true
                } label: {
                    HStack(spacing: LeafySpacing.xSmall) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LeafyTheme.green.opacity(0.12))
                            .frame(width: 24, height: 10)
                        Text("Typical range")
                            .font(LeafyTypography.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "info.circle")
                            .font(LeafyTypography.icon(12))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About the typical fluctuation range")
                .accessibilityIdentifier("weightFluctuationRangeInfo")
            }
        }
        .sheet(isPresented: $showingFluctuationExplanation) {
            FluctuationRangeExplanationView(goal: app.draft.goal)
                .presentationDetents([.height(310)])
                .presentationDragIndicator(.visible)
        }
    }

    private func chartLegendItem(label: String, showsPoint: Bool = false) -> some View {
        HStack(spacing: LeafySpacing.xSmall) {
            ZStack {
                Capsule()
                    .fill(LeafyTheme.green)
                    .frame(width: 24, height: 3)
                if showsPoint {
                    Circle()
                        .fill(LeafyTheme.green)
                        .frame(width: 7, height: 7)
                }
            }
            Text(label)
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var weightChart: some View {
        Chart {
            if let offsets = insights.fluctuationOffsetsKG {
                ForEach(filteredTrendPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Recent range low", displayValue(point.averageKG + offsets.lowerBound)),
                        yEnd: .value("Recent range high", displayValue(point.averageKG + offsets.upperBound))
                    )
                    .foregroundStyle(LeafyTheme.green.opacity(0.08))
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(chartActualEntries) { entry in
                LineMark(
                    x: .value("Date", entry.recordedOn),
                    y: .value("Weight", displayValue(entry.weightKG)),
                    series: .value("Series", "Actual")
                )
                    .foregroundStyle(LeafyTheme.green)
                    .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                PointMark(x: .value("Date", entry.recordedOn), y: .value("Actual weight", displayValue(entry.weightKG)))
                    .foregroundStyle(LeafyTheme.green)
                    .symbolSize(34)
            }
            if app.draft.goal != .maintain,
               chartScale.domain.contains(displayValue(app.draft.targetWeightKG)) {
                RuleMark(y: .value("Target", displayValue(app.draft.targetWeightKG)))
                    .foregroundStyle(LeafyTheme.green.opacity(0.38))
                    .lineStyle(.init(lineWidth: 1, dash: [6, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal")
                            .font(LeafyTypography.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            if let selectedDataDate {
                RuleMark(x: .value("Selected date", selectedDataDate))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(.init(lineWidth: 1, dash: [3]))
            }
            if let selectedActualEntry {
                PointMark(
                    x: .value("Selected date", selectedActualEntry.recordedOn),
                    y: .value("Selected actual weight", displayValue(selectedActualEntry.weightKG))
                )
                .foregroundStyle(LeafyTheme.green)
                .symbolSize(110)
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
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.background(Color.clear)
        }
        .chartXSelection(value: $selectedChartDate)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onEnded { _ in
                    withAnimation(reduceMotion ? .none : .easeOut(duration: 0.16)) {
                        selectedChartDate = nil
                        lastHapticChartDate = nil
                    }
                }
        )
        .onChange(of: selectedChartDate) { _, _ in
            guard let selectedDataDate, selectedDataDate != lastHapticChartDate else { return }
            lastHapticChartDate = selectedDataDate
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .accessibilityLabel("Recorded weight chart with a personalized typical fluctuation range")
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
            if displayMode == .trend {
                WeightStat(
                    label: "Total progress",
                    value: totalProgressKG.map(formatChange) ?? "Learning",
                    explanation: "The difference between your starting weight and your current trend weight. This measures progress across your full history rather than one scale reading.",
                    status: totalProgressKG == nil ? "Log enough weigh-ins to establish a trend weight." : nil,
                    identifier: "totalProgress"
                )
                WeightStat(
                    label: "Weekly trend",
                    value: insights.weeklyPaceKG.map { "\(formatChange($0))/week" } ?? "Learning",
                    explanation: "Your current seven-day average compared with the preceding seven-day average. Averaging reduces the influence of any single scale reading.",
                    status: weeklyLearningDetail,
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
                commonDaysLoggedStat
                commonFluctuationStat
                WeightStat(
                    label: "Projected goal",
                    value: forecastLabel,
                    explanation: "An estimated date for reaching your target if your observed weekly trend continues. It is a projection, not a deadline or guarantee.",
                    status: forecastDetail,
                    identifier: "projectedGoal"
                )
            } else {
                WeightStat(
                    label: "Total change",
                    value: actualTotalChangeKG.map(formatChange) ?? "Learning",
                    explanation: "The difference between your first recorded scale weight and your latest reading.",
                    status: actualTotalChangeKG == nil ? "Log at least two weigh-ins to calculate total change." : nil,
                    identifier: "actualTotalChange"
                )
                WeightStat(
                    label: "Latest change",
                    value: actualLatestChangeKG.map(formatChange) ?? "Learning",
                    explanation: "The difference between your two most recent scale readings. Water and digestion can influence this value.",
                    status: actualLatestChangeKG == nil ? "Log at least two weigh-ins to compare readings." : nil,
                    identifier: "actualLatestChange"
                )
                WeightStat(
                    label: "Selected change",
                    value: actualRangeChangeKG.map(formatChange) ?? "Learning",
                    explanation: "The difference between the first and last actual readings in the selected chart range.",
                    status: actualRangeChangeKG == nil ? "Choose a range containing at least two weigh-ins." : nil,
                    identifier: "actualRangeChange"
                )
                commonDaysLoggedStat
                if insights.hasTrend {
                    commonFluctuationStat
                    WeightStat(
                        label: "Versus trend",
                        value: actualDifferenceFromTrendKG.map(formatChange) ?? "Learning",
                        explanation: "How far your latest scale reading is above or below your current seven-reading trend.",
                        status: actualDifferenceFromTrendKG == nil ? "Leafy is still learning this comparison." : nil,
                        identifier: "actualVersusTrend"
                    )
                }
            }
        }
    }

    private var commonDaysLoggedStat: some View {
        WeightStat(
            label: "Days logged",
            value: insights.consistency.map { "\(Int(($0 * 100).rounded()))%" } ?? "Learning",
            explanation: "The percentage of days in the selected range that include a weigh-in. Leafy counts no more than one weigh-in per day.",
            status: insights.periodDayCount > 0 ? "You logged weight on \(insights.weighInDayCount) of \(insights.periodDayCount) days." : "Log your first weight to begin measuring consistency.",
            identifier: "daysLogged"
        )
    }

    private var commonFluctuationStat: some View {
        WeightStat(
            label: "Typical fluctuation",
            value: typicalFluctuationLabel,
            explanation: "The middle range of day-to-day differences between your scale readings and rolling trend during the last four weeks. It helps put a single higher or lower reading in context.",
            status: insights.fluctuationOffsetsKG == nil ? "Leafy needs at least 14 recent weigh-ins to estimate your typical range." : nil,
            identifier: "typicalFluctuation"
        )
    }

    private var insights: WeightTrendInsights {
        let now = Date.now
        return WeightTrendInsights(
            entries: app.weightEntries,
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
        case .learning: "Learning"
        case .onPace: "On pace"
        case .fasterThanPlan: "Faster than plan"
        case .slowerThanPlan: "Slower than plan"
        case .movingAway: app.draft.goal == .maintain ? "Outside trend range" : "Not yet aligned"
        }
    }

    private var paceComparisonDetail: String? {
        switch insights.paceComparison {
        case .learning: weeklyLearningDetail
        case .onPace: "Your observed trend is within 20% of your planned pace."
        case .fasterThanPlan: "Your observed trend is faster than planned. Review your plan if this pace feels difficult to sustain."
        case .slowerThanPlan: "Your observed trend is slower than your planned pace."
        case .movingAway: "Your weekly averages are not yet moving with your plan. Short-term readings do not affect this label."
        }
    }

    private var paceComparisonColor: Color {
        switch insights.paceComparison {
        case .onPace: LeafyTheme.green
        case .fasterThanPlan: .orange
        case .learning, .slowerThanPlan, .movingAway: .primary
        }
    }

    private var forecastLabel: String {
        switch insights.goalForecast {
        case .learning: "Learning"
        case .ongoing: "Ongoing"
        case .notTrendingTowardGoal: "Not available"
        case let .date(date): date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private var forecastDetail: String? {
        switch insights.goalForecast {
        case .learning: weeklyLearningDetail
        case .ongoing: "Maintenance is ongoing, so there is no finish date to project."
        case .notTrendingTowardGoal: "Leafy needs weekly averages that consistently move toward your target before projecting a date."
        case .date: "This projection uses your current target and the difference between consecutive weekly averages."
        }
    }

    private var selectedTrendPoint: WeightTrendPoint? {
        guard let selectedChartDate else { return nil }
        return filteredTrendPoints.min {
            abs($0.date.timeIntervalSince(selectedChartDate)) < abs($1.date.timeIntervalSince(selectedChartDate))
        }
    }

    private var selectedActualEntry: WeightEntry? {
        guard let selectedChartDate else { return nil }
        return filteredEntries.min {
            abs($0.recordedOn.timeIntervalSince(selectedChartDate)) < abs($1.recordedOn.timeIntervalSince(selectedChartDate))
        }
    }

    private var selectedDataDate: Date? {
        selectedActualEntry?.recordedOn
    }

    private var displayMode: DisplayMode {
        guard insights.hasTrend else { return .actual }
        return DisplayMode(rawValue: displayModeRawValue) ?? .actual
    }

    private var displayedWeightKG: Double? {
        if let selectedActualEntry { return selectedActualEntry.weightKG }
        switch displayMode {
        case .trend:
            return insights.trendWeightKG ?? latestEntry?.weightKG
        case .actual:
            return latestEntry?.weightKG
        }
    }

    private var supportingWeightKG: Double? {
        if selectedActualEntry != nil { return selectedTrendPoint?.averageKG }
        switch displayMode {
        case .trend: return selectedActualEntry?.weightKG ?? latestEntry?.weightKG
        case .actual: return selectedTrendPoint?.averageKG ?? insights.trendWeightKG
        }
    }

    private var supportingMetricLabel: String {
        displayMode == .trend ? "Actual reading" : "Seven-day trend"
    }

    private var supportingMetricDate: Date? {
        displayMode == .trend ? latestEntry?.recordedOn : filteredTrendPoints.last?.date
    }

    private var latestEntry: WeightEntry? {
        app.weightEntries.max { $0.recordedOn < $1.recordedOn }
    }

    private var filteredTrendPoints: [WeightTrendPoint] {
        guard let cutoff = chartRange.startDate(relativeTo: .now, calendar: .current) else { return insights.trendPoints }
        return insights.trendPoints.filter { $0.date >= cutoff }
    }

    private var displayedRemainingKG: Double? {
        guard app.draft.goal != .maintain else { return nil }
        if displayMode == .trend, selectedChartDate == nil, !insights.hasTrend {
            return nil
        }
        guard let displayedWeightKG else { return nil }
        return abs(app.draft.targetWeightKG - displayedWeightKG)
    }

    private var totalProgressKG: Double? {
        WeightInsightMetrics.totalProgressKG(
            startingKG: app.weightProgress.startingKG,
            trendWeightKG: insights.trendWeightKG,
            currentSampleCount: insights.distinctReadingCount
        )
    }

    private var actualTotalChangeKG: Double? {
        WeightInsightMetrics.actualTotalChangeKG(entries: app.weightEntries)
    }

    private var actualLatestChangeKG: Double? {
        WeightInsightMetrics.actualLatestChangeKG(entries: app.weightEntries)
    }

    private var actualRangeChangeKG: Double? {
        WeightInsightMetrics.actualRangeChangeKG(entries: filteredEntries)
    }

    private var actualDifferenceFromTrendKG: Double? {
        WeightInsightMetrics.actualDifferenceFromTrendKG(
            actualKG: latestEntry?.weightKG,
            trendKG: insights.trendWeightKG,
            currentSampleCount: insights.distinctReadingCount
        )
    }

    private var typicalFluctuationLabel: String {
        WeightInsightMetrics.fluctuationRangeLabel(
            offsetsKG: insights.fluctuationOffsetsKG,
            unitSystem: app.draft.unitSystem
        )
    }

    private var fluctuationContextMessage: String? {
        guard insights.fluctuationStatus == .outsideRecentRange else { return nil }
        let elevated = app.weightNutritionContext?.elevatedNutrients ?? []
        let names = [
            elevated.contains("sodium_mg") ? "sodium" : nil,
            elevated.contains("carbohydrate_g") ? "carbohydrate" : nil,
        ].compactMap { $0 }
        if !names.isEmpty {
            return "Your recent confirmed logs were higher than usual in \(names.joined(separator: " and ")). That can temporarily influence water weight, but Leafy can’t determine the cause of one reading."
        }
        return "Water, stored carbohydrate (glycogen), sodium, hormones, and digestion can all affect a short-term scale reading."
    }

    private var weeklyLearningDetail: String? {
        guard insights.weeklyPaceKG == nil else { return nil }
        let currentNeeded = max(0, WeightTrendInsights.minimumWeeklySamples - insights.currentWindowCount)
        let previousNeeded = max(0, WeightTrendInsights.minimumWeeklySamples - insights.previousWindowCount)
        if currentNeeded > 0 && previousNeeded > 0 {
            return "Leafy needs \(currentNeeded) more current-week and \(previousNeeded) more prior-week check-ins."
        }
        if currentNeeded > 0 { return "Leafy needs \(currentNeeded) more check-in\(currentNeeded == 1 ? "" : "s") in the current seven-day window." }
        return "Leafy needs \(previousNeeded) more check-in\(previousNeeded == 1 ? "" : "s") in the preceding seven-day window."
    }

    private var heroLabel: String {
        selectedDataDate?.formatted(date: .abbreviated, time: .omitted) ?? displayMode.metricTitle
    }

    private var chartScale: WeightChartScale {
        WeightChartScale(
            weightsKG: chartScaleWeightsKG,
            targetKG: app.draft.targetWeightKG,
            goal: app.draft.goal,
            unitSystem: app.draft.unitSystem
        )
    }

    private var chartScaleWeightsKG: [Double] {
        var values = filteredEntries.map(\.weightKG)
        if let offsets = insights.fluctuationOffsetsKG {
            for point in filteredTrendPoints {
                values.append(point.averageKG + offsets.lowerBound)
                values.append(point.averageKG + offsets.upperBound)
            }
        }
        return values
    }

    private var filteredEntries: [WeightEntry] {
        guard let cutoff = chartRange.startDate(relativeTo: .now, calendar: .current) else { return app.weightEntries }
        return app.weightEntries.filter { $0.recordedOn >= cutoff }
    }

    private var chartActualEntries: [WeightEntry] {
        filteredEntries.sorted { $0.recordedOn < $1.recordedOn }
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

private struct WeightExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: WeightView.DisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            HStack(alignment: .top) {
                Text(title)
                    .font(LeafyTypography.title2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: LeafySpacing.small)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(LeafyTypography.icon(15))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss weight explanation")
                .accessibilityIdentifier("dismissTrendWeightExplanation")
            }

            Text(explanation)
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(LeafyTheme.pageInset)
        .background(LeafyTheme.canvas)
    }

    private var title: String {
        switch mode {
        case .trend: "Why Leafy emphasizes trend weight"
        case .actual: "About actual weight"
        }
    }

    private var explanation: String {
        switch mode {
        case .trend:
            "Trend weight is your rolling seven-day average. It reduces the influence of temporary changes from water, sodium, carbohydrates, hormones, and digestion, making longer-term progress easier to see than a single weigh-in."
        case .actual:
            "Actual weight is the reading recorded by your scale. It is useful for seeing each measurement, but water, sodium, carbohydrates, hormones, digestion, and time of day can cause normal short-term changes."
        }
    }
}

private struct FluctuationRangeExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: WeightGoal

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.medium) {
            HStack(alignment: .top) {
                Text("Your typical range")
                    .font(LeafyTypography.title2)
                Spacer(minLength: LeafySpacing.small)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(LeafyTypography.icon(15))
                        .frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss typical range explanation")
            }

            Text("The shaded area shows where most of your daily scale readings typically fall around Leafy’s smoothed seven-reading trend.")
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(goalMessage)
                .font(LeafyTypography.bodyMedium)
                .fixedSize(horizontal: false, vertical: true)

            Text("Water, sodium, carbohydrates, hormones, digestion, and time of day can move an individual reading. One point outside the range does not automatically mean your progress changed.")
                .font(LeafyTypography.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(LeafyTheme.pageInset)
        .background(LeafyTheme.canvas)
    }

    private var goalMessage: String {
        switch goal {
        case .lose:
            "Daily readings can move up and down while the range gradually moves lower toward your goal."
        case .gain:
            "Daily readings can move up and down while the range gradually moves higher toward your goal."
        case .maintain:
            "Daily readings can move up and down while the range remains relatively stable over time."
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
        }
        .frame(minHeight: LeafyTheme.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

private struct WeightHistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var editingEntry: WeightEntry?
    @State private var showingEditor = false

    var body: some View {
        List {
            if app.isWeightLoading && app.weightEntries.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading weights…")
                    Spacer()
                }
                .padding(.vertical, LeafySpacing.xLarge)
            } else {
                ForEach(app.weightEntries) { entry in
                    WeightHistoryRow(entry: entry, unitSystem: app.draft.unitSystem)
                        .contentShape(Rectangle())
                        .onTapGesture { edit(entry) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if entry.source != .baseline {
                                Button("Delete", role: .destructive) {
                                    Task { await app.deleteWeightEntry(entry) }
                                }
                            }
                            Button {
                                edit(entry)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(LeafyTheme.green)
                        }
                }
            }

            if let error = app.weightErrorMessage {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Label(app.weightErrorTitle, systemImage: "exclamationmark.triangle.fill")
                        .font(LeafyTypography.headline)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Refresh history") { Task { await app.loadWeightHistory() } }
                }
                .padding(.vertical, LeafySpacing.small)
            }
        }
        .leafyBorderlessList()
        .navigationTitle("Weight history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showingEditor) {
            WeightEntryEditorView(entry: editingEntry)
        }
        .task {
            if app.weightEntries.isEmpty && !app.isWeightLoading {
                await app.loadWeightHistory()
            }
        }
        .accessibilityIdentifier("weightHistoryView")
    }

    private func edit(_ entry: WeightEntry) {
        editingEntry = entry
        showingEditor = true
    }
}
