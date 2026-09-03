import Foundation

enum WeightGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case lose, maintain, gain
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .lose: "Create a sustainable calorie deficit"
        case .maintain: "Support your current weight"
        case .gain: "Create a controlled calorie surplus"
        }
    }
}

enum CalculationSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case female, male
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case sedentary, light, moderate, veryActive = "very_active", athlete
    var id: Self { self }
    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .veryActive: 1.725
        case .athlete: 1.9
        }
    }
    var title: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .veryActive: "Very active"
        case .athlete: "Athlete-level"
        }
    }
    var detail: String {
        switch self {
        case .sedentary: "Mostly seated; little intentional exercise"
        case .light: "Light exercise 1–3 days each week"
        case .moderate: "Moderate exercise 3–5 days each week"
        case .veryActive: "Hard exercise 6–7 days each week"
        case .athlete: "Very hard training or a physical job"
        }
    }
}

enum GoalPace: String, Codable, CaseIterable, Identifiable, Sendable {
    case gentle, steady, faster
    var id: Self { self }
    var title: String { rawValue.capitalized }
    func adjustment(for goal: WeightGoal) -> Double {
        switch (goal, self) {
        case (.lose, .gentle): -0.10
        case (.lose, .steady): -0.15
        case (.lose, .faster): -0.20
        case (.gain, .gentle): 0.05
        case (.gain, .steady): 0.10
        case (.gain, .faster): 0.15
        case (.maintain, _): 0
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case imperial, metric
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct NutritionPlanInput: Codable, Equatable, Sendable {
    /// Civil birth date. `nil` only for pending onboarding recovery that has
    /// no user-selected or successfully migrated YMD — never an invented date.
    var birthDate: LocalDate?
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
}

struct NutritionPlan: Codable, Equatable, Sendable, Identifiable {
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
    var estimatedGoalDate: LocalDate?
    var createdAt: Date
    /// Goal and inputs the plan was computed from. Optional so PlanCache
    /// records written before this field still decode.
    var inputSnapshot: NutritionPlanInput? = nil

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

    /// Snapshot `goal` only. Never inferred from target presence or absence.
    var snapshotGoal: WeightGoal? { inputSnapshot?.goal }

    /// True only when the snapshot's own goal is a change goal and matches the live draft.
    /// Missing snapshot (pre-upgrade cache) suppresses pace.
    func showsProjectedPace(draftGoal: WeightGoal) -> Bool {
        guard let snapshotGoal else { return false }
        return snapshotGoal != .maintain && snapshotGoal == draftGoal
    }

    /// Formats the stored weekly change. Does not recompute from target or draft.
    func projectedPaceLabel(draftGoal: WeightGoal, unitSystem: UnitSystem) -> String? {
        guard showsProjectedPace(draftGoal: draftGoal) else { return nil }
        let amount = unitSystem == .imperial
            ? projectedWeeklyChangeKG * 2.20462
            : projectedWeeklyChangeKG
        let number = unitSystem == .imperial
            ? String(format: "%.1f", amount)
            : String(format: "%.2f", amount)
        return "\(number) \(unitSystem == .imperial ? "lb" : "kg") per week"
    }

    /// Same gate as pace: a lose plan's date must not render against a gain draft.
    func displayedEstimatedGoalDate(draftGoal: WeightGoal) -> LocalDate? {
        guard showsProjectedPace(draftGoal: draftGoal) else { return nil }
        return estimatedGoalDate
    }
}

enum PlanValidationError: LocalizedError, Equatable {
    case invalidAge, invalidHeight, invalidWeight, missingTarget, conflictingTarget
    case underweightLossGoal, noSafeDeficit

    var errorDescription: String? {
        switch self {
        case .invalidAge: "Leafy currently supports adults ages 18 through 100."
        case .invalidHeight: "Enter a height between 120 and 230 cm."
        case .invalidWeight: "Enter a weight between 35 and 350 kg."
        case .missingTarget: "Choose a target weight for this goal."
        case .conflictingTarget: "Your target weight must match your selected goal."
        case .underweightLossGoal: "Leafy cannot create a weight-loss plan below a BMI of 18.5."
        case .noSafeDeficit: "Leafy cannot create a meaningful generic deficit from these inputs. Please speak with a qualified professional."
        }
    }
}

