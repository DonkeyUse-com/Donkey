import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct DryRunReflexLoopTests {
    @Test
    func syntheticFramesProduceOrderedReflexEventsAndTraces() async {
        let coordinator = RunCoordinator()
        let loop = DryRunReflexLoop(
            coordinator: coordinator,
            frameSource: SyntheticFrameSource(
                frames: [
                    frame(id: "frame-1", milliseconds: 10),
                    frame(id: "frame-2", milliseconds: 20)
                ]
            )
        )

        let result = await loop.run(session: session())

        #expect(result.processedFrameCount == 2)
        #expect(result.droppedFrameCount == 0)
        #expect(result.latestWorldState?.frameID == "frame-2")
        #expect(result.latestAction?.kind == .tapTarget)

        let events = await coordinator.events()
        #expect(events.map(\.sequence) == [1, 2, 3, 4, 5, 6])
        #expect(events.map(\.stream) == [
            .lifecycle,
            .lifecycle,
            .reflex,
            .reflex,
            .lifecycle,
            .lifecycle
        ])

        let traces = await coordinator.reflexTraces()
        #expect(traces.map(\.frameID) == ["frame-1", "frame-2"])
        #expect(traces.map(\.actionID) == ["action-state-frame-1", "action-state-frame-2"])
        #expect(traces.allSatisfy { $0.metadata["dryRun.executed"] == "false" })
    }

    @Test
    func latestFrameWinsBufferDropsStaleFrames() async {
        let coordinator = RunCoordinator()
        let loop = DryRunReflexLoop(
            coordinator: coordinator,
            frameSource: SyntheticFrameSource(
                batches: [[
                    frame(id: "frame-stale-1", milliseconds: 10),
                    frame(id: "frame-stale-2", milliseconds: 20),
                    frame(id: "frame-latest", milliseconds: 30)
                ]]
            )
        )

        let result = await loop.run(session: session())

        #expect(result.processedFrameCount == 1)
        #expect(result.droppedFrameCount == 2)
        #expect(result.latestWorldState?.frameID == "frame-latest")
        #expect((await coordinator.reflexTraces()).map(\.frameID) == ["frame-latest"])
    }

    @Test
    func dryRunLoopCompletesThroughCoordinator() async {
        let coordinator = RunCoordinator()
        let loop = DryRunReflexLoop(
            coordinator: coordinator,
            frameSource: SyntheticFrameSource(frames: [frame(id: "frame-1", milliseconds: 10)])
        )

        _ = await loop.run(
            session: session(),
            completion: .complete(reason: "fixture complete")
        )

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.lifecycleState == .completed)

        let events = await coordinator.events()
        #expect(lifecycleStates(in: events).suffix(2) == [.stopping, .completed])
    }

    @Test
    func dryRunLoopAbortRequestsInputReleaseWithoutInputToolExecution() async {
        let coordinator = RunCoordinator()
        let loop = DryRunReflexLoop(
            coordinator: coordinator,
            frameSource: SyntheticFrameSource(frames: [frame(id: "frame-abort", milliseconds: 10)])
        )

        _ = await loop.run(
            session: session(),
            completion: .abort(reason: "operator abort")
        )

        let events = await coordinator.events()
        #expect(lifecycleStates(in: events).last == .aborted)
        #expect(events.last?.requiresInputRelease == true)
        #expect(!eventsContainInputToolCall(events))
    }

    @Test
    func dryRunLoopTimeoutRequestsInputReleaseWithoutInputToolExecution() async {
        let coordinator = RunCoordinator()
        let loop = DryRunReflexLoop(
            coordinator: coordinator,
            frameSource: SyntheticFrameSource(frames: [frame(id: "frame-timeout", milliseconds: 10)])
        )

        _ = await loop.run(
            session: session(),
            completion: .timeout(reason: "deadline")
        )

        let events = await coordinator.events()
        #expect(lifecycleStates(in: events).last == .timedOut)
        #expect(events.last?.requiresInputRelease == true)
        #expect(!eventsContainInputToolCall(events))
    }

    @Test
    func emittedTraceLinksFrameStateActionPlannerHintAndLatency() async {
        let coordinator = RunCoordinator()
        let loop = DryRunReflexLoop(
            coordinator: coordinator,
            frameSource: SyntheticFrameSource(
                frames: [
                    frame(
                        id: "frame-linked",
                        milliseconds: 10,
                        plannerHintID: "hint-1"
                    )
                ]
            )
        )

        _ = await loop.run(session: session())

        let trace = await coordinator.latestReflexTrace()
        #expect(trace?.traceID == "trace-frame-linked")
        #expect(trace?.frameID == "frame-linked")
        #expect(trace?.stateID == "state-frame-linked")
        #expect(trace?.actionID == "action-state-frame-linked")
        #expect(trace?.plannerHintID == "hint-1")
        #expect(trace?.latencyBreakdown.perceptionMS == 2)
        #expect(trace?.latencyBreakdown.decisionMS == 1)
        #expect(trace?.metadata["dryRun.mode"] == "dryRun")
    }

    private func session() -> RunSession {
        RunSession(
            id: "session-dry-run",
            userGoal: "tap visible target",
            targetID: "target-1"
        )
    }

    private func frame(
        id: String,
        milliseconds: UInt64,
        plannerHintID: String? = nil
    ) -> HotLoopFrame {
        HotLoopFrame(
            id: id,
            traceID: "trace-\(id)",
            targetID: "target-1",
            capturedAt: timestamp(milliseconds),
            sourceKind: .synthetic,
            windowBounds: HotLoopRect(
                x: 0,
                y: 0,
                width: 400,
                height: 300,
                space: .screen
            ),
            crop: HotLoopCrop(
                id: "crop-\(id)",
                bounds: HotLoopRect(
                    x: 0,
                    y: 0,
                    width: 400,
                    height: 300,
                    space: .window
                ),
                outputSize: HotLoopSize(width: 400, height: 300, space: .crop)
            ),
            pixelSize: HotLoopSize(width: 400, height: 300, space: .window),
            plannerHintID: plannerHintID,
            metadata: [
                "tapTargetX": "0.4",
                "tapTargetY": "0.5",
                "tapTargetWidth": "0.1",
                "tapTargetHeight": "0.1",
                "tapTargetLabel": "start",
                "signalKind": "template",
                "signalConfidence": "0.85"
            ]
        )
    }

    private func timestamp(_ milliseconds: UInt64) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(milliseconds) / 1_000),
            monotonicUptimeNanoseconds: milliseconds * 1_000_000
        )
    }

    private func lifecycleStates(in events: [RunEvent]) -> [RunLifecycleState] {
        events.compactMap { event in
            guard case .lifecycle(let payload) = event.payload else { return nil }
            return payload.state
        }
    }

    private func eventsContainInputToolCall(_ events: [RunEvent]) -> Bool {
        events.contains { event in
            guard case .tool(let payload) = event.payload else { return false }
            return payload.capability == .input
        }
    }
}
