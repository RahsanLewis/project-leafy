import Charts
import SwiftUI
import UIKit

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

    @Environment(AppCoordinator.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chartRange: ChartRange = .month
    @State private var selectedChartDate: Date?
    @State private var lastHapticChartDate: Date?
    @State private var editingEntry: WeightEntry?
    @State private var showingEditor = false
    @State private var showingHistory = false
    @State private var showingWeightExplanation = false
    @State private var showingFluctuationExplanation = false
    @State private var showingInsightsExplanation = false
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
                    HStack(spacing: LeafySpacing.xSmall) {
                        Text("Insights")
                            .font(LeafyTypography.title3)

                        Button {
                            showingInsightsExplanation = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(LeafyTypography.icon(14))
                                .foregroundStyle(.secondary)
                                .frame(width: LeafyTheme.minimumTouchTarget, height: LeafyTheme.minimumTouchTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("About weight insights")
                        .accessibilityIdentifier("weightInsightsInfo")
                    }
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
        .listSectionSpacing(LeafySpacing.large)
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
        .sheet(isPresented: $showingInsightsExplanation) {
            WeightInsightsExplanationView()
        }
        .fullScreenCover(isPresented: $showingPlanEditor) {
            PlanEditView(onSaved: {})
        }
        .navigationDestination(isPresented: $showingHistory) {
            WeightHistoryView()
        }
        .overlay(alignment: .top) {
            weightStatusBanner
        }
        .animation(LeafyMotion.state, value: app.weightStatusMessage)
        .onChange(of: chartRange) { _, _ in selectedChartDate = nil }
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
                    Text("Actual weight")
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: LeafyTheme.minimumTouchTarget)
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
                    .accessibilityLabel("About actual weight")
                    .accessibilityIdentifier("actualWeightInfo")
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
            rangeChangeSummaryView
                .padding(.top, 12)
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
                        label: "Actual remaining",
                        value: displayedRemainingKG.map(formatWeight) ?? "Learning"
                    )
                    .padding(.leading, LeafySpacing.medium)
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
        .padding(.top, LeafySpacing.medium)
        .padding(.bottom, LeafySpacing.small)
        .sheet(isPresented: $showingWeightExplanation) {
            WeightExplanationView()
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

    private var chartLegend: some View {
        HStack(spacing: LeafySpacing.large) {
            chartLegendItem(label: "Actual")
            if insights.fluctuationOffsetsKG != nil {
                Button {
                    showingFluctuationExplanation = true
                } label: {
                    HStack(spacing: LeafySpacing.xSmall) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LeafyTheme.green.opacity(0.12))
                            .frame(width: 24, height: 10)
                        Text(fluctuationRangeTitle)
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
            FluctuationRangeExplanationView(
                goal: app.draft.goal
            )
        }
    }

    private func chartLegendItem(label: String) -> some View {
        HStack(spacing: LeafySpacing.xSmall) {
            Capsule()
                .fill(LeafyTheme.green)
                .frame(width: 24, height: 3)
            Text(label)
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var weightChart: some View {
        Chart {
            if let offsets = insights.fluctuationOffsetsKG {
                ForEach(fluctuationBandPoints) { point in
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
                    .interpolationMethod(.monotone)
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
            AxisMarks(values: chartXAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(LeafyTheme.hairline)
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(WeightChartAxis.label(for: date, in: chartDateDomain, calendar: .current))
                            .font(LeafyTypography.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(LeafyTheme.hairline)
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
        .accessibilityLabel(weightChartAccessibilityLabel)
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
                label: "Total change",
                value: actualTotalChangeKG.map(formatChange) ?? "Learning",
                identifier: "totalChange"
            )
            WeightStat(
                label: "Latest change",
                value: actualLatestChangeKG.map(formatChange) ?? "Learning",
                identifier: "latestChange"
            )
            WeightStat(
                label: "Days logged",
                value: planLoggingConsistency.map { "\($0.percentage)%" } ?? "Learning",
                identifier: "daysLogged"
            )
            WeightStat(
                label: "Pace",
                value: paceComparisonLabel,
                identifier: "pace",
                valueColor: paceComparisonColor
            )
        }
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

    private var paceComparisonColor: Color {
        switch insights.paceComparison {
        case .onPace: LeafyTheme.green
        case .fasterThanPlan, .slowerThanPlan, .movingAway: LeafyTheme.danger
        case .learning: .secondary
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

    private var displayedWeightKG: Double? {
        selectedActualEntry?.weightKG ?? latestEntry?.weightKG
    }

    @ViewBuilder
    private var rangeChangeSummaryView: some View {
        if let change = displayedRangeChangeKG {
            HStack(spacing: LeafySpacing.xSmall) {
                Text(rangeChangePrimaryText(change))
                    .foregroundStyle(rangeChangeColor(change))
                Text(rangeChangeSuffix)
                    .foregroundStyle(.secondary)
            }
            .font(LeafyTypography.subheadlineSemibold)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .accessibilityElement(children: .combine)
        } else {
            Text("Add another weigh-in to see \(rangeChangeSuffix) change")
                .font(LeafyTypography.subheadlineSemibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private var rangeChangeSuffix: String {
        switch chartRange {
        case .yearToDate: "YTD"
        case .all: "all time"
        default: "in \(chartRange.rawValue)"
        }
    }

    private func rangeChangePrimaryText(_ changeKG: Double) -> String {
        let value = displayValue(changeKG)
        guard abs(value) >= 0.05 else { return "No change" }
        return "\(value < 0 ? "Down" : "Up") \(String(format: "%.1f", abs(value))) \(unitLabel)"
    }

    private func rangeChangeColor(_ changeKG: Double) -> Color {
        let displayedChange = displayValue(changeKG)
        if abs(displayedChange) < 0.05 {
            return app.draft.goal == .maintain ? LeafyTheme.green : .secondary
        }
        return switch WeightDashboardStats.movement(
            for: changeKG,
            relativeTo: displayedRangeStartKG,
            goal: app.draft.goal
        ) {
        case .towardGoal: LeafyTheme.green
        case .awayFromGoal: LeafyTheme.danger
        case .neutral: .secondary
        }
    }

    private var displayedRangeChangeKG: Double? {
        actualRangeChangeKG
    }

    private var displayedRangeStartKG: Double? {
        chartActualEntries.first?.weightKG
    }

    private var latestEntry: WeightEntry? {
        app.weightEntries.max { $0.recordedOn < $1.recordedOn }
    }

    private var filteredFluctuationCenterPoints: [WeightTrendPoint] {
        guard let cutoff = chartRange.startDate(relativeTo: .now, calendar: .current) else {
            return insights.fluctuationCenterPoints
        }
        return insights.fluctuationCenterPoints.filter { $0.date >= cutoff }
    }

    private var fluctuationBandPoints: [WeightTrendPoint] {
        let points = filteredFluctuationCenterPoints.sorted { $0.date < $1.date }
        guard points.count == 1, let point = points.first else {
            return points
        }
        let calendar = Calendar.current
        let start = chartRange.startDate(relativeTo: point.date, calendar: calendar)
            ?? calendar.date(byAdding: .day, value: -1, to: point.date)
            ?? point.date
        let end = max(
            Date.now,
            calendar.date(byAdding: .day, value: 1, to: point.date) ?? point.date
        )
        return [
            WeightTrendPoint(date: start, averageKG: point.averageKG, sampleCount: point.sampleCount),
            WeightTrendPoint(date: end, averageKG: point.averageKG, sampleCount: point.sampleCount),
        ]
    }

    private var displayedRemainingKG: Double? {
        guard app.draft.goal != .maintain else { return nil }
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

    private var planLoggingConsistency: WeightInsightMetrics.LoggingConsistency? {
        let start = app.currentPlan?.createdAt ?? app.weightEntries.map(\.recordedOn).min()
        return WeightInsightMetrics.loggingConsistency(
            entries: app.weightEntries,
            planStartedAt: start,
            now: .now
        )
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
            for point in filteredFluctuationCenterPoints {
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
        let plottedDates = chartActualEntries.map(\.recordedOn) + fluctuationBandPoints.map(\.date)
        return WeightChartDateDomain.fitted(
            to: plottedDates,
            fallbackStart: chartRange.startDate(relativeTo: now, calendar: .current),
            now: now,
            calendar: .current
        )
    }

    private var fluctuationRangeTitle: String {
        "Typical range"
    }

    private var weightChartAccessibilityLabel: String {
        switch insights.fluctuationRangeSource {
        case .unavailable: "Recorded weight chart"
        case .expected: "Recorded weight chart with an expected daily fluctuation range"
        case .personalized: "Recorded weight chart with your typical daily fluctuation range"
        }
    }

    private var xAxisLabelCount: Int {
        switch chartRange {
        case .week: 4
        case .month, .quarter: 4
        case .yearToDate, .year, .all: 5
        }
    }

    private var chartXAxisDates: [Date] {
        WeightChartAxis.tickDates(
            in: chartDateDomain,
            desiredCount: xAxisLabelCount,
            calendar: .current
        )
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

    @ViewBuilder
    private var weightStatusBanner: some View {
        if !showingEditor,
           !showingPlanEditor,
           let status = app.weightStatusMessage,
           let outcome = app.lastWeightOutcome {
            HStack(spacing: LeafySpacing.compact) {
                Image(systemName: statusIcon(outcome))
                    .font(LeafyTypography.icon(18))
                    .foregroundStyle(outcome == .reviewRequired ? .orange : LeafyTheme.green)

                Text(status)
                    .font(LeafyTypography.subheadlineSemibold)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if outcome == .reviewRequired {
                    Button("Review") {
                        dismissWeightStatus()
                        showingPlanEditor = true
                    }
                        .font(LeafyTypography.subheadlineSemibold)
                        .foregroundStyle(LeafyTheme.green)
                }
            }
            .padding(.horizontal, LeafySpacing.medium)
            .padding(.vertical, LeafySpacing.compact)
            .background(.regularMaterial, in: .rect(cornerRadius: LeafyRadius.control))
            .padding(.horizontal, LeafyTheme.pageInset)
            .padding(.top, LeafySpacing.small)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("weightStatusBanner")
            .task(id: status) {
                let presentedStatus = status
                do {
                    try await Task.sleep(for: .seconds(2.2))
                } catch {
                    return
                }
                guard !Task.isCancelled, app.weightStatusMessage == presentedStatus else { return }
                dismissWeightStatus()
            }
        }
    }

    private func dismissWeightStatus() {
        withAnimation(LeafyMotion.state) {
            app.weightStatusMessage = nil
            app.lastWeightOutcome = nil
        }
    }
}

private struct WeightExplanationView: View {
    var body: some View {
        LeafyInfoSheet(
            title: "About actual weight",
            dismissAccessibilityLabel: "Dismiss weight explanation",
            dismissIdentifier: "dismissWeightExplanation"
        ) {
            Text("Actual weight is the reading recorded by your scale. It is useful for seeing each measurement, but water, sodium, carbohydrates, hormones, digestion, and time of day can cause normal short-term changes.")
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FluctuationRangeExplanationView: View {
    let goal: WeightGoal

    var body: some View {
        LeafyInfoSheet(
            title: "Typical range",
            dismissAccessibilityLabel: "Dismiss fluctuation range explanation",
            dismissIdentifier: "dismissFluctuationRangeExplanation"
        ) {
            Text(explanation)
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fluctuationRangeExplanation")
        }
    }

    private var explanation: String {
        switch goal {
        case .lose:
            "The shaded area represents normal day-to-day weight fluctuations. Focus on the overall direction over time—you want the range to trend downward."
        case .gain:
            "The shaded area represents normal day-to-day weight fluctuations. Focus on the overall direction over time—you want the range to trend upward."
        case .maintain:
            "The shaded area represents normal day-to-day weight fluctuations. Focus on the overall direction over time—you want the range to remain generally stable."
        }
    }
}

private struct WeightInsightsExplanationView: View {
    var body: some View {
        LeafyInfoSheet(
            title: "About insights",
            dismissAccessibilityLabel: "Dismiss weight insights explanation",
            dismissIdentifier: "dismissWeightInsightsExplanation"
        ) {
            insightDefinition(
                id: "totalChange",
                title: "Total change",
                explanation: "The difference between your first and latest recorded weights."
            )
            insightDefinition(
                id: "latestChange",
                title: "Latest change",
                explanation: "The difference between your two most recent weigh-ins. Normal daily fluctuations can affect it."
            )
            insightDefinition(
                id: "daysLogged",
                title: "Days logged",
                explanation: "The percentage of days since your current plan began that include a weigh-in."
            )
            insightDefinition(
                id: "pace",
                title: "Pace",
                explanation: "How your weekly weight direction compares with your current plan."
            )
        }
        .accessibilityIdentifier("weightInsightsExplanation")
    }

    private func insightDefinition(id: String, title: String, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text(title)
                .font(LeafyTypography.headline)
            Text(explanation)
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weightInsightDefinition-\(id)")
    }
}

private struct WeightStat: View {
    let label: String
    let value: String
    let identifier: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text(label)
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(LeafyTypography.headline)
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .accessibilityLabel("\(label), \(value)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("weightInsight-\(identifier)")
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
    @Environment(AppCoordinator.self) private var app
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
