import Foundation

struct WeightEntry: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case baseline, manual }

    let id: UUID
    let userID: UUID
    var weightKG: Double
    var recordedOn: Date
    var timeZone: String
    let source: Source
    var planID: UUID?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, source
        case userID = "user_id"
        case weightKG = "weight_kg"
        case recordedOn = "recorded_on"
        case timeZone = "time_zone"
        case planID = "plan_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum WeightMutationOutcome: String, Codable, Sendable {
    case tracked
    case planUpdated = "plan_updated"
    case goalReached = "goal_reached"
    case reviewRequired = "review_required"
}

struct WeightMutationResponse: Codable, Sendable {
    let entry: WeightEntry?
    let currentEntry: WeightEntry
    let plan: NutritionPlan?
    let planInput: NutritionPlanInput?
    let planUpdated: Bool
    let outcome: WeightMutationOutcome

    enum CodingKeys: String, CodingKey {
        case entry, plan, outcome
        case currentEntry = "current_entry"
        case planInput = "plan_input"
        case planUpdated = "plan_updated"
    }
}

struct WeightNutritionContext: Codable, Equatable, Sendable {
    let available: Bool
    let confirmedDayCount: Int
    let elevatedNutrients: [String]

    enum CodingKeys: String, CodingKey {
        case available
        case confirmedDayCount = "confirmed_day_count"
        case elevatedNutrients = "elevated_nutrients"
    }
}

struct WeightProgress: Equatable, Sendable {
    let latestKG: Double?
    let previousKG: Double?
    let startingKG: Double?
    let targetKG: Double?
    let goal: WeightGoal

    var changeFromPreviousKG: Double? {
        guard let latestKG, let previousKG else { return nil }
        return latestKG - previousKG
    }

    var remainingKG: Double? {
        guard let latestKG, let targetKG, goal != .maintain else { return nil }
        return abs(targetKG - latestKG)
    }

    var progress: Double? {
        guard let latestKG, let startingKG, let targetKG, goal != .maintain else { return nil }
        let total = abs(targetKG - startingKG)
        guard total > 0 else { return 1 }
        let completed = goal == .lose ? startingKG - latestKG : latestKG - startingKG
        return min(max(completed / total, 0), 1)
    }
}

enum WeightMovement: Equatable, Sendable {
    case towardGoal, awayFromGoal, neutral
}

struct WeightDashboardStats: Equatable, Sendable {
    let startingKG: Double?
    let targetKG: Double?
    let totalChangeKG: Double?
    let remainingKG: Double?
    let projectedWeeklyChangeKG: Double?
    let estimatedGoalDate: Date?
    let goal: WeightGoal

    init(
        entries: [WeightEntry],
        targetKG: Double?,
        goal: WeightGoal,
        projectedWeeklyChangeKG: Double?,
        estimatedGoalDate: Date?
    ) {
        let ordered = entries.sorted { $0.recordedOn < $1.recordedOn }
        startingKG = ordered.first?.weightKG
        let latestKG = ordered.last?.weightKG
        self.goal = goal
        self.targetKG = goal == .maintain ? nil : targetKG
        totalChangeKG = startingKG.flatMap { start in latestKG.map { $0 - start } }
        remainingKG = goal == .maintain ? nil : latestKG.flatMap { latest in targetKG.map { abs($0 - latest) } }
        self.projectedWeeklyChangeKG = goal == .maintain ? 0 : projectedWeeklyChangeKG
        self.estimatedGoalDate = goal == .maintain ? nil : estimatedGoalDate
    }

    static func movement(for changeKG: Double?, goal: WeightGoal) -> WeightMovement {
        guard let changeKG, abs(changeKG) > 0.0001, goal != .maintain else { return .neutral }
        switch goal {
        case .lose: return changeKG < 0 ? .towardGoal : .awayFromGoal
        case .gain: return changeKG > 0 ? .towardGoal : .awayFromGoal
        case .maintain: return .neutral
        }
    }
}

enum WeightPaceComparison: Equatable, Sendable {
    case learning, onPace, fasterThanPlan, slowerThanPlan, movingAway
}

enum WeightGoalForecast: Equatable, Sendable {
    case learning, ongoing, notTrendingTowardGoal, date(Date)
}

struct WeightTrendPoint: Equatable, Identifiable, Sendable {
    let date: Date
    let averageKG: Double
    let sampleCount: Int

    var id: Date { date }
}

enum WeightFluctuationStatus: Equatable, Sendable {
    case learning
    case withinRecentRange
    case outsideRecentRange
}

struct WeightTrendInsights: Equatable, Sendable {
    let trendWeightKG: Double?
    let previousTrendWeightKG: Double?
    let periodChangeKG: Double?
    let weeklyPaceKG: Double?
    let paceComparison: WeightPaceComparison
    let consistency: Double?
    let weighInDayCount: Int
    let periodDayCount: Int
    let goalForecast: WeightGoalForecast
    let currentWindowCount: Int
    let previousWindowCount: Int
    let trendPoints: [WeightTrendPoint]
    let latestDeviationKG: Double?
    let fluctuationStatus: WeightFluctuationStatus
    let fluctuationOffsetsKG: ClosedRange<Double>?
    let distinctReadingCount: Int

    static let minimumWeeklySamples = 4
    static let minimumTrendReadings = 7

    var hasTrend: Bool { distinctReadingCount >= Self.minimumTrendReadings }

    init(
        entries: [WeightEntry],
        periodStart: Date?,
        periodEnd: Date,
        targetKG: Double?,
        goal: WeightGoal,
        plannedWeeklyChangeKG: Double?,
        calendar: Calendar = .current
    ) {
        let dailyEntries = Self.dailyEntries(entries, calendar: calendar)
        let ordered = dailyEntries.sorted { $0.recordedOn < $1.recordedOn }
        distinctReadingCount = ordered.count
        let latest = ordered.last
        let anchor = calendar.startOfDay(for: latest?.recordedOn ?? periodEnd)
        let currentStart = calendar.date(byAdding: .day, value: -6, to: anchor) ?? anchor
        let previousEnd = calendar.date(byAdding: .day, value: -7, to: anchor) ?? anchor
        let previousStart = calendar.date(byAdding: .day, value: -13, to: anchor) ?? previousEnd
        let currentEntries = ordered.filter { $0.recordedOn >= currentStart && $0.recordedOn <= anchor }
        let previousEntries = ordered.filter { $0.recordedOn >= previousStart && $0.recordedOn <= previousEnd }
        currentWindowCount = currentEntries.count
        previousWindowCount = previousEntries.count
        let currentWeeklyAverageKG = Self.average(currentEntries)
        let rollingTrendEntries = Array(ordered.suffix(Self.minimumTrendReadings))
        let currentTrendWeightKG = ordered.count >= Self.minimumTrendReadings
            ? Self.average(rollingTrendEntries)
            : nil
        let priorTrendWeightKG = Self.average(previousEntries)
        trendWeightKG = currentTrendWeightKG
        previousTrendWeightKG = priorTrendWeightKG

        if currentEntries.count >= Self.minimumWeeklySamples,
           previousEntries.count >= Self.minimumWeeklySamples,
           let current = currentWeeklyAverageKG,
           let previous = priorTrendWeightKG {
            weeklyPaceKG = current - previous
            periodChangeKG = current - previous
        } else {
            weeklyPaceKG = nil
            periodChangeKG = nil
        }

        trendPoints = ordered.indices.compactMap { index in
            guard index + 1 >= Self.minimumTrendReadings else { return nil }
            let window = Array(ordered[(index + 1 - Self.minimumTrendReadings)...index])
            guard let average = Self.average(window) else { return nil }
            return WeightTrendPoint(
                date: calendar.startOfDay(for: ordered[index].recordedOn),
                averageKG: average,
                sampleCount: window.count
            )
        }

        let residualCutoff = calendar.date(byAdding: .day, value: -27, to: anchor) ?? .distantPast
        let recentEntries = ordered.filter { $0.recordedOn >= residualCutoff && $0.recordedOn <= anchor }
        let recentIDs = Set(recentEntries.map(\.id))
        let trendsByDate = Dictionary(uniqueKeysWithValues: trendPoints.map { ($0.date, $0.averageKG) })
        let residuals = ordered
            .filter { recentIDs.contains($0.id) }
            .compactMap { entry in
                trendsByDate[calendar.startOfDay(for: entry.recordedOn)].map { entry.weightKG - $0 }
            }
            .sorted()
        latestDeviationKG = latest.flatMap { latest in currentTrendWeightKG.map { latest.weightKG - $0 } }
        if residuals.count >= 14,
           let lower = Self.quantile(residuals, percentile: 0.10),
           let upper = Self.quantile(residuals, percentile: 0.90) {
            fluctuationOffsetsKG = lower...upper
            if let deviation = latestDeviationKG, deviation >= lower, deviation <= upper {
                fluctuationStatus = .withinRecentRange
            } else {
                fluctuationStatus = .outsideRecentRange
            }
        } else {
            fluctuationOffsetsKG = nil
            fluctuationStatus = .learning
        }

        let periodEntries = ordered.filter { entry in
            guard let periodStart else { return true }
            return entry.recordedOn >= periodStart && entry.recordedOn <= periodEnd
        }
        weighInDayCount = periodEntries.count

        let effectiveStart = periodStart ?? periodEntries.first?.recordedOn
        let effectiveEnd = periodStart == nil ? (latest?.recordedOn ?? periodEnd) : periodEnd
        if let effectiveStart {
            periodDayCount = max(1, Self.daySpan(from: effectiveStart, to: effectiveEnd, calendar: calendar) + 1)
            consistency = min(Double(weighInDayCount) / Double(periodDayCount), 1)
        } else {
            periodDayCount = 0
            consistency = nil
        }

        paceComparison = Self.paceComparison(
            weeklyPaceKG: weeklyPaceKG,
            plannedWeeklyChangeKG: plannedWeeklyChangeKG,
            goal: goal
        )

        if goal == .maintain {
            goalForecast = .ongoing
        } else if weeklyPaceKG == nil {
            goalForecast = .learning
        } else if let pace = weeklyPaceKG, let targetKG, let latest {
            let movingTowardGoal = goal == .lose ? pace < 0 : pace > 0
            guard movingTowardGoal, abs(pace) > 0.0001 else {
                goalForecast = .notTrendingTowardGoal
                return
            }
            let referenceWeight = currentTrendWeightKG ?? latest.weightKG
            let weeks = abs(targetKG - referenceWeight) / abs(pace)
            let days = Int(ceil(weeks * 7 - 1e-9))
            goalForecast = .date(calendar.date(byAdding: .day, value: days, to: periodEnd) ?? periodEnd)
        } else {
            goalForecast = .learning
        }
    }

    private static func dailyEntries(_ entries: [WeightEntry], calendar: Calendar) -> [WeightEntry] {
        let ordered = entries.sorted { $0.recordedOn < $1.recordedOn }
        return Dictionary(grouping: ordered, by: { calendar.startOfDay(for: $0.recordedOn) })
            .compactMap { $0.value.last }
    }

    private static func average(_ entries: [WeightEntry]) -> Double? {
        guard !entries.isEmpty else { return nil }
        return entries.map(\.weightKG).reduce(0, +) / Double(entries.count)
    }

    private static func quantile(_ sorted: [Double], percentile: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let position = min(max(percentile, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    private static func paceComparison(
        weeklyPaceKG: Double?,
        plannedWeeklyChangeKG: Double?,
        goal: WeightGoal
    ) -> WeightPaceComparison {
        guard let actual = weeklyPaceKG else { return .learning }
        if goal == .maintain {
            return abs(actual) <= 0.1 ? .onPace : .movingAway
        }
        guard let plannedMagnitude = plannedWeeklyChangeKG, plannedMagnitude > 0 else { return .learning }
        let movingTowardGoal = goal == .lose ? actual < 0 : actual > 0
        guard movingTowardGoal else { return .movingAway }
        let ratio = abs(actual) / abs(plannedMagnitude)
        if ratio < 0.8 { return .slowerThanPlan }
        if ratio > 1.2 { return .fasterThanPlan }
        return .onPace
    }

    private static func daySpan(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }
}

struct WeightChartScale: Equatable, Sendable {
    let domain: ClosedRange<Double>

    init(weightsKG: [Double], targetKG: Double?, goal: WeightGoal, unitSystem: UnitSystem) {
        let convert: (Double) -> Double = unitSystem == .imperial ? { $0 * 2.20462 } : { $0 }
        let values = weightsKG.map(convert)

        let fallback = goal == .maintain ? nil : targetKG.map(convert)
        let fallbackValue = fallback ?? (unitSystem == .imperial ? 170 : 77)
        let minimum = values.min() ?? fallbackValue
        let maximum = values.max() ?? fallbackValue
        let contentSpan = maximum - minimum
        let minimumSpan = unitSystem == .imperial ? 10.0 : 5.0
        let plotSpan = max(contentSpan * 1.2, minimumSpan)
        let midpoint = (minimum + maximum) / 2

        domain = (midpoint - plotSpan / 2)...(midpoint + plotSpan / 2)
    }
}

struct WeightInsightMetrics {
    static func totalProgressKG(
        startingKG: Double?,
        trendWeightKG: Double?,
        currentSampleCount: Int
    ) -> Double? {
        guard currentSampleCount >= WeightTrendInsights.minimumTrendReadings,
              let startingKG,
              let trendWeightKG else { return nil }
        return trendWeightKG - startingKG
    }

    static func fluctuationRangeLabel(
        offsetsKG: ClosedRange<Double>?,
        unitSystem: UnitSystem
    ) -> String {
        guard let offsetsKG else { return "Learning" }
        let conversion = unitSystem == .imperial ? 2.20462 : 1
        let unit = unitSystem == .imperial ? "lb" : "kg"
        return "\(signed(offsetsKG.lowerBound * conversion)) to \(signed(offsetsKG.upperBound * conversion)) \(unit)"
    }

    static func actualTotalChangeKG(entries: [WeightEntry]) -> Double? {
        changeAcross(entries: entries)
    }

    static func actualLatestChangeKG(entries: [WeightEntry]) -> Double? {
        let ordered = entries.sorted { $0.recordedOn < $1.recordedOn }
        guard ordered.count >= 2, let previous = ordered.dropLast().last, let latest = ordered.last else { return nil }
        return latest.weightKG - previous.weightKG
    }

    static func actualRangeChangeKG(entries: [WeightEntry]) -> Double? {
        changeAcross(entries: entries)
    }

    static func actualDifferenceFromTrendKG(
        actualKG: Double?,
        trendKG: Double?,
        currentSampleCount: Int
    ) -> Double? {
        guard currentSampleCount >= WeightTrendInsights.minimumTrendReadings,
              let actualKG,
              let trendKG else { return nil }
        return actualKG - trendKG
    }

    private static func changeAcross(entries: [WeightEntry]) -> Double? {
        let ordered = entries.sorted { $0.recordedOn < $1.recordedOn }
        guard ordered.count >= 2, let first = ordered.first, let last = ordered.last else { return nil }
        return last.weightKG - first.weightKG
    }

    private static func signed(_ value: Double) -> String {
        if abs(value) < 0.05 { return "0.0" }
        return String(format: value > 0 ? "+%.1f" : "−%.1f", abs(value))
    }
}
