import Foundation

enum NutritionCalculator {
    static let version = "msj-amdr-v1"

    static func calculate(
        input: NutritionPlanInput,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> NutritionPlan {
        let age = calendar.dateComponents([.year], from: input.birthDate, to: now).year ?? 0
        guard (18...100).contains(age) else { throw PlanValidationError.invalidAge }
        guard (120...230).contains(input.heightCM) else { throw PlanValidationError.invalidHeight }
        guard (35...350).contains(input.currentWeightKG) else { throw PlanValidationError.invalidWeight }

        if input.goal != .maintain {
            guard let target = input.targetWeightKG else { throw PlanValidationError.missingTarget }
            guard (35...350).contains(target) else { throw PlanValidationError.invalidWeight }
            guard (input.goal == .lose && target < input.currentWeightKG) ||
                    (input.goal == .gain && target > input.currentWeightKG)
            else { throw PlanValidationError.conflictingTarget }
            let currentBMI = input.currentWeightKG / pow(input.heightCM / 100, 2)
            let targetBMI = target / pow(input.heightCM / 100, 2)
            if input.goal == .lose && (currentBMI < 18.5 || targetBMI < 18.5) {
                throw PlanValidationError.underweightLossGoal
            }
        }

        let sexConstant = input.calculationSex == .male ? 5.0 : -161.0
        let rawBMR = 10 * input.currentWeightKG + 6.25 * input.heightCM - 5 * Double(age) + sexConstant
        let rawTDEE = rawBMR * input.activityLevel.multiplier
        var rawTarget = rawTDEE * (1 + input.pace.adjustment(for: input.goal))
        if input.goal == .lose {
            rawTarget = max(rawTarget, rawBMR, 1_200)
            guard rawTDEE - rawTarget >= 50 else { throw PlanValidationError.noSafeDeficit }
        }

        let calorieTarget = Int((rawTarget / 10).rounded() * 10)
        let referenceWeight = input.goal == .maintain ? input.currentWeightKG : input.targetWeightKG!
        let proteinPerKG = input.goal == .maintain ? 1.2 : 1.6
        let desiredProteinCalories = referenceWeight * proteinPerKG * 4
        let proteinCalories = min(max(desiredProteinCalories, Double(calorieTarget) * 0.10), Double(calorieTarget) * 0.35)
        var fatCalories = Double(calorieTarget) * 0.30
        let minimumCarbohydrateCalories = Double(calorieTarget) * 0.45
        if Double(calorieTarget) - proteinCalories - fatCalories < minimumCarbohydrateCalories {
            fatCalories = max(Double(calorieTarget) * 0.20, Double(calorieTarget) - proteinCalories - minimumCarbohydrateCalories)
        }
        let carbohydrateCalories = Double(calorieTarget) - proteinCalories - fatCalories

        let weeklyChange = abs(rawTDEE - Double(calorieTarget)) * 7 / 7_700
        var estimatedDate: Date?
        if input.goal != .maintain, let target = input.targetWeightKG, weeklyChange > 0 {
            let weeks = abs(target - input.currentWeightKG) / weeklyChange
            estimatedDate = calendar.date(byAdding: .day, value: Int((weeks * 7).rounded(.up)), to: now)
        }

        return NutritionPlan(
            id: UUID(), revision: 0, calculatorVersion: version,
            bmrKcal: Int(rawBMR.rounded()), tdeeKcal: Int(rawTDEE.rounded()),
            calorieTargetKcal: calorieTarget,
            proteinG: Int((proteinCalories / 4).rounded()),
            carbohydrateG: Int((carbohydrateCalories / 4).rounded()),
            fatG: Int((fatCalories / 9).rounded()),
            projectedWeeklyChangeKG: weeklyChange,
            estimatedGoalDate: estimatedDate, createdAt: now
        )
    }
}

