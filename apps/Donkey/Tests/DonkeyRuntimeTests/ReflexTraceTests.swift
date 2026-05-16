import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct ReflexTraceTests {
    @Test
    func latencyBreakdownUsesMonotonicTimestamps() {
        let timeline = ReflexTraceTimeline(
            captureStart: timestamp(0),
            captureEnd: timestamp(4),
            preprocessStart: timestamp(4),
            preprocessEnd: timestamp(7),
            modelStart: timestamp(7),
            modelEnd: timestamp(16),
            perceptionStart: timestamp(4),
            perceptionEnd: timestamp(18),
            statePublished: timestamp(19),
            controllerStart: timestamp(24),
            controllerEnd: timestamp(27),
            actionEnqueued: timestamp(28),
            inputExecuted: timestamp(31)
        )

        let breakdown = timeline.latencyBreakdown()

        #expect(breakdown.captureMS == 4)
        #expect(breakdown.preprocessMS == 3)
        #expect(breakdown.modelInferenceMS == 9)
        #expect(breakdown.perceptionMS == 14)
        #expect(breakdown.decisionMS == 3)
        #expect(breakdown.inputMS == 3)
        #expect(breakdown.softwareLoopMS == 27)
        #expect(breakdown.frameAgeMS == 20)
        #expect(breakdown.stateAgeMS == 12)
    }

    @Test
    func reflexTraceStoreKeepsLatestRecordsWithinCapacity() async {
        let store = InMemoryReflexTraceStore(maxRecords: 2)

        await store.append(record(traceID: "trace-1", frameID: "frame-1"))
        await store.append(record(traceID: "trace-2", frameID: "frame-2"))
        await store.append(record(traceID: "trace-3", frameID: "frame-3"))

        let records = await store.allRecords()

        #expect(records.map(\.traceID) == ["trace-2", "trace-3"])
        #expect(await store.count() == 2)
        #expect(await store.latestRecord()?.frameID == "frame-3")
    }

    @Test
    func coordinatorRecordsReflexTraceAndPublishesLatencyEvent() async {
        let coordinator = RunCoordinator()
        let trace = record(
            traceID: "trace-reflex",
            frameID: "frame-9",
            stateID: "state-9",
            actionID: "action-9",
            controllerPolicy: "dodge-lane",
            confidence: 0.875,
            plannerHintID: "hint-1",
            machineProfile: "apple-silicon",
            buildID: "debug"
        )

        let event = await coordinator.appendReflexTrace(trace)

        #expect(event.stream == .reflex)
        #expect(event.traceID == "trace-reflex")
        #expect(event.metadata["reflex.frameID"] == "frame-9")
        #expect(event.metadata["reflex.controllerPolicy"] == "dodge-lane")
        #expect(event.metadata["latency.softwareLoopMS"] == "27.0")

        guard case .reflex(let payload) = event.payload else {
            Issue.record("Expected reflex payload")
            return
        }

        #expect(payload.frameID == "frame-9")
        #expect(payload.stateID == "state-9")
        #expect(payload.actionID == "action-9")
        #expect(payload.latency?.softwareLoopMS == 27)

        #expect(await coordinator.reflexTraces() == [trace])
        #expect(await coordinator.latestReflexTrace() == trace)
    }

    private func record(
        traceID: String,
        frameID: String,
        stateID: String = "state-1",
        actionID: String? = nil,
        controllerPolicy: String? = nil,
        confidence: Double? = nil,
        plannerHintID: String? = nil,
        machineProfile: String? = nil,
        buildID: String? = nil
    ) -> ReflexTraceRecord {
        ReflexTraceRecord(
            traceID: traceID,
            frameID: frameID,
            stateID: stateID,
            actionID: actionID,
            timestamps: ReflexTraceTimeline(
                captureStart: timestamp(0),
                captureEnd: timestamp(4),
                statePublished: timestamp(19),
                controllerStart: timestamp(24),
                controllerEnd: timestamp(27),
                actionEnqueued: timestamp(28),
                inputExecuted: timestamp(31)
            ),
            controllerPolicy: controllerPolicy,
            confidence: confidence,
            plannerHintID: plannerHintID,
            machineProfile: machineProfile,
            buildID: buildID
        )
    }

    private func timestamp(_ milliseconds: UInt64) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(milliseconds) / 1_000),
            monotonicUptimeNanoseconds: milliseconds * 1_000_000
        )
    }
}
