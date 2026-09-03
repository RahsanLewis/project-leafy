import XCTest
@testable import Leafy

final class PlanServiceSavePlanTests: XCTestCase {
    func testSavePlanRejectsNilBirthDateWithoutEncodingNull() async throws {
        let service = PlanService(configuration: .live())
        var input = sampleInput()
        input.birthDate = nil

        let raw = try JSONEncoder().encode(input)
        let rawObject = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertNil(rawObject["birth_date"], "pending-local encode must omit birth_date")

        let pendingURL = FileManager.default.temporaryDirectory.appending(path: "leafy-021-pending-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: pendingURL) }
        try await PendingOnboardingCache(fileURL: pendingURL).save(
            PendingOnboardingState(
                input: input,
                stepID: OnboardingDraft.Step.birthDate.rawValue,
                termsAccepted: true,
                privacyAccepted: true,
                coreDataAccepted: true,
                requiresBirthDateConfirmation: true
            )
        )
        let pendingObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: pendingURL)) as? [String: Any]
        )
        if let pendingInput = pendingObject["input"] as? [String: Any] {
            XCTAssertNil(pendingInput["birth_date"], "pending-local input must omit birth_date")
        }

        do {
            _ = try await service.savePlan(input)
            XCTFail("savePlan must reject a nil birthDate before encode")
        } catch {
            XCTAssertEqual(error as? PlanValidationError, .invalidAge)
        }

        XCTAssertThrowsError(try PlanService.encodeSavePlanPayload(input)) {
            XCTAssertEqual($0 as? PlanValidationError, .invalidAge)
        }
    }

    func testSavePlanPayloadEncodesCivilBirthDate() throws {
        let data = try PlanService.encodeSavePlanPayload(sampleInput())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["birth_date"] as? String, "1996-07-01")
        XCTAssertFalse((object["birth_date"] as Any?) is NSNull)
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("null") == true)
    }

    func testSavePlanLegalAcceptancePayloadKeepsCivilBirthDate() throws {
        let data = try PlanService.encodeSavePlanPayload(sampleInput(), recordLegalAcceptance: true)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let planInput = try XCTUnwrap(object["plan_input"] as? [String: Any])
        XCTAssertEqual(planInput["birth_date"] as? String, "1996-07-01")
        XCTAssertFalse((planInput["birth_date"] as Any?) is NSNull)
        XCTAssertNotNil(object["legal_acceptances"])
    }

    private func sampleInput() -> NutritionPlanInput {
        NutritionPlanInput(
            birthDate: try! LocalDate(year: 1996, month: 7, day: 1),
            calculationSex: .male, heightCM: 180, currentWeightKG: 90, targetWeightKG: 80,
            activityLevel: .moderate, goal: .lose, pace: .steady, unitSystem: .metric
        )
    }
}
