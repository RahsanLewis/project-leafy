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

struct WeightTrendInsights: Equatable, Sendable {
    let trendWeightKG: Double?
    let periodChangeKG: Double?
    let weeklyPaceKG: Double?
    let paceComparison: WeightPaceComparison
    let consistency: Double?
    let weighInDayCount: Int
    let periodDayCount: Int
    let goalForecast: WeightGoalForecast

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
        let earliest = ordered.first
        let latest = ordered.last

        if let latest {
            let trendStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: latest.recordedOn)) ?? .distantPast
            let trendEntries = ordered.filter { $0.recordedOn >= trendStart && $0.recordedOn <= latest.recordedOn }
            trendWeightKG = trendEntries.map(\.weightKG).reduce(0, +) / Double(trendEntries.count)
        } else {
            trendWeightKG = nil
        }

        periodChangeKG = earliest.flatMap { first in latest.map { $0.weightKG - first.weightKG } }
        weighInDayCount = ordered.count

        let effectiveStart = periodStart ?? earliest?.recordedOn
        let effectiveEnd = periodStart == nil ? (latest?.recordedOn ?? periodEnd) : periodEnd
        if let effectiveStart {
            periodDayCount = max(1, Self.daySpan(from: effectiveStart, to: effectiveEnd, calendar: calendar) + 1)
            consistency = min(Double(weighInDayCount) / Double(periodDayCount), 1)
        } else {
            periodDayCount = 0
            consistency = nil
        }

        let span = earliest.flatMap { first in latest.map { Self.daySpan(from: first.recordedOn, to: $0.recordedOn, calendar: calendar) } } ?? 0
        if ordered.count >= 3, span >= 7 {
            weeklyPaceKG = Self.theilSenDailySlope(ordered, calendar: calendar).map { $0 * 7 }
        } else {
            weeklyPaceKG = nil
        }

        paceComparison = Self.paceComparison(
            weeklyPaceKG: weeklyPaceKG,
            plannedWeeklyChangeKG: plannedWeeklyChangeKG,
            goal: goal
        )

        if goal == .maintain {
            goalForecast = .ongoing
        } else if ordered.count < 7 || span < 14 || weeklyPaceKG == nil {
            goalForecast = .learning
        } else if let pace = weeklyPaceKG, let targetKG, let latest {
            let movingTowardGoal = goal == .lose ? pace < 0 : pace > 0
            guard movingTowardGoal, abs(pace) > 0.0001 else {
                goalForecast = .notTrendingTowardGoal
                return
            }
            let weeks = abs(targetKG - latest.weightKG) / abs(pace)
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

    private static func theilSenDailySlope(_ entries: [WeightEntry], calendar: Calendar) -> Double? {
        var slopes: [Double] = []
        for firstIndex in entries.indices {
            for secondIndex in entries.indices where secondIndex > firstIndex {
                let days = daySpan(
                    from: entries[firstIndex].recordedOn,
                    to: entries[secondIndex].recordedOn,
                    calendar: calendar
                )
                guard days > 0 else { continue }
                slopes.append((entries[secondIndex].weightKG - entries[firstIndex].weightKG) / Double(days))
            }
        }
        guard !slopes.isEmpty else { return nil }
        slopes.sort()
        let middle = slopes.count / 2
        return slopes.count.isMultiple(of: 2) ? (slopes[middle - 1] + slopes[middle]) / 2 : slopes[middle]
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
        var values = weightsKG.map(convert)
        if goal != .maintain, let targetKG { values.append(convert(targetKG)) }

        let fallback = targetKG.map(convert) ?? (unitSystem == .imperial ? 170 : 77)
        let minimum = values.min() ?? fallback
        let maximum = values.max() ?? fallback
        let contentSpan = maximum - minimum
        let minimumSpan = unitSystem == .imperial ? 10.0 : 5.0
        let plotSpan = max(contentSpan * 1.2, minimumSpan)
        let midpoint = (minimum + maximum) / 2

        domain = (midpoint - plotSpan / 2)...(midpoint + plotSpan / 2)
    }
}
