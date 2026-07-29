import Foundation
import Observation

@Observable final class OnboardingDraft {
    enum Step: Int, CaseIterable { case welcome, eligibility, goal, body, target, activity, pace, results }
    var step: Step = .welcome
    var isEditing = false
    var confirmsAdult = false
    var hasContraindication = false
    var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
    var calculationSex: CalculationSex = .female
    var heightCM = 168.0
    var currentWeightKG = 70.0
    var targetWeightKG = 64.0
    var activityLevel: ActivityLevel = .moderate
    var goal: WeightGoal = .lose {
        didSet {
            if goal == .lose, targetWeightKG >= currentWeightKG { targetWeightKG = max(35, currentWeightKG - 5) }
            if goal == .gain, targetWeightKG <= currentWeightKG { targetWeightKG = min(350, currentWeightKG + 5) }
        }
    }
    var pace: GoalPace = .steady
    var unitSystem: UnitSystem = .imperial

    var input: NutritionPlanInput {
        NutritionPlanInput(
            birthDate: birthDate, calculationSex: calculationSex,
            heightCM: heightCM, currentWeightKG: currentWeightKG,
            targetWeightKG: goal == .maintain ? nil : targetWeightKG,
            activityLevel: activityLevel, goal: goal, pace: pace, unitSystem: unitSystem
        )
    }
}

