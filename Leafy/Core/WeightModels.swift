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
