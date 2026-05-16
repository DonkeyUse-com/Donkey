import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct CheapPerceptionAndControllerTests {
    @Test
    func cheapPerceptionAdapterBuildsDeterministicMetadataSignal() async throws {
        let frame = fixtureFrame(
            metadata: [
                "target.x": "0.25",
                "target.y": "0.4",
                "target.width": "0.2",
                "target.height": "0.1",
                "target.label": "play",
                "target.confidence": "0.7",
                "perception.kind": "template",
                "perception.confidence": "0.8"
            ]
        )

        let signals = await CheapPerceptionAdapter().perceive(frame: frame)
        let signal = try #require(signals.first)
        let observation = try #require(signal.observations.first)

        #expect(signal.kind == "template")
        #expect(signal.confidence == 0.8)
        #expect(signal.metadata["rawPixelsExposed"] == "false")
        #expect(signal.sourceAgeMS(at: timestamp(12)) == 2)
        #expect(observation.label == "play")
        #expect(observation.confidence == 0.7)
        #expect(observation.bounds == HotLoopRect(x: 0.25, y: 0.4, width: 0.2, height: 0.1, space: .normalizedTarget))
    }

    @Test
    func worldStateProjectorConvertsSignalsIntoCompactState() async throws {
        let frame = fixtureFrame()
        let signals = await CheapPerceptionAdapter().perceive(frame: frame)

        let state = HotLoopWorldStateProjector(staleSignalThresholdMS: 250).project(
            frame: frame,
            signals: signals,
            observedAt: timestamp(12)
        )

        #expect(state.id == "state-frame-1")
        #expect(state.signalSummaries.count == 1)
        #expect(state.signalSummaries.first?.sourceAgeMS == 2)
        #expect(state.actionAffordances.count == 1)
        #expect(state.actionAffordances.first?.kind == .tapTarget)
        #expect(state.metadata["rawPixelsExposed"] == "false")
    }

    @Test
    func deterministicControllerSelectsTapTargetForFreshConfidentAffordance() async {
        let state = worldState(confidence: 0.9, affordanceConfidence: 0.85)

        let action = await DeterministicControllerPolicy().decide(state: state)

        #expect(action.kind == .tapTarget)
        #expect(action.confidence == 0.85)
        #expect(action.policyName == "deterministic-tap-target-v1")
        #expect(action.metadata["fallback"] == "false")
        #expect(action.metadata["sourceSignalID"] == "signal-1")
    }

    @Test
    func deterministicControllerFallsBackWhenConfidenceIsLow() async {
        let state = worldState(confidence: 0.4, affordanceConfidence: 0.4)

        let action = await DeterministicControllerPolicy(minimumActionConfidence: 0.6).decide(state: state)

        #expect(action.kind == .wait)
        #expect(action.metadata["fallback"] == "true")
        #expect(action.metadata["fallbackReason"] == "lowConfidence")
    }

    @Test
    func deterministicControllerFallsBackWhenSignalIsStale() async {
        let state = worldState(
            confidence: 0.9,
            affordanceConfidence: 0.9,
            staleSignalIDs: ["signal-1"]
        )

        let action = await DeterministicControllerPolicy().decide(state: state)

        #expect(action.kind == .wait)
        #expect(action.metadata["fallback"] == "true")
        #expect(action.metadata["fallbackReason"] == "staleSignal")
    }

    @Test
    func dryRunTraceRecordsChosenActionMetadata() async {
        let coordinator = RunCoordinator()
        let loop = DryRunReflexLoop(
            coordinator: coordinator,
            frameSource: SyntheticFrameSource(frames: [fixtureFrame()])
        )

        _ = await loop.run(session: RunSession(id: "session-action", userGoal: "tap", targetID: "target-1"))

        let trace = await coordinator.latestReflexTrace()
        #expect(trace?.metadata["action.kind"] == "tapTarget")
        #expect(trace?.metadata["action.fallback"] == "false")
        #expect(trace?.metadata["action.rationale"] == "Selected highest-confidence tap target affordance")
        #expect(trace?.metadata["sourceSignalID"] == "signal-frame-1")
    }

    @Test
    func controllerReplayDecisionP95StaysUnder20MS() async {
        let policy = DeterministicControllerPolicy()
        let states = (0..<500).map { index in
            worldState(
                id: "state-\(index)",
                confidence: 0.9,
                affordanceConfidence: 0.85
            )
        }
        var durations: [Double] = []
        durations.reserveCapacity(states.count)

        for state in states {
            let start = ProcessInfo.processInfo.systemUptime
            _ = await policy.decide(state: state)
            let end = ProcessInfo.processInfo.systemUptime
            durations.append((end - start) * 1_000)
        }

        #expect(percentile95(durations) < 20)
    }

    private func fixtureFrame(metadata: [String: String] = [
        "tapTargetX": "0.4",
        "tapTargetY": "0.5",
        "tapTargetWidth": "0.1",
        "tapTargetHeight": "0.1",
        "tapTargetLabel": "start",
        "signalKind": "template",
        "signalConfidence": "0.85"
    ]) -> HotLoopFrame {
        HotLoopFrame(
            id: "frame-1",
            traceID: "trace-1",
            targetID: "target-1",
            capturedAt: timestamp(10),
            sourceKind: .recorded,
            windowBounds: HotLoopRect(x: 0, y: 0, width: 400, height: 300, space: .screen),
            crop: HotLoopCrop(
                id: "crop-1",
                bounds: HotLoopRect(x: 0, y: 0, width: 400, height: 300, space: .window),
                outputSize: HotLoopSize(width: 400, height: 300, space: .crop)
            ),
            pixelSize: HotLoopSize(width: 400, height: 300, space: .window),
            metadata: metadata
        )
    }

    private func worldState(
        id: String = "state-1",
        confidence: Double,
        affordanceConfidence: Double,
        staleSignalIDs: [String] = []
    ) -> HotLoopWorldState {
        HotLoopWorldState(
            id: id,
            traceID: "trace-1",
            frameID: "frame-1",
            targetID: "target-1",
            observedAt: timestamp(12),
            signalSummaries: [
                HotLoopPerceptionSignalSummary(
                    id: "signal-1",
                    kind: "template",
                    confidence: confidence,
                    sourceAgeMS: 2,
                    observationCount: 1
                )
            ],
            staleSignalIDs: staleSignalIDs,
            actionAffordances: [
                HotLoopActionAffordance(
                    id: "affordance-1",
                    kind: .tapTarget,
                    targetBounds: HotLoopRect(x: 0.4, y: 0.5, width: 0.1, height: 0.1, space: .normalizedTarget),
                    confidence: affordanceConfidence,
                    sourceSignalID: "signal-1"
                )
            ],
            confidence: confidence
        )
    }

    private func timestamp(_ milliseconds: UInt64) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(milliseconds) / 1_000),
            monotonicUptimeNanoseconds: milliseconds * 1_000_000
        )
    }

    private func percentile95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        return sorted[index]
    }
}
