import XCTest
@testable import Leafy

final class WeightProgressTests: XCTestCase {
    func testImperialWeightWheelKeepsWholeValueWhenDecimalChanges() {
        var selection = WeightWheelSelection(kilograms: 184.5 / 2.2046226218)

        selection.setTenth(7, unitSystem: .imperial)

        XCTAssertEqual(selection.whole(in: .imperial), 184)
        XCTAssertEqual(selection.tenth(in: .imperial), 7)
        XCTAssertEqual(selection.displayValue(in: .imperial), 184.7, accuracy: 0.001)
    }

    func testImperialWeightWheelKeepsDecimalWhenWholeValueChanges() {
        var selection = WeightWheelSelection(kilograms: 184.5 / 2.2046226218)

        selection.setWhole(190, unitSystem: .imperial)

        XCTAssertEqual(selection.whole(in: .imperial), 190)
        XCTAssertEqual(selection.tenth(in: .imperial), 5)
        XCTAssertEqual(selection.displayValue(in: .imperial), 190.5, accuracy: 0.001)
    }

    func testMetricWeightWheelRoundTripsTenths() {
        var selection = WeightWheelSelection(kilograms: 83.4)

        selection.setWhole(84, unitSystem: .metric)
        selection.setTenth(6, unitSystem: .metric)

        XCTAssertEqual(selection.kilograms, 84.6, accuracy: 0.001)
        XCTAssertEqual(selection.whole(in: .metric), 84)
        XCTAssertEqual(selection.tenth(in: .metric), 6)
    }

    func testWeightChartRangesUseExpectedCalendarBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 10))!

        XCTAssertFalse(WeightView.ChartRange.allCases.map(\.rawValue).contains("1D"))
        XCTAssertEqual(
            WeightView.ChartRange.week.startDate(relativeTo: now, calendar: calendar),
            calendar.date(byAdding: .day, value: -7, to: now)
        )
        XCTAssertEqual(
            WeightView.ChartRange.month.startDate(relativeTo: now, calendar: calendar),
            calendar.date(byAdding: .day, value: -30, to: now)
        )
        XCTAssertEqual(
            WeightView.ChartRange.quarter.startDate(relativeTo: now, calendar: calendar),
            calendar.date(byAdding: .day, value: -90, to: now)
        )
        XCTAssertEqual(
            WeightView.ChartRange.yearToDate.startDate(relativeTo: now, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        XCTAssertEqual(
            WeightView.ChartRange.year.startDate(relativeTo: now, calendar: calendar),
            calendar.date(byAdding: .day, value: -365, to: now)
        )
        XCTAssertNil(WeightView.ChartRange.all.startDate(relativeTo: now, calendar: calendar))
    }

    func testTrendInsightsDescribeObservedLossAcrossSelectedRange() {
        let entries = (1...14).map { day in makeEntry(weightKG: 80 - Double(day - 1) * 0.1, day: day) }
        let calendar = Calendar(identifier: .gregorian)
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 14))!

        let insights = WeightTrendInsights(
            entries: entries,
            periodStart: periodStart,
            periodEnd: periodEnd,
            targetKG: 77,
            goal: .lose,
            plannedWeeklyChangeKG: 0.7,
            calendar: calendar
        )

        XCTAssertEqual(insights.trendWeightKG!, 79.0, accuracy: 0.001)
        XCTAssertEqual(insights.previousTrendWeightKG!, 79.7, accuracy: 0.001)
        XCTAssertEqual(insights.periodChangeKG!, -0.7, accuracy: 0.001)
        XCTAssertEqual(insights.weeklyPaceKG!, -0.7, accuracy: 0.001)
        XCTAssertEqual(insights.paceComparison, .onPace)
        XCTAssertEqual(insights.currentWindowCount, 7)
        XCTAssertEqual(insights.previousWindowCount, 7)
        XCTAssertEqual(insights.weighInDayCount, 14)
        XCTAssertEqual(insights.periodDayCount, 14)
        XCTAssertEqual(insights.consistency!, 1, accuracy: 0.001)
        guard case let .date(forecast) = insights.goalForecast else {
            return XCTFail("Expected an observed goal forecast")
        }
        XCTAssertEqual(forecast, calendar.date(from: DateComponents(year: 2026, month: 2, day: 3)))
    }

    func testTrendInsightsStayInLearningStateWithSparseData() {
        let calendar = Calendar(identifier: .gregorian)
        let entries = [makeEntry(weightKG: 80, day: 1), makeEntry(weightKG: 79.8, day: 3)]
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7))!
        let insights = WeightTrendInsights(
            entries: entries,
            periodStart: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)),
            periodEnd: end,
            targetKG: 75,
            goal: .lose,
            plannedWeeklyChangeKG: 0.5,
            calendar: calendar
        )

        XCTAssertNil(insights.weeklyPaceKG)
        XCTAssertEqual(insights.paceComparison, .learning)
        XCTAssertEqual(insights.goalForecast, .learning)
        XCTAssertFalse(insights.hasTrend)
        XCTAssertNil(insights.trendWeightKG)
        XCTAssertTrue(insights.trendPoints.isEmpty)
    }

    func testTrendUnlocksAtSevenDistinctDailyReadings() throws {
        let calendar = Calendar(identifier: .gregorian)
        let entries = (1...7).map { day in makeEntry(weightKG: 80 - Double(day - 1), day: day) }
        let insights = WeightTrendInsights(
            entries: entries, periodStart: nil,
            periodEnd: calendar.date(from: DateComponents(year: 2026, month: 1, day: 7))!,
            targetKG: 75, goal: .lose, plannedWeeklyChangeKG: 0.5, calendar: calendar
        )

        XCTAssertTrue(insights.hasTrend)
        XCTAssertEqual(insights.distinctReadingCount, 7)
        XCTAssertEqual(insights.trendWeightKG!, 77, accuracy: 0.001)
        XCTAssertEqual(insights.trendPoints.count, 1)
        XCTAssertEqual(insights.trendPoints[0].sampleCount, 7)
        XCTAssertEqual(insights.fluctuationRangeSource, .expected)
        XCTAssertEqual(
            try XCTUnwrap(insights.fluctuationOffsetsKG).upperBound,
            WeightTrendInsights.expectedFluctuationHalfWidthKG,
            accuracy: 0.0001
        )
    }

    func testFluctuationRangeIsUnavailableBeforeSevenReadings() {
        let calendar = Calendar(identifier: .gregorian)
        let entries = (1...6).map { day in makeEntry(weightKG: 80, day: day) }
        let insights = WeightTrendInsights(
            entries: entries, periodStart: nil,
            periodEnd: calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!,
            targetKG: 75, goal: .lose, plannedWeeklyChangeKG: 0.5, calendar: calendar
        )

        XCTAssertEqual(insights.fluctuationRangeSource, .unavailable)
        XCTAssertNil(insights.fluctuationOffsetsKG)
    }

    func testFluctuationRangePersonalizesAfterFourteenUsableResiduals() {
        let calendar = Calendar(identifier: .gregorian)
        let entries = (1...20).map { day in
            makeEntry(weightKG: 80 - Double(day) * 0.08 + (day.isMultiple(of: 2) ? 0.15 : -0.1), day: day)
        }
        let insights = WeightTrendInsights(
            entries: entries, periodStart: nil,
            periodEnd: calendar.date(from: DateComponents(year: 2026, month: 1, day: 20))!,
            targetKG: 75, goal: .lose, plannedWeeklyChangeKG: 0.5, calendar: calendar
        )

        XCTAssertEqual(insights.fluctuationRangeSource, .personalized)
        XCTAssertNotNil(insights.fluctuationOffsetsKG)
    }

    func testYearChartDomainFitsOneMonthOfAvailableData() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 10))!
        let earliest = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 8))!
        let latest = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 8))!
        let yearStart = calendar.date(byAdding: .day, value: -365, to: now)!

        let domain = WeightChartDateDomain.fitted(
            to: [earliest, latest],
            fallbackStart: yearStart,
            now: now,
            calendar: calendar
        )

        XCTAssertLessThan(domain.upperBound.timeIntervalSince(domain.lowerBound), 21 * 86_400)
        XCTAssertLessThan(domain.lowerBound, earliest)
        XCTAssertGreaterThan(domain.upperBound, latest)
    }

    func testChartDomainCentersASingleReading() {
        let calendar = Calendar(identifier: .gregorian)
        let reading = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
        let domain = WeightChartDateDomain.fitted(
            to: [reading],
            fallbackStart: nil,
            now: reading.addingTimeInterval(3_600),
            calendar: calendar
        )

        XCTAssertEqual(domain.lowerBound, calendar.date(byAdding: .day, value: -1, to: reading))
        XCTAssertEqual(domain.upperBound, calendar.date(byAdding: .day, value: 1, to: reading))
    }

    func testChartAxisDoesNotRepeatLabelsWithinAShortVisibleRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let lower = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 18))!
        let upper = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 6))!
        let domain = lower...upper

        let ticks = WeightChartAxis.tickDates(in: domain, desiredCount: 5, calendar: calendar)
        let labels = ticks.map { WeightChartAxis.label(for: $0, in: domain, calendar: calendar) }

        XCTAssertEqual(labels, ["Aug 25", "Aug 26", "Aug 27"])
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    func testChartAxisAdaptsLabelsToVisibleSpanInsteadOfSelectedRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let shortDomain = ClosedRange(
            uncheckedBounds: (
                calendar.date(from: DateComponents(year: 2026, month: 7, day: 28))!,
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
            )
        )
        let longDomain = ClosedRange(
            uncheckedBounds: (
                calendar.date(from: DateComponents(year: 2025, month: 8, day: 14))!,
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
            )
        )

        XCTAssertEqual(
            WeightChartAxis.label(for: shortDomain.lowerBound, in: shortDomain, calendar: calendar),
            "Jul 28"
        )
        XCTAssertEqual(
            WeightChartAxis.label(for: longDomain.lowerBound, in: longDomain, calendar: calendar),
            "Aug 25"
        )
    }

    func testChartAxisUsesYearsForMultiYearHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let domain = ClosedRange(
            uncheckedBounds: (
                calendar.date(from: DateComponents(year: 2022, month: 1, day: 1))!,
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
            )
        )
        let ticks = WeightChartAxis.tickDates(in: domain, desiredCount: 5, calendar: calendar)
        let labels = ticks.map { WeightChartAxis.label(for: $0, in: domain, calendar: calendar) }

        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertTrue(labels.allSatisfy { $0.count == 4 })
    }

    func testEightReadingsProduceTwoRollingSevenReadingTrendPoints() {
        let calendar = Calendar(identifier: .gregorian)
        let entries = (1...8).map { day in makeEntry(weightKG: Double(day), day: day) }
        let insights = WeightTrendInsights(
            entries: entries, periodStart: nil,
            periodEnd: calendar.date(from: DateComponents(year: 2026, month: 1, day: 8))!,
            targetKG: 10, goal: .gain, plannedWeeklyChangeKG: 0.5, calendar: calendar
        )

        XCTAssertEqual(insights.trendPoints.map(\.averageKG), [4, 5])
        XCTAssertLessThan(insights.trendPoints[0].date, insights.trendPoints[1].date)
    }

    func testTrendCountsDistinctReadingDaysAndAllowsGaps() {
        let calendar = Calendar(identifier: .gregorian)
        var entries = [1, 3, 5, 8, 13, 21, 34].map { day in
            makeEntry(weightKG: 80, day: day)
        }
        entries.append(makeEntry(weightKG: 99, day: 34))
        let insights = WeightTrendInsights(
            entries: entries, periodStart: nil,
            periodEnd: calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))!,
            targetKG: 75, goal: .lose, plannedWeeklyChangeKG: 0.5, calendar: calendar
        )

        XCTAssertTrue(insights.hasTrend)
        XCTAssertEqual(insights.distinctReadingCount, 7)
        XCTAssertEqual(insights.trendPoints.count, 1)
    }

    func testWeeklyAveragesRequireFourDistinctDaysInEachWindow() {
        let calendar = Calendar(identifier: .gregorian)
        let entries = [1, 3, 5, 8, 10, 12, 14].map { day in makeEntry(weightKG: 80, day: day) }
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 14))!
        let insights = WeightTrendInsights(
            entries: entries, periodStart: nil, periodEnd: end, targetKG: 75,
            goal: .lose, plannedWeeklyChangeKG: 0.5, calendar: calendar
        )

        XCTAssertEqual(insights.currentWindowCount, 4)
        XCTAssertEqual(insights.previousWindowCount, 3)
        XCTAssertNil(insights.weeklyPaceKG)
        XCTAssertEqual(insights.paceComparison, .learning)
    }

    func testSingleSpikeDoesNotBecomeWeeklyProgressSignal() {
        let calendar = Calendar(identifier: .gregorian)
        let entries = (1...14).map { day in
            makeEntry(weightKG: day == 14 ? 84 : 80, day: day)
        }
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 14))!
        let insights = WeightTrendInsights(
            entries: entries, periodStart: nil, periodEnd: end, targetKG: 75,
            goal: .lose, plannedWeeklyChangeKG: 0.5, calendar: calendar
        )

        XCTAssertEqual(insights.weeklyPaceKG!, 4.0 / 7.0, accuracy: 0.001)
        XCTAssertLessThan(insights.weeklyPaceKG!, 1)
        XCTAssertEqual(insights.trendWeightKG!, 80 + 4.0 / 7.0, accuracy: 0.001)
    }

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

    func testImperialChartScalePrioritizesRecordedRangeOverDistantTarget() {
        let scale = WeightChartScale(
            weightsKG: [184 / 2.20462, 183 / 2.20462],
            targetKG: 141 / 2.20462,
            goal: .lose,
            unitSystem: .imperial
        )

        XCTAssertEqual(scale.domain.lowerBound, 178.5, accuracy: 0.01)
        XCTAssertEqual(scale.domain.upperBound, 188.5, accuracy: 0.01)
        XCTAssertFalse(scale.domain.contains(141))
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

    func testTotalProgressUsesStartingWeightAndEstablishedTrend() {
        XCTAssertNil(
            WeightInsightMetrics.totalProgressKG(
                startingKG: 90,
                trendWeightKG: 86.5,
                currentSampleCount: 4
            )
        )
        XCTAssertNil(
            WeightInsightMetrics.totalProgressKG(
                startingKG: 70,
                trendWeightKG: 72,
                currentSampleCount: 6
            )
        )
        XCTAssertEqual(
            WeightInsightMetrics.totalProgressKG(
                startingKG: 80,
                trendWeightKG: 80,
                currentSampleCount: 7
            ),
            0
        )
    }

    func testTotalProgressWaitsForEstablishedTrend() {
        XCTAssertNil(
            WeightInsightMetrics.totalProgressKG(
                startingKG: 90,
                trendWeightKG: 89,
                currentSampleCount: 3
            )
        )
    }

    func testTypicalFluctuationFormattingSupportsBothUnitSystems() {
        XCTAssertEqual(
            WeightInsightMetrics.fluctuationRangeLabel(
                offsetsKG: -0.4...0.5,
                unitSystem: .metric
            ),
            "−0.4 to +0.5 kg"
        )
        XCTAssertEqual(
            WeightInsightMetrics.fluctuationRangeLabel(
                offsetsKG: -0.4...0.5,
                unitSystem: .imperial
            ),
            "−0.9 to +1.1 lb"
        )
        XCTAssertEqual(
            WeightInsightMetrics.fluctuationRangeLabel(
                offsetsKG: nil,
                unitSystem: .imperial
            ),
            "Learning"
        )
    }

    func testActualWeightInsightsUseChronologicalReadings() {
        let entries = [
            makeEntry(weightKG: 79, day: 3),
            makeEntry(weightKG: 80, day: 1),
            makeEntry(weightKG: 79.5, day: 2),
        ]

        XCTAssertEqual(WeightInsightMetrics.actualTotalChangeKG(entries: entries), -1)
        XCTAssertEqual(WeightInsightMetrics.actualLatestChangeKG(entries: entries), -0.5)
        XCTAssertEqual(WeightInsightMetrics.actualRangeChangeKG(entries: Array(entries.prefix(2))), -1)
    }

    func testActualWeightInsightsRequireEnoughReadings() {
        let entry = makeEntry(weightKG: 80, day: 1)

        XCTAssertNil(WeightInsightMetrics.actualTotalChangeKG(entries: [entry]))
        XCTAssertNil(WeightInsightMetrics.actualLatestChangeKG(entries: [entry]))
        XCTAssertNil(WeightInsightMetrics.actualRangeChangeKG(entries: [entry]))
    }

    func testTrendRangeChangeUsesChronologicalPoints() {
        let points = [
            WeightTrendPoint(date: makeEntry(weightKG: 78.5, day: 3).recordedOn, averageKG: 78.5, sampleCount: 7),
            WeightTrendPoint(date: makeEntry(weightKG: 80, day: 1).recordedOn, averageKG: 80, sampleCount: 7),
            WeightTrendPoint(date: makeEntry(weightKG: 79.25, day: 2).recordedOn, averageKG: 79.25, sampleCount: 7),
        ]

        XCTAssertEqual(WeightInsightMetrics.trendRangeChangeKG(points: points), -1.5)
    }

    func testTrendRangeChangeRequiresTwoPoints() {
        let point = WeightTrendPoint(date: Date(), averageKG: 80, sampleCount: 7)
        XCTAssertNil(WeightInsightMetrics.trendRangeChangeKG(points: [point]))
    }

    func testActualDifferenceFromTrendRequiresEstablishedTrend() {
        XCTAssertNil(
            WeightInsightMetrics.actualDifferenceFromTrendKG(
                actualKG: 80.5,
                trendKG: 80,
                currentSampleCount: 6
            )
        )
        XCTAssertEqual(
            WeightInsightMetrics.actualDifferenceFromTrendKG(
                actualKG: 80.5,
                trendKG: 80,
                currentSampleCount: 7
            ),
            0.5
        )
    }

    func testWeightMovementFollowsGoalDirection() {
        XCTAssertEqual(WeightDashboardStats.movement(for: -1, goal: .lose), .towardGoal)
        XCTAssertEqual(WeightDashboardStats.movement(for: 1, goal: .lose), .awayFromGoal)
        XCTAssertEqual(WeightDashboardStats.movement(for: 1, goal: .gain), .towardGoal)
        XCTAssertEqual(WeightDashboardStats.movement(for: -1, goal: .gain), .awayFromGoal)
        XCTAssertEqual(WeightDashboardStats.movement(for: -1, goal: .maintain), .neutral)
    }

    func testMaintenanceMovementUsesOnePercentOfRangeStart() {
        XCTAssertEqual(
            WeightDashboardStats.movement(for: 1, relativeTo: 100, goal: .maintain),
            .towardGoal
        )
        XCTAssertEqual(
            WeightDashboardStats.movement(for: -1, relativeTo: 100, goal: .maintain),
            .towardGoal
        )
        XCTAssertEqual(
            WeightDashboardStats.movement(for: 1.01, relativeTo: 100, goal: .maintain),
            .awayFromGoal
        )
        XCTAssertEqual(
            WeightDashboardStats.movement(for: 1, relativeTo: nil, goal: .maintain),
            .neutral
        )
    }

    func testLoggingConsistencyCountsDistinctDaysSinceCurrentPlanBegan() {
        let calendar = Calendar(identifier: .gregorian)
        let start = makeEntry(weightKG: 80, day: 1).recordedOn
        let end = makeEntry(weightKG: 79, day: 5).recordedOn
        let entries = [
            makeEntry(weightKG: 80, day: 1),
            makeEntry(weightKG: 79.8, day: 3),
            makeEntry(weightKG: 79.7, day: 3),
            makeEntry(weightKG: 79.5, day: 5),
        ]

        let result = WeightInsightMetrics.loggingConsistency(
            entries: entries,
            planStartedAt: start,
            now: end,
            calendar: calendar
        )

        XCTAssertEqual(result?.loggedDayCount, 3)
        XCTAssertEqual(result?.totalDayCount, 5)
        XCTAssertEqual(result?.percentage, 60)
    }

    func testLoggingConsistencyIgnoresEntriesBeforePlanAndRejectsInvalidStart() {
        let calendar = Calendar(identifier: .gregorian)
        let start = makeEntry(weightKG: 80, day: 3).recordedOn
        let end = makeEntry(weightKG: 79, day: 5).recordedOn
        let result = WeightInsightMetrics.loggingConsistency(
            entries: [makeEntry(weightKG: 81, day: 1), makeEntry(weightKG: 80, day: 3)],
            planStartedAt: start,
            now: end,
            calendar: calendar
        )

        XCTAssertEqual(result?.loggedDayCount, 1)
        XCTAssertEqual(result?.totalDayCount, 3)
        XCTAssertNil(
            WeightInsightMetrics.loggingConsistency(
                entries: [],
                planStartedAt: nil,
                now: end,
                calendar: calendar
            )
        )
        XCTAssertNil(
            WeightInsightMetrics.loggingConsistency(
                entries: [],
                planStartedAt: end.addingTimeInterval(86_400),
                now: end,
                calendar: calendar
            )
        )
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
