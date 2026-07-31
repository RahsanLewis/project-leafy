import Foundation
import Observation

@Observable final class OnboardingDraft {
    enum Step: Int, CaseIterable { case welcome, eligibility, goal, body, activity, pace, results }
    var step: Step = .welcome
    var isEditing = false
    var confirmsAdult: Bool?
    var hasContraindication: Bool?
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

    var hasCompletedEligibility: Bool {
        confirmsAdult != nil && hasContraindication != nil
    }

    var isEligible: Bool {
        confirmsAdult == true && hasContraindication == false
    }

    var isIneligible: Bool {
        confirmsAdult == false || hasContraindication == true
    }

    var goalDifferenceKG: Double {
        abs(currentWeightKG - targetWeightKG)
    }

    var hasValidMeasurements: Bool {
        guard (120...230).contains(heightCM), (35...350).contains(currentWeightKG) else { return false }
        guard goal != .maintain else { return true }
        guard (35...350).contains(targetWeightKG) else { return false }
        if goal == .lose { return targetWeightKG < currentWeightKG }
        return targetWeightKG > currentWeightKG
    }

    var input: NutritionPlanInput {
        NutritionPlanInput(
            birthDate: birthDate, calculationSex: calculationSex,
            heightCM: heightCM, currentWeightKG: currentWeightKG,
            targetWeightKG: goal == .maintain ? nil : targetWeightKG,
            activityLevel: activityLevel, goal: goal, pace: pace, unitSystem: unitSystem
        )
    }
}
