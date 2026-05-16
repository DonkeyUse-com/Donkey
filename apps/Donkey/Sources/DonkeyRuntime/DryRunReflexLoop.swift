import DonkeyContracts
import Foundation

public protocol DryRunFrameSource: Sendable {
    func frameBatches() async -> [[HotLoopFrame]]
}

public protocol DryRunPerceptionAdapting: Sendable {
    func perceive(frame: HotLoopFrame) async -> [HotLoopPerceptionSignal]
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
    public var staleSignalThresholdMS: Double

    public init(
        coordinator: RunCoordinator,
        frameSource: any DryRunFrameSource,
        perceptionAdapter: any DryRunPerceptionAdapting = SyntheticPerceptionAdapter(),
        controllerPolicy: any DryRunControllerPolicy = InspectableDryRunControllerPolicy(),
        actionProjector: any DryRunActionProjecting = DryRunActionProjector(),
        staleSignalThresholdMS: Double = 250
    ) {
        self.coordinator = coordinator
        self.frameSource = frameSource
        self.perceptionAdapter = perceptionAdapter
        self.controllerPolicy = controllerPolicy
        self.actionProjector = actionProjector
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
        let affordances = actionAffordances(from: signals)
        let worldState = HotLoopWorldState.build(
            id: "state-\(frame.id)",
            frame: frame,
            signals: signals,
            observedAt: observedAt,
            staleThresholdMS: staleSignalThresholdMS,
            actionAffordances: affordances
        )
        let controllerStart = observedAt.addingMilliseconds(1)
        let action = await controllerPolicy.decide(state: worldState)
        let result = await actionProjector.project(action: action, state: worldState)
        let trace = ReflexTraceRecord(
            traceID: frame.traceID,
            frameID: frame.id,
            stateID: worldState.id,
            actionID: action.id,
            timestamps: ReflexTraceTimeline(
                captureStart: frame.capturedAt,
                captureEnd: frame.capturedAt,
                perceptionStart: frame.capturedAt,
                perceptionEnd: observedAt,
                statePublished: observedAt,
                controllerStart: controllerStart,
                controllerEnd: result.enqueuedAt,
                actionEnqueued: result.enqueuedAt,
                inputExecuted: result.completedAt
            ),
            controllerPolicy: action.policyName,
            confidence: action.confidence,
            plannerHintID: action.plannerHintID,
            metadata: [
                "dryRun.mode": result.mode.rawValue,
                "dryRun.executed": String(result.executed),
                "dryRun.summary": result.summary
            ]
        )

        await coordinator.appendReflexTrace(trace)

        return (worldState, action)
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

    private func actionAffordances(
        from signals: [HotLoopPerceptionSignal]
    ) -> [HotLoopActionAffordance] {
        signals.flatMap { signal in
            signal.observations.map { observation in
                HotLoopActionAffordance(
                    id: "affordance-\(observation.id)",
                    kind: .tapTarget,
                    targetBounds: observation.bounds,
                    confidence: min(signal.confidence, observation.confidence),
                    sourceSignalID: signal.id
                )
            }
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

public struct SyntheticPerceptionAdapter: DryRunPerceptionAdapting {
    public init() {}

    public func perceive(frame: HotLoopFrame) async -> [HotLoopPerceptionSignal] {
        let confidence = Double(frame.metadata["signalConfidence"] ?? "") ?? 1
        let observedAt = frame.capturedAt.addingMilliseconds(2)
        let observation = observation(from: frame, confidence: confidence)

        return [
            HotLoopPerceptionSignal(
                id: "signal-\(frame.id)",
                traceID: frame.traceID,
                frameID: frame.id,
                kind: frame.metadata["signalKind"] ?? "synthetic",
                capturedAt: frame.capturedAt,
                observedAt: observedAt,
                confidence: confidence,
                observations: observation.map { [$0] } ?? [],
                plannerHintID: frame.plannerHintID
            )
        ]
    }

    private func observation(
        from frame: HotLoopFrame,
        confidence: Double
    ) -> HotLoopPerceptionObservation? {
        guard let x = Double(frame.metadata["tapTargetX"] ?? ""),
              let y = Double(frame.metadata["tapTargetY"] ?? "")
        else {
            return nil
        }

        let width = Double(frame.metadata["tapTargetWidth"] ?? "") ?? 0.1
        let height = Double(frame.metadata["tapTargetHeight"] ?? "") ?? 0.1

        return HotLoopPerceptionObservation(
            id: "observation-\(frame.id)",
            label: frame.metadata["tapTargetLabel"] ?? "tap-target",
            bounds: HotLoopRect(
                x: x,
                y: y,
                width: width,
                height: height,
                space: .normalizedTarget
            ),
            confidence: confidence
        )
    }
}

public struct InspectableDryRunControllerPolicy: DryRunControllerPolicy {
    public var name: String

    public init(name: String = "inspectable-dry-run") {
        self.name = name
    }

    public func decide(state: HotLoopWorldState) async -> HotLoopControllerAction {
        if let affordance = state.actionAffordances.first(where: { $0.kind == .tapTarget }) {
            return HotLoopControllerAction(
                id: "action-\(state.id)",
                traceID: state.traceID,
                frameID: state.frameID,
                stateID: state.id,
                kind: .tapTarget,
                target: affordance.targetBounds,
                policyName: name,
                confidence: affordance.confidence,
                rationale: "Synthetic tap target affordance is available",
                plannerHintID: state.plannerHintID
            )
        }

        let kind: HotLoopActionKind = state.signalSummaries.isEmpty ? .observe : .wait
        return HotLoopControllerAction(
            id: "action-\(state.id)",
            traceID: state.traceID,
            frameID: state.frameID,
            stateID: state.id,
            kind: kind,
            policyName: name,
            confidence: state.confidence,
            rationale: kind == .observe ? "No perception signal is available" : "No safe action affordance is available",
            plannerHintID: state.plannerHintID
        )
    }
}

public struct DryRunActionProjector: DryRunActionProjecting {
    public init() {}

    public func project(
        action: HotLoopControllerAction,
        state: HotLoopWorldState
    ) async -> HotLoopActionResult {
        let enqueuedAt = state.observedAt.addingMilliseconds(2)
        let completedAt = enqueuedAt

        return HotLoopActionResult(
            id: "result-\(action.id)",
            traceID: action.traceID,
            frameID: action.frameID,
            stateID: action.stateID,
            actionID: action.id,
            mode: .dryRun,
            executed: false,
            enqueuedAt: enqueuedAt,
            completedAt: completedAt,
            summary: "Dry-run projected \(action.kind.rawValue)",
            metadata: [
                "policyName": action.policyName,
                "rationale": action.rationale
            ]
        )
    }
}

private extension RunTraceTimestamp {
    func addingMilliseconds(_ milliseconds: UInt64) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: wallClock.addingTimeInterval(Double(milliseconds) / 1_000),
            monotonicUptimeNanoseconds: monotonicUptimeNanoseconds + milliseconds * 1_000_000
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
