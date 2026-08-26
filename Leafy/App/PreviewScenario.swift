import Foundation

extension AppCoordinator {
    func configureCICOPreview() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let userID = UUID()
        let plan = NutritionPlan(
            id: UUID(), revision: 2, calculatorVersion: "msj-amdr-v1",
            bmrKcal: 1_650, tdeeKcal: 2_250, calorieTargetKcal: 1_850,
            proteinG: 127, carbohydrateG: 208, fatG: 57,
            projectedWeeklyChangeKG: 0.36, estimatedGoalDate: nil, createdAt: .now
        )
        let breakfast = FoodEntry(
            id: UUID(), userID: userID, name: "Greek yogurt and berries", calories: 310,
            consumedAt: calendar.date(bySettingHour: 8, minute: 15, second: 0, of: yesterday) ?? yesterday,
            localDate: PlanService.localDayString(for: yesterday), timeZone: calendar.timeZone.identifier,
            createdAt: .now, updatedAt: .now
        )
        let dinner = FoodEntry(
            id: UUID(), userID: userID, name: "Chicken rice bowl", calories: 720,
            consumedAt: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: yesterday) ?? yesterday,
            localDate: PlanService.localDayString(for: yesterday), timeZone: calendar.timeZone.identifier,
            createdAt: .now, updatedAt: .now
        )
        currentPlan = plan
        dailyPlan = plan
        let previewWeightCount = ProcessInfo.processInfo.arguments.contains("-SixWeightReadings") ? 6 : 8
        weightEntries = (0..<previewWeightCount).map { offset in
            WeightEntry(
                id: UUID(),
                userID: userID,
                weightKG: 84.0 + Double(offset) * 0.08,
                recordedOn: calendar.date(byAdding: .day, value: -offset, to: today) ?? today,
                timeZone: calendar.timeZone.identifier,
                source: offset == previewWeightCount - 1 ? .baseline : .manual,
                planID: plan.id,
                createdAt: .now,
                updatedAt: .now
            )
        }
        selectedLogDate = today
        route = .dashboard
        isAuthenticated = true
        foodEntries = []
        dailyNutrition = Self.previewDailyNutrition(plan: plan)
        let previewCheckInEntries = ProcessInfo.processInfo.arguments.contains("-EmptyMorningCheckIn")
            ? []
            : [breakfast, dinner]
        morningCheckIn = MorningCheckIn(reviewDate: yesterday, entries: previewCheckInEntries, intakeDay: nil, todayWeight: nil)
        hasMorningCheckInReminder = true
        showMorningCheckIn = !ProcessInfo.processInfo.arguments.contains("-SkipMorningCheckIn")
        if ProcessInfo.processInfo.arguments.contains("-PlanResultsPreview") {
            preview = plan
            draft.step = .results
            route = .onboarding
            showMorningCheckIn = false
        }
    }

    static func previewMealEstimate(sessionID: UUID, ready: Bool = false) -> MealEstimate {
        MealEstimate(
            sessionID: sessionID,
            status: ready ? .ready : .needsClarification,
            totalCalories: 610,
            calorieLow: 500,
            calorieHigh: 760,
            confidence: 0.68,
            assumptions: ["Chicken appears grilled", "Rice portion is about one cup"],
            items: [
                MealEstimateItem(
                    id: UUID(uuidString: "D27DC6DA-CC10-4E55-9CC0-A017C9345521")!,
                    name: "Grilled chicken", portion: "1 chicken breast", estimatedGrams: 170,
                    calories: 280, calorieLow: 240, calorieHigh: 340, confidence: 0.82,
                    assumptions: ["Skinless chicken breast"]
                ),
                MealEstimateItem(
                    id: UUID(uuidString: "CC094E0B-3F24-4AD0-B641-47A244D14B38")!,
                    name: "Rice and vegetables", portion: "About 1½ cups", estimatedGrams: 260,
                    calories: 330, calorieLow: 260, calorieHigh: 420, confidence: 0.58,
                    assumptions: ["One cup cooked rice", "Lightly oiled vegetables"]
                ),
            ],
            followUp: ready ? nil : MealFollowUp(
                id: UUID(uuidString: "47DC0199-6EBF-4B37-B7D9-AEC297A031DD")!, ordinal: 1,
                question: "Was any oil, butter, or sauce added?"
            )
        )
    }

    static func previewDailyNutrition(plan: NutritionPlan?) -> DailyNutritionSummary? {
        guard let plan else { return nil }
        let values: [(String, String, String, Double, Double?, NutrientTargetKind)] = [
            ("protein_g", "Protein", "g", 54, Double(plan.proteinG), .goal),
            ("carbohydrate_g", "Carbohydrate", "g", 82, Double(plan.carbohydrateG), .goal),
            ("fat_g", "Fat", "g", 24, Double(plan.fatG), .goal),
            ("fiber_g", "Dietary fiber", "g", 13, 28, .goal),
            ("sodium_mg", "Sodium", "mg", 920, 2300, .limit),
            ("vitamin_d_mcg", "Vitamin D", "mcg", 7, 20, .goal),
            ("calcium_mg", "Calcium", "mg", 610, 1300, .goal),
            ("iron_mg", "Iron", "mg", 8.2, 18, .goal),
        ]
        let nutrients = values.enumerated().map { index, value in
            let nutrientClass: String = switch value.0 {
            case "protein_g", "carbohydrate_g", "fat_g": "macro"
            case "vitamin_d_mcg": "vitamin"
            case "sodium_mg", "calcium_mg", "iron_mg": "mineral"
            default: "other"
            }
            return DailyNutrient(
                code: value.0, name: value.1, unit: value.2, nutrientClass: nutrientClass,
                displayOrder: index, targetKind: value.5, amount: value.3, targetAmount: value.4,
                percentOfTarget: value.4.map { value.3 / $0 }, coverage: 0.78,
                estimatedAmount: value.3 * 0.35, verifiedAmount: value.3 * 0.65, confidence: 0.68
            )
        }
        return DailyNutritionSummary(
            localDate: PlanService.localDayString(for: .now), totalCalories: 0, macroCoverage: 0.78,
            reference: NutrientReference(
                code: "fda_adults_4_plus_2020", name: "FDA Daily Values",
                population: "Adults and children age 4 and older",
                sourceURL: URL(string: "https://www.fda.gov/food/nutrition-facts-label/daily-value-nutrition-and-supplement-facts-labels")!
            ), nutrients: nutrients
        )
    }

}
