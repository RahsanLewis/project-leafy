import Foundation

actor PlanCache {
    static let currentVersion = 2

    struct State: Sendable {
        let plan: NutritionPlan
        let input: NutritionPlanInput
    }

    private let url: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            url = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            url = base.appending(path: "leafy-current-plan.json")
        }
    }

    func load(timeZone: TimeZone = .current) -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let v2 = decodeV2(data) {
            return State(plan: v2.plan, input: v2.input)
        }
        if let legacy = decodeV1(data) {
            do {
                let migrated = try migrate(legacy, timeZone: timeZone)
                try save(migrated.plan, input: migrated.input)
                return migrated
            } catch {
                clear()
                return nil
            }
        }
        clear()
        return nil
    }

    func save(_ plan: NutritionPlan, input: NutritionPlanInput) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(EnvelopeV2(version: Self.currentVersion, plan: plan, input: input))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }

    private func decodeV2(_ data: Data) -> EnvelopeV2? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(EnvelopeV2.self, from: data),
              envelope.version == Self.currentVersion
        else { return nil }
        return envelope
    }

    private func decodeV1(_ data: Data) -> LegacyV1State? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LegacyV1State.self, from: data)
    }

    private func migrate(_ legacy: LegacyV1State, timeZone: TimeZone) throws -> State {
        let input = try legacy.input.asCurrent(timeZone: timeZone)
        let snapshot = try legacy.plan.inputSnapshot?.asCurrent(timeZone: timeZone)
        let estimatedGoalDate: LocalDate?
        if let instant = legacy.plan.estimatedGoalDate {
            guard let displayed = LocalDate.displayed(from: instant, timeZone: timeZone) else {
                throw LegacyMigrationError.invalidDisplayedDate
            }
            estimatedGoalDate = displayed
        } else {
            estimatedGoalDate = nil
        }
        let plan = NutritionPlan(
            id: legacy.plan.id,
            revision: legacy.plan.revision,
            calculatorVersion: legacy.plan.calculatorVersion,
            bmrKcal: legacy.plan.bmrKcal,
            tdeeKcal: legacy.plan.tdeeKcal,
            calorieTargetKcal: legacy.plan.calorieTargetKcal,
            proteinG: legacy.plan.proteinG,
            carbohydrateG: legacy.plan.carbohydrateG,
            fatG: legacy.plan.fatG,
            projectedWeeklyChangeKG: legacy.plan.projectedWeeklyChangeKG,
            estimatedGoalDate: estimatedGoalDate,
            createdAt: legacy.plan.createdAt,
            inputSnapshot: snapshot
        )
        return State(plan: plan, input: input)
    }
}

private enum LegacyMigrationError: Error {
    case invalidDisplayedDate
}

private struct EnvelopeV2: Codable {
    var version: Int
    var plan: NutritionPlan
    var input: NutritionPlanInput
}

/// Dedicated v1 on-disk shape. Dates are ISO8601 instants from the previous cache.
private struct LegacyV1State: Codable {
    var plan: LegacyV1Plan
    var input: LegacyV1Input
}

private struct LegacyV1Plan: Codable {
    var id: UUID
    var revision: Int
    var calculatorVersion: String
    var bmrKcal: Int
    var tdeeKcal: Int
    var calorieTargetKcal: Int
    var proteinG: Int
    var carbohydrateG: Int
    var fatG: Int
    var projectedWeeklyChangeKG: Double
    var estimatedGoalDate: Date?
    var createdAt: Date
    var inputSnapshot: LegacyV1Input?

    enum CodingKeys: String, CodingKey {
        case id, revision
        case calculatorVersion = "calculator_version"
        case bmrKcal = "bmr_kcal"
        case tdeeKcal = "tdee_kcal"
        case calorieTargetKcal = "calorie_target_kcal"
        case proteinG = "protein_g"
        case carbohydrateG = "carbohydrate_g"
        case fatG = "fat_g"
        case projectedWeeklyChangeKG = "projected_weekly_change_kg"
        case estimatedGoalDate = "estimated_goal_date"
        case createdAt = "created_at"
        case inputSnapshot = "input_snapshot"
    }
}

private struct LegacyV1Input: Codable {
    var birthDate: Date
    var calculationSex: CalculationSex
    var heightCM: Double
    var currentWeightKG: Double
    var targetWeightKG: Double?
    var activityLevel: ActivityLevel
    var goal: WeightGoal
    var pace: GoalPace
    var unitSystem: UnitSystem

    enum CodingKeys: String, CodingKey {
        case birthDate = "birth_date"
        case calculationSex = "calculation_sex"
        case heightCM = "height_cm"
        case currentWeightKG = "current_weight_kg"
        case targetWeightKG = "target_weight_kg"
        case activityLevel = "activity_level"
        case goal, pace
        case unitSystem = "unit_system"
    }

    func asCurrent(timeZone: TimeZone) throws -> NutritionPlanInput {
        guard let birthDate = LocalDate.displayed(from: birthDate, timeZone: timeZone) else {
            throw LegacyMigrationError.invalidDisplayedDate
        }
        return NutritionPlanInput(
            birthDate: birthDate,
            calculationSex: calculationSex,
            heightCM: heightCM,
            currentWeightKG: currentWeightKG,
            targetWeightKG: targetWeightKG,
            activityLevel: activityLevel,
            goal: goal,
            pace: pace,
            unitSystem: unitSystem
        )
    }
}
