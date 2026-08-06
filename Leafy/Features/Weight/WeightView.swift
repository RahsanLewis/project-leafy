import Charts
import SwiftUI

struct WeightView: View {
    enum ChartRange: String, CaseIterable { case month = "1M", quarter = "3M", all = "All" }

    @Environment(AppModel.self) private var app
    @State private var chartRange: ChartRange = .month
    @State private var selectedEntryID: UUID?
    @State private var editingEntry: WeightEntry?
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                hero
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let status = app.weightStatusMessage, let outcome = app.lastWeightOutcome {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(status, systemImage: statusIcon(outcome))
                            .font(.headline)
                            .foregroundStyle(outcome == .reviewRequired ? .orange : LeafyTheme.green)
                        if outcome == .reviewRequired {
                            Button("Review Plan") { app.editPlan() }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if filteredEntries.isEmpty {
                    ContentUnavailableView("No weight history", systemImage: "chart.line.uptrend.xyaxis", description: Text("Log your weight to begin tracking progress."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: LeafySpacing.compact) {
                        weightChart.frame(height: 200)
                        chartRangePicker
                    }
                    .padding(.vertical, LeafySpacing.small)
                }
            }

            Section("Stats") {
                statsGrid
                    .padding(.vertical, LeafySpacing.small)
            }

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

            if let error = app.weightErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("We couldn’t update your weight", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(.orange)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await app.loadWeightHistory() } }
                    }.padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(LeafySpacing.xLarge)
        .contentMargins(.top, LeafySpacing.medium, for: .scrollContent)
        .contentMargins(.bottom, LeafySpacing.medium, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button("Log Weight") { editingEntry = nil; showingEditor = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, LeafySpacing.compact)
                .padding(.bottom, LeafySpacing.small)
                .background(.regularMaterial)
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
        return VStack(alignment: .leading, spacing: LeafySpacing.compact) {
            Text(heroLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(displayedEntry.map { formatWeight($0.weightKG) } ?? "—")
                .font(.system(size: 52, weight: .bold, design: LeafyTheme.fontDesign))
                .contentTransition(.numericText())
            if let change = rangeChangeKG {
                Label(rangeChangeLabel(change), systemImage: changeIcon(change))
                    .font(.headline)
                    .foregroundStyle(changeColor(change))
            }
            if let value = progress.progress, let remaining = progress.remainingKG {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    ProgressView(value: value).tint(LeafyTheme.green)
                    HStack {
                        Text("\(Int((value * 100).rounded()))% complete")
                        Spacer()
                        Text("\(formatWeightValue(remaining)) to target")
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Label("Maintenance progress", systemImage: "equal.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(LeafyTheme.green)
            }
        }
        .padding(.vertical, LeafySpacing.small)
        .accessibilityIdentifier("weightSummaryCard")
    }

    private var weightChart: some View {
        Chart {
            ForEach(filteredEntries.reversed()) { entry in
                LineMark(x: .value("Date", entry.recordedOn), y: .value("Weight", displayValue(entry.weightKG)))
                    .foregroundStyle(LeafyTheme.green)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", entry.recordedOn), y: .value("Weight", displayValue(entry.weightKG)))
                    .foregroundStyle(LeafyTheme.green)
            }
            if app.draft.goal != .maintain {
                RuleMark(y: .value("Target", displayValue(app.draft.targetWeightKG)))
                    .foregroundStyle(.secondary)
                    .lineStyle(.init(lineWidth: 1, dash: [5]))
                    .annotation(position: .top, alignment: .leading) { Text("Target").font(.caption2).foregroundStyle(.secondary) }
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
        .chartYAxisLabel(app.draft.unitSystem == .imperial ? "lb" : "kg")
        .chartYScale(domain: chartScale.domain)
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
        HStack(spacing: LeafySpacing.small) {
            ForEach(ChartRange.allCases, id: \.self) { range in
                Button {
                    chartRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LeafySpacing.small)
                        .foregroundStyle(chartRange == range ? LeafyTheme.green : .primary)
                        .background(
                            chartRange == range ? LeafyTheme.mint : Color.clear,
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chartRange == range ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart range")
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: LeafySpacing.large
        ) {
            WeightStat(label: "Starting weight", value: stats.startingKG.map(formatWeight) ?? "—")
            WeightStat(label: "Target weight", value: targetStatValue)
            WeightStat(label: "Total change", value: stats.totalChangeKG.map(formatChange) ?? "—")
            WeightStat(label: "Remaining", value: remainingStatValue)
            WeightStat(label: "Weekly target", value: weeklyTargetStatValue)
            WeightStat(label: "Estimated goal", value: goalDateStatValue)
        }
    }

    private var stats: WeightDashboardStats {
        WeightDashboardStats(
            entries: app.weightEntries,
            targetKG: app.draft.targetWeightKG,
            goal: app.draft.goal,
            projectedWeeklyChangeKG: app.currentPlan?.projectedWeeklyChangeKG,
            estimatedGoalDate: app.currentPlan?.estimatedGoalDate
        )
    }

    private var targetStatValue: String {
        app.draft.goal == .maintain ? "Maintain" : stats.targetKG.map(formatWeight) ?? "—"
    }

    private var remainingStatValue: String {
        app.draft.goal == .maintain ? "—" : stats.remainingKG.map(formatWeight) ?? "—"
    }

    private var weeklyTargetStatValue: String {
        guard app.draft.goal != .maintain else { return "Stable" }
        guard let weekly = stats.projectedWeeklyChangeKG else { return "—" }
        let direction = app.draft.goal == .lose ? "−" : "+"
        return "\(direction)\(formatWeightValue(weekly)) \(unitLabel)/week"
    }

    private var goalDateStatValue: String {
        guard app.draft.goal != .maintain else { return "Ongoing" }
        return stats.estimatedGoalDate?.formatted(date: .abbreviated, time: .omitted) ?? "—"
    }

    private var selectedEntry: WeightEntry? {
        guard let selectedEntryID else { return nil }
        return filteredEntries.first { $0.id == selectedEntryID }
    }

    private var displayedEntry: WeightEntry? { selectedEntry ?? filteredEntries.first ?? app.weightEntries.first }

    private var rangeStartEntry: WeightEntry? { filteredEntries.last }

    private var rangeChangeKG: Double? {
        guard let displayedEntry, let rangeStartEntry else { return nil }
        return displayedEntry.weightKG - rangeStartEntry.weightKG
    }

    private var heroLabel: String {
        selectedEntry?.recordedOn.formatted(date: .abbreviated, time: .omitted) ?? "Current weight"
    }

    private func rangeChangeLabel(_ changeKG: Double) -> String {
        guard let start = rangeStartEntry else { return formatChange(changeKG) }
        if abs(changeKG) < 0.0001 { return "Start of selected range" }
        return "\(formatChange(changeKG)) since \(start.recordedOn.formatted(date: .abbreviated, time: .omitted))"
    }

    private func changeIcon(_ changeKG: Double) -> String {
        if abs(changeKG) < 0.0001 { return "minus" }
        return changeKG > 0 ? "arrow.up.right" : "arrow.down.right"
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
        guard chartRange != .all else { return app.weightEntries }
        let days = chartRange == .month ? -30 : -90
        let cutoff = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .distantPast
        return app.weightEntries.filter { $0.recordedOn >= cutoff }
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

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.xSmall) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WeightHistoryRow: View {
    let entry: WeightEntry
    let unitSystem: UnitSystem
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.recordedOn.formatted(date: .abbreviated, time: .omitted)).font(.body.weight(.medium))
                if entry.source == .baseline { Text("Starting weight").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(String(format: "%.1f %@", unitSystem == .imperial ? entry.weightKG * 2.20462 : entry.weightKG, unitSystem == .imperial ? "lb" : "kg"))
                .font(.headline.monospacedDigit())
        }.padding(.vertical, 5)
    }
}
