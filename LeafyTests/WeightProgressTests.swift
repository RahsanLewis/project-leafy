import XCTest
@testable import Leafy

final class WeightProgressTests: XCTestCase {
    func testLossProgressUsesStartingLatestAndTargetWeights() {
        let progress = WeightProgress(latestKG: 85, previousKG: 86, startingKG: 90, targetKG: 80, goal: .lose)

        XCTAssertEqual(progress.changeFromPreviousKG, -1)
        XCTAssertEqual(progress.remainingKG, 5)
        XCTAssertEqual(progress.progress, 0.5)
    }

    func testGainProgressUsesDirectionOfGoal() {
        let progress = WeightProgress(latestKG: 72.5, previousKG: 72, startingKG: 70, targetKG: 75, goal: .gain)

        XCTAssertEqual(progress.changeFromPreviousKG, 0.5)
        XCTAssertEqual(progress.remainingKG, 2.5)
        XCTAssertEqual(progress.progress, 0.5)
    }

    func testProgressClampsAtGoalAndBeforeStartingPoint() {
        XCTAssertEqual(WeightProgress(latestKG: 78, previousKG: nil, startingKG: 90, targetKG: 80, goal: .lose).progress, 1)
        XCTAssertEqual(WeightProgress(latestKG: 92, previousKG: nil, startingKG: 90, targetKG: 80, goal: .lose).progress, 0)
    }

    func testMaintenanceDoesNotExposeTargetProgress() {
        let progress = WeightProgress(latestKG: 80, previousKG: 81, startingKG: 82, targetKG: nil, goal: .maintain)

        XCTAssertNil(progress.progress)
        XCTAssertNil(progress.remainingKG)
        XCTAssertEqual(progress.changeFromPreviousKG, -1)
    }

    func testImperialChartScaleIncludesRecordedAndTargetWeightsWithPadding() {
        let scale = WeightChartScale(
            weightsKG: [184 / 2.20462, 183 / 2.20462],
            targetKG: 141 / 2.20462,
            goal: .lose,
            unitSystem: .imperial
        )

        XCTAssertEqual(scale.domain.lowerBound, 136.7, accuracy: 0.01)
        XCTAssertEqual(scale.domain.upperBound, 188.3, accuracy: 0.01)
        XCTAssertTrue(scale.domain.contains(141))
        XCTAssertTrue(scale.domain.contains(184))
    }

    func testSingleImperialWeightUsesTenPoundMinimumSpan() {
        let scale = WeightChartScale(
            weightsKG: [184 / 2.20462],
            targetKG: nil,
            goal: .maintain,
            unitSystem: .imperial
        )

        XCTAssertEqual(scale.domain.lowerBound, 179, accuracy: 0.01)
        XCTAssertEqual(scale.domain.upperBound, 189, accuracy: 0.01)
    }

    func testMetricChartScaleUsesFiveKilogramMinimumSpan() {
        let scale = WeightChartScale(
            weightsKG: [80, 80.5],
            targetKG: nil,
            goal: .maintain,
            unitSystem: .metric
        )

        XCTAssertEqual(scale.domain.lowerBound, 77.75, accuracy: 0.01)
        XCTAssertEqual(scale.domain.upperBound, 82.75, accuracy: 0.01)
    }

    func testMaintenanceChartScaleIgnoresTargetWeight() {
        let scale = WeightChartScale(
            weightsKG: [80, 81],
            targetKG: 60,
            goal: .maintain,
            unitSystem: .metric
        )

        XCTAssertFalse(scale.domain.contains(60))
        XCTAssertEqual(scale.domain.lowerBound, 78, accuracy: 0.01)
        XCTAssertEqual(scale.domain.upperBound, 83, accuracy: 0.01)
    }

    func testWeightMovementFollowsGoalDirection() {
        XCTAssertEqual(WeightDashboardStats.movement(for: -1, goal: .lose), .towardGoal)
        XCTAssertEqual(WeightDashboardStats.movement(for: 1, goal: .lose), .awayFromGoal)
        XCTAssertEqual(WeightDashboardStats.movement(for: 1, goal: .gain), .towardGoal)
        XCTAssertEqual(WeightDashboardStats.movement(for: -1, goal: .gain), .awayFromGoal)
        XCTAssertEqual(WeightDashboardStats.movement(for: -1, goal: .maintain), .neutral)
    }

    func testDashboardStatsUseFirstAndLatestEntries() {
        let entries = [
            makeEntry(weightKG: 80, day: 1),
            makeEntry(weightKG: 78, day: 3),
            makeEntry(weightKG: 79, day: 2),
        ]
        let stats = WeightDashboardStats(
            entries: entries,
            targetKG: 75,
            goal: .lose,
            projectedWeeklyChangeKG: 0.5,
            estimatedGoalDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(stats.startingKG, 80)
        XCTAssertEqual(stats.totalChangeKG, -2)
        XCTAssertEqual(stats.remainingKG, 3)
        XCTAssertEqual(stats.targetKG, 75)
        XCTAssertEqual(stats.projectedWeeklyChangeKG, 0.5)
    }

    func testMaintenanceStatsRemoveGoalSpecificValues() {
        let stats = WeightDashboardStats(
            entries: [makeEntry(weightKG: 80, day: 1)],
            targetKG: 75,
            goal: .maintain,
            projectedWeeklyChangeKG: 0.5,
            estimatedGoalDate: Date()
        )

        XCTAssertNil(stats.targetKG)
        XCTAssertNil(stats.remainingKG)
        XCTAssertEqual(stats.projectedWeeklyChangeKG, 0)
        XCTAssertNil(stats.estimatedGoalDate)
    }

    private func makeEntry(weightKG: Double, day: Int) -> WeightEntry {
        WeightEntry(
            id: UUID(),
            userID: UUID(),
            weightKG: weightKG,
            recordedOn: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 1, day: day))!,
            timeZone: "UTC",
            source: day == 1 ? .baseline : .manual,
            planID: nil,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}
