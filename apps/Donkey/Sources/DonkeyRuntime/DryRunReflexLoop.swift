import DonkeyContracts
import Foundation

public protocol DryRunFrameSource: Sendable {
    func frameBatches() async -> [[HotLoopFrame]]
}

public protocol DryRunPerceptionAdapting: Sendable {
    func perceive(frame: HotLoopFrame) async -> [HotLoopPerceptionSignal]
}

public protocol DryRunWorldStateProjecting: Sendable {
    func project(
        frame: HotLoopFrame,
        signals: [HotLoopPerceptionSignal],
        observedAt: RunTraceTimestamp
    ) async -> HotLoopWorldState
}

public protocol DryRunControllerPolicy: Sendable {
    var name: String { get }
    func decide(state: HotLoopWorldState) async -> HotLoopControllerAction
}

public protocol DryRunActionProjecting: Sendable {
    func project(
        action: HotLoopControllerAction,
        state: HotLoopWorldState
    ) async -> HotLoopActionResult
}

public enum DryRunReflexLoopCompletion: Equatable, Sendable {
    case complete(reason: String)
    case abort(reason: String)
    case timeout(reason: String)
    case pause(reason: String)
}

public struct DryRunReflexLoopResult: Equatable, Sendable {
    public var processedFrameCount: Int
    public var droppedFrameCount: Int
    public var latestWorldState: HotLoopWorldState?
    public var latestAction: HotLoopControllerAction?

    public init(
        processedFrameCount: Int,
        droppedFrameCount: Int,
        latestWorldState: HotLoopWorldState? = nil,
        latestAction: HotLoopControllerAction? = nil
    ) {
        self.processedFrameCount = processedFrameCount
        self.droppedFrameCount = droppedFrameCount
        self.latestWorldState = latestWorldState
        self.latestAction = latestAction
    }
}

public actor LatestHotLoopFrameBuffer {
    private var latestFrame: HotLoopFrame?
    private var droppedFrameCount = 0

    public init() {}

    public func offer(_ frame: HotLoopFrame) {
        if latestFrame != nil {
            droppedFrameCount += 1
        }

        latestFrame = frame
    }

    public func takeLatest() -> HotLoopFrame? {
        let frame = latestFrame
        latestFrame = nil
        return frame
    }

    public func droppedCount() -> Int {
        droppedFrameCount
    }
}

public struct DryRunReflexLoop: Sendable {
    public var coordinator: RunCoordinator
    public var frameSource: any DryRunFrameSource
    public var perceptionAdapter: any DryRunPerceptionAdapting
    public var controllerPolicy: any DryRunControllerPolicy
    public var actionProjector: any DryRunActionProjecting
    public var worldStateProjector: any DryRunWorldStateProjecting
    public var staleSignalThresholdMS: Double

    public init(
        coordinator: RunCoordinator,
        frameSource: any DryRunFrameSource,
        perceptionAdapter: any DryRunPerceptionAdapting = CheapPerceptionAdapter(),
        worldStateProjector: (any DryRunWorldStateProjecting)? = nil,
        controllerPolicy: any DryRunControllerPolicy = DeterministicControllerPolicy(),
        actionProjector: any DryRunActionProjecting = DryRunActionProjector(),
        staleSignalThresholdMS: Double = 250
    ) {
        self.coordinator = coordinator
        self.frameSource = frameSource
        self.perceptionAdapter = perceptionAdapter
        self.controllerPolicy = controllerPolicy
        self.actionProjector = actionProjector
        self.worldStateProjector = worldStateProjector
            ?? HotLoopWorldStateProjector(staleSignalThresholdMS: staleSignalThresholdMS)
        self.staleSignalThresholdMS = staleSignalThresholdMS
    }

    @discardableResult
    public func run(
        session: RunSession,
        completion: DryRunReflexLoopCompletion = .complete(reason: "Dry-run reflex loop completed")
    ) async -> DryRunReflexLoopResult {
        _ = await coordinator.start(session)

        let buffer = LatestHotLoopFrameBuffer()
        var processedFrameCount = 0
        var latestWorldState: HotLoopWorldState?
        var latestAction: HotLoopControllerAction?

        for batch in await frameSource.frameBatches() {
            for frame in batch {
                await buffer.offer(frame)
            }

            guard !Task.isCancelled else {
                await coordinator.abort(reason: "Dry-run reflex loop task cancelled")
                break
            }

            guard !(await coordinator.snapshot().lifecycleState.isTerminal) else {
                break
            }

            guard let frame = await buffer.takeLatest() else {
                continue
            }

            let tick = await process(frame: frame)
            processedFrameCount += 1
            latestWorldState = tick.worldState
            latestAction = tick.action
        }

        if !(await coordinator.snapshot().lifecycleState.isTerminal) {
            await finish(completion)
        }

        return DryRunReflexLoopResult(
            processedFrameCount: processedFrameCount,
            droppedFrameCount: await buffer.droppedCount(),
            latestWorldState: latestWorldState,
            latestAction: latestAction
        )
    }

    private func process(
        frame: HotLoopFrame
    ) async -> (worldState: HotLoopWorldState, action: HotLoopControllerAction) {
        let signals = await perceptionAdapter.perceive(frame: frame)
        let observedAt = signals.map(\.observedAt).maxByMonotonicUptime() ?? frame.capturedAt.addingMilliseconds(2)
        let stateUpdateStart = observedAt
        let worldState = await worldStateProjector.project(
            frame: frame,
            signals: signals,
            observedAt: observedAt,
        )
        let stateUpdateEnd = stateUpdateStart.addingMilliseconds(
            latencyMilliseconds(
                named: "latency.stateUpdateMS",
                frame: frame,
                signals: signals,
                defaultValue: 1
            ) ?? 1
        )
        let controllerStart = stateUpdateEnd
        let action = await controllerPolicy.decide(state: worldState)
        let result = await actionProjector.project(action: action, state: worldState)
        let controllerEnd = controllerStart.addingMilliseconds(
            latencyMilliseconds(
                named: "latency.controllerDecisionMS",
                frame: frame,
                signals: signals,
                defaultValue: 1
            ) ?? 1
        )
        let actionProjectionStart = controllerEnd
        let actionProjectionEnd = actionProjectionStart.addingMilliseconds(
            latencyMilliseconds(
                named: "latency.actionProjectionMS",
                frame: frame,
                signals: signals,
                defaultValue: 0
            ) ?? 0
        )
        let captureStart = captureStart(for: frame)
        let preprocess = stageWindow(
            named: "latency.preprocessMS",
            frame: frame,
            signals: signals,
            defaultValue: frame.crop == nil ? 0 : nil,
            after: frame.capturedAt
        )
        let model = stageWindow(
            named: "latency.modelInferenceMS",
            frame: frame,
            signals: signals,
            defaultValue: nil,
            after: preprocess.end ?? frame.capturedAt
        )
        let trace = ReflexTraceRecord(
            traceID: frame.traceID,
            frameID: frame.id,
            stateID: worldState.id,
            actionID: action.id,
            timestamps: ReflexTraceTimeline(
                captureStart: captureStart,
                captureEnd: frame.capturedAt,
                preprocessStart: preprocess.start,
                preprocessEnd: preprocess.end,
                modelStart: model.start,
                modelEnd: model.end,
                perceptionStart: frame.capturedAt,
                perceptionEnd: observedAt,
                stateUpdateStart: stateUpdateStart,
                stateUpdateEnd: stateUpdateEnd,
                statePublished: stateUpdateEnd,
                controllerStart: controllerStart,
                controllerEnd: controllerEnd,
                actionProjectionStart: actionProjectionStart,
                actionProjectionEnd: actionProjectionEnd,
                actionEnqueued: actionProjectionEnd,
                inputExecuted: actionProjectionEnd
            ),
            controllerPolicy: action.policyName,
            confidence: action.confidence,
            plannerHintID: action.plannerHintID,
            metadata: [
                "dryRun.mode": result.mode.rawValue,
                "dryRun.executed": String(result.executed),
                "dryRun.summary": result.summary,
                "action.kind": action.kind.rawValue,
                "action.rationale": action.rationale,
                "action.fallback": action.metadata["fallback"] ?? "false",
                "latency.metadataReadMS": formatLatency(
                    latencyMilliseconds(
                        named: "latency.metadataReadMS",
                        frame: frame,
                        signals: signals,
                        defaultValue: nil
                    )
                ),
                "latency.stateUpdateMS": formatLatency(stateUpdateStart.milliseconds(until: stateUpdateEnd)),
                "latency.actionProjectionMS": formatLatency(actionProjectionStart.milliseconds(until: actionProjectionEnd))
            ].merging(action.metadata, uniquingKeysWith: { current, _ in current })
        )

        await coordinator.appendReflexTrace(trace)

        return (worldState, action)
    }

    private func captureStart(for frame: HotLoopFrame) -> RunTraceTimestamp {
        guard let latency = Double(frame.metadata["capture.latencyMS"] ?? ""),
              latency >= 0
        else {
            return frame.capturedAt
        }

        return frame.capturedAt.addingMilliseconds(-latency)
    }

    private func stageWindow(
        named key: String,
        frame: HotLoopFrame,
        signals: [HotLoopPerceptionSignal],
        defaultValue: Double?,
        after start: RunTraceTimestamp
    ) -> (start: RunTraceTimestamp?, end: RunTraceTimestamp?) {
        guard let latency = latencyMilliseconds(
            named: key,
            frame: frame,
            signals: signals,
            defaultValue: defaultValue
        ) else {
            return (nil, nil)
        }

        let end = start.addingMilliseconds(latency)
        return (start, end)
    }

    private func latencyMilliseconds(
        named key: String,
        frame: HotLoopFrame,
        signals: [HotLoopPerceptionSignal],
        defaultValue: Double?
    ) -> Double? {
        if let value = Double(frame.metadata[key] ?? "") {
            return max(0, value)
        }

        for signal in signals {
            if let value = Double(signal.metadata[key] ?? "") {
                return max(0, value)
            }
        }

        return defaultValue
    }

    private func formatLatency(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return String(format: "%.2f", value)
    }

    private func finish(_ completion: DryRunReflexLoopCompletion) async {
        switch completion {
        case .complete(let reason):
            await coordinator.complete(reason: reason)
        case .abort(let reason):
            await coordinator.abort(reason: reason)
        case .timeout(let reason):
            await coordinator.timeout(reason: reason)
        case .pause(let reason):
            await coordinator.pause(reason: reason)
        }
    }

}

public struct SyntheticFrameSource: DryRunFrameSource {
    public var batches: [[HotLoopFrame]]

    public init(frames: [HotLoopFrame]) {
        self.batches = frames.map { [$0] }
    }

    public init(batches: [[HotLoopFrame]]) {
        self.batches = batches
    }

    public func frameBatches() async -> [[HotLoopFrame]] {
        batches
    }
}

public struct RecordedFrameSource: DryRunFrameSource {
    public var frames: [HotLoopFrame]

    public init(frames: [HotLoopFrame]) {
        self.frames = frames
    }

    public func frameBatches() async -> [[HotLoopFrame]] {
        frames.map { [$0] }
    }
}

public typealias SyntheticPerceptionAdapter = CheapPerceptionAdapter
public typealias InspectableDryRunControllerPolicy = DeterministicControllerPolicy

private extension RunTraceTimestamp {
    func addingMilliseconds(_ milliseconds: Double) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: wallClock.addingTimeInterval(Double(milliseconds) / 1_000),
            monotonicUptimeNanoseconds: UInt64(
                max(
                    0,
                    Double(monotonicUptimeNanoseconds) + milliseconds * 1_000_000
                )
            )
        )
    }
}

private extension Array where Element == RunTraceTimestamp {
    func maxByMonotonicUptime() -> RunTraceTimestamp? {
        self.max { lhs, rhs in
            lhs.monotonicUptimeNanoseconds < rhs.monotonicUptimeNanoseconds
        }
    }
}
