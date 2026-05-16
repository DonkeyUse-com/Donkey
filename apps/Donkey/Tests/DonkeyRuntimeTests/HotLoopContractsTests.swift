import DonkeyContracts
import Foundation
import Testing

@Suite
struct HotLoopContractsTests {
    @Test
    func hotLoopContractsRoundTripThroughCodable() throws {
        let frame = syntheticFrame(id: "frame-1")
        let signal = HotLoopPerceptionSignal(
            id: "signal-1",
            traceID: "trace-1",
            frameID: frame.id,
            kind: "template",
            capturedAt: timestamp(10),
            observedAt: timestamp(12),
            confidence: 0.8,
            observations: [
                HotLoopPerceptionObservation(
                    id: "observation-1",
                    label: "button",
                    bounds: HotLoopRect(
                        x: 0.4,
                        y: 0.5,
                        width: 0.1,
                        height: 0.1,
                        space: .normalizedTarget
                    ),
                    confidence: 0.75
                )
            ],
            plannerHintID: "hint-1"
        )
        let affordance = HotLoopActionAffordance(
            id: "affordance-1",
            kind: .tapTarget,
            targetBounds: signal.observations[0].bounds,
            confidence: 0.75,
            sourceSignalID: signal.id
        )
        let worldState = HotLoopWorldState.build(
            id: "state-1",
            frame: frame,
            signals: [signal],
            observedAt: timestamp(12),
            staleThresholdMS: 250,
            actionAffordances: [affordance]
        )
        let action = HotLoopControllerAction(
            id: "action-1",
            traceID: frame.traceID,
            frameID: frame.id,
            stateID: worldState.id,
            kind: .tapTarget,
            target: affordance.targetBounds,
            policyName: "test-policy",
            confidence: 0.75,
            rationale: "fixture target"
        )
        let result = HotLoopActionResult(
            id: "result-1",
            traceID: frame.traceID,
            frameID: frame.id,
            stateID: worldState.id,
            actionID: action.id,
            mode: .dryRun,
            executed: false,
            enqueuedAt: timestamp(13),
            completedAt: timestamp(13),
            summary: "projected"
        )

        try roundTrip(frame)
        try roundTrip(frame.crop)
        try roundTrip(signal)
        try roundTrip(worldState)
        try roundTrip(action)
        try roundTrip(result)
    }

    @Test
    func coordinateMapperConvertsAcrossSpaces() throws {
        let mapper = HotLoopCoordinateMapper(
            windowBoundsInScreen: HotLoopRect(
                x: 100,
                y: 200,
                width: 400,
                height: 300,
                space: .screen
            ),
            cropBoundsInWindow: HotLoopRect(
                x: 50,
                y: 40,
                width: 200,
                height: 100,
                space: .window
            )
        )

        let screenPoint = HotLoopPoint(x: 200, y: 290, space: .screen)
        let windowPoint = try #require(mapper.convert(screenPoint, to: .window))
        let cropPoint = try #require(mapper.convert(windowPoint, to: .crop))
        let normalizedPoint = try #require(mapper.convert(cropPoint, to: .normalizedTarget))
        let convertedBackToScreen = try #require(mapper.convert(normalizedPoint, to: .screen))

        #expect(windowPoint == HotLoopPoint(x: 100, y: 90, space: .window))
        #expect(cropPoint == HotLoopPoint(x: 50, y: 50, space: .crop))
        #expect(normalizedPoint == HotLoopPoint(x: 0.25, y: 0.5, space: .normalizedTarget))
        #expect(convertedBackToScreen == screenPoint)

        let screenRect = HotLoopRect(
            x: 150,
            y: 240,
            width: 100,
            height: 50,
            space: .screen
        )
        let normalizedRect = try #require(mapper.convert(screenRect, to: .normalizedTarget))

        #expect(normalizedRect.origin == HotLoopPoint(x: 0, y: 0, space: .normalizedTarget))
        #expect(normalizedRect.size == HotLoopSize(width: 0.5, height: 0.5, space: .normalizedTarget))
    }

    @Test
    func coordinateMapperReturnsNilForZeroAreaBounds() {
        let mapper = HotLoopCoordinateMapper(
            windowBoundsInScreen: HotLoopRect(
                x: 0,
                y: 0,
                width: 0,
                height: 300,
                space: .screen
            ),
            cropBoundsInWindow: HotLoopRect(
                x: 0,
                y: 0,
                width: 200,
                height: 100,
                space: .window
            )
        )

        #expect(mapper.convert(HotLoopPoint(x: 1, y: 1, space: .screen), to: .window) == nil)
    }

    @Test
    func worldStateMarksStaleSignalsBySourceAge() {
        let frame = syntheticFrame(id: "frame-stale")
        let signal = HotLoopPerceptionSignal(
            id: "signal-stale",
            traceID: frame.traceID,
            frameID: frame.id,
            kind: "template",
            capturedAt: timestamp(0),
            observedAt: timestamp(10),
            confidence: 0.9
        )

        let state = HotLoopWorldState.build(
            id: "state-stale",
            frame: frame,
            signals: [signal],
            observedAt: timestamp(300),
            staleThresholdMS: 250
        )

        #expect(state.staleSignalIDs == ["signal-stale"])
        #expect(state.signalSummaries.first?.sourceAgeMS == 300)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        #expect(decoded == value)
    }

    private func syntheticFrame(id: String) -> HotLoopFrame {
        HotLoopFrame(
            id: id,
            traceID: "trace-\(id)",
            targetID: "target-1",
            capturedAt: timestamp(10),
            sourceKind: .synthetic,
            windowBounds: HotLoopRect(
                x: 100,
                y: 200,
                width: 400,
                height: 300,
                space: .screen
            ),
            crop: HotLoopCrop(
                id: "crop-1",
                bounds: HotLoopRect(
                    x: 50,
                    y: 40,
                    width: 200,
                    height: 100,
                    space: .window
                ),
                outputSize: HotLoopSize(width: 200, height: 100, space: .crop)
            ),
            pixelSize: HotLoopSize(width: 400, height: 300, space: .window)
        )
    }

    private func timestamp(_ milliseconds: UInt64) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: 0),
            monotonicUptimeNanoseconds: milliseconds * 1_000_000
        )
    }
}
