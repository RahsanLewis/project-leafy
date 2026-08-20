import Foundation
import Observation

struct ImperialHeightSelection: Equatable, Sendable {
    var feet: Int
    var inches: Int

    init(feet: Int, inches: Int) {
        self.feet = feet
        self.inches = inches
    }

    init(centimeters: Double) {
        let totalInches = Int((centimeters / 2.54).rounded())
        feet = totalInches / 12
        inches = totalInches % 12
    }

    var centimeters: Double { Double(feet * 12 + inches) * 2.54 }
    var isSupported: Bool { (120...230).contains(centimeters) }
}

@Observable final class OnboardingDraft {
    enum Step: String, CaseIterable, Codable {
        case welcome
        case adultEligibility
        case healthConsiderations
        case goal
        case birthDate
        case calculationSex
        case height
        case currentWeight
        case targetWeight
        case activity
        case pace
        case results
        case account

        static func legacy(_ rawValue: Int, draft: OnboardingDraft) -> Step {
            switch rawValue {
            case 0: return .welcome
            case 1:
                if draft.confirmsAdult == nil { return .adultEligibility }
                if draft.hasContraindication == nil { return .healthConsiderations }
                return .goal
            case 2: return .goal
            case 3: return .birthDate
            case 4: return .activity
            case 5: return .pace
            case 6: return .results
            case 7: return .account
            default: return .welcome
            }
        }
    }
    var step: Step = .welcome
    var confirmsAdult: Bool?
    var isPregnantOrBreastfeeding: Bool?
    var isInEatingDisorderRecovery: Bool?
    var followsClinicianDirectedDiet: Bool?
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

    var hasContraindication: Bool? {
        guard let isPregnantOrBreastfeeding,
              let isInEatingDisorderRecovery,
              let followsClinicianDirectedDiet else { return nil }
        return isPregnantOrBreastfeeding || isInEatingDisorderRecovery || followsClinicianDirectedDiet
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
