import DonkeyContracts
import Foundation
import Testing

@Suite
struct PlannerHintContractsTests {
    @Test
    func validPlannerHintCanBeSelectedAsLatest() {
        let older = hint(id: "hint-old", createdAtMS: 10, sourceStateID: "state-1", confidence: 0.7)
        let latest = hint(id: "hint-latest", createdAtMS: 20, sourceStateID: "state-1", confidence: 0.8)
        let expired = hint(id: "hint-expired", createdAtMS: 30, expiresAtMS: 40, sourceStateID: "state-1", confidence: 0.9)

        let selection = PlannerHintSelector.latestValidHint(
            from: [older, latest, expired],
            context: context(nowMS: 50, currentStateID: "state-1")
        )

        #expect(selection.latestValidHint?.id == "hint-latest")
        #expect(selection.validationResults.first(where: { $0.hint.id == "hint-expired" })?.issues == [.expired])
    }

    @Test
    func validatorRejectsUnsafeActionsStaleStateAndLowConfidenceReplacement() {
        let candidate = hint(
            id: "hint-bad",
            sourceStateID: "old-state",
            confidence: 0.4,
            preferredActions: [.tapTarget],
            replacesHintID: "hint-current"
        )

        let result = PlannerHintValidator.validate(
            candidate,
            context: PlannerHintValidationContext(
                currentStateID: "state-1",
                allowedActions: Set(HotLoopActionKind.allCases),
                unsafeActions: [.tapTarget],
                minimumConfidence: 0.3,
                minimumReplacementConfidence: 0.6,
                now: timestamp(20)
            )
        )

        #expect(result.isValid == false)
        #expect(result.issues == [
            .lowConfidenceReplacement,
            .staleStateReference,
            .unsafeAction
        ])
    }

    @Test
    func structuredHintRoundTripsThroughCodableAndSummaryBridge() throws {
        let candidate = hint(id: "hint-codable", sourceStateID: "state-1", confidence: 0.75)

        let data = try JSONEncoder().encode(candidate)
        let decoded = try JSONDecoder().decode(StructuredPlannerHint.self, from: data)

        #expect(decoded == candidate)
        #expect(decoded.summaryHint().id == "hint-codable")
        #expect(decoded.summaryHint().isValid == true)
    }

    private func context(nowMS: UInt64, currentStateID: String?) -> PlannerHintValidationContext {
        PlannerHintValidationContext(
            currentStateID: currentStateID,
            now: timestamp(nowMS)
        )
    }

    private func hint(
        id: String,
        createdAtMS: UInt64 = 10,
        expiresAtMS: UInt64 = 100,
        sourceStateID: String?,
        confidence: Double,
        preferredActions: [HotLoopActionKind] = [.wait],
        replacesHintID: String? = nil
    ) -> StructuredPlannerHint {
        StructuredPlannerHint(
            id: id,
            goal: "stay safe",
            policyName: "planner-policy",
            priorities: ["avoid hazards"],
            preferredActions: preferredActions,
            avoidActions: [.tapTarget],
            confidence: confidence,
            createdAt: timestamp(createdAtMS),
            expiresAt: timestamp(expiresAtMS),
            sourceTraceID: "trace-1",
            sourceFrameID: "frame-1",
            sourceStateID: sourceStateID,
            replacesHintID: replacesHintID
        )
    }

    private func timestamp(_ milliseconds: UInt64) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(milliseconds) / 1_000),
            monotonicUptimeNanoseconds: milliseconds * 1_000_000
        )
    }
}
