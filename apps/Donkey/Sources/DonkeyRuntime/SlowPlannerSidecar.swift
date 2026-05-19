import DonkeyContracts
import Foundation

public enum SlowPlannerTriggerReason: String, Codable, Equatable, Hashable, Sendable {
    case sceneChanged
    case lowConfidence
    case repeatedFailure
    case goalCompleted
    case userInstruction
}

public struct SlowPlannerScreenshotReference: Codable, Equatable, Sendable {
    public var artifactID: String
    public var summary: String
    public var metadata: [String: String]

    public init(
        artifactID: String,
        summary: String,
        metadata: [String: String] = [:]
    ) {
        self.artifactID = artifactID
        self.summary = summary
        self.metadata = metadata
    }
}

public struct SlowPlannerTraceSummary: Codable, Equatable, Sendable {
    public var traceID: String
    public var frameID: String
    public var stateID: String
    public var actionID: String?
    public var actionKind: String?
    public var confidence: Double?
    public var fallbackReason: String?
    public var softwareLoopMS: Double?

    public init(
        traceID: String,
        frameID: String,
        stateID: String,
        actionID: String? = nil,
        actionKind: String? = nil,
        confidence: Double? = nil,
        fallbackReason: String? = nil,
        softwareLoopMS: Double? = nil
    ) {
        self.traceID = traceID
        self.frameID = frameID
        self.stateID = stateID
        self.actionID = actionID
        self.actionKind = actionKind
        self.confidence = confidence
        self.fallbackReason = fallbackReason
        self.softwareLoopMS = softwareLoopMS
    }
}

public struct SlowPlannerSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var triggerReasons: [SlowPlannerTriggerReason]
    public var context: RunContextPackage
    public var latestWorldState: HotLoopWorldState
    public var latestAction: HotLoopControllerAction
    public var traceSummaries: [SlowPlannerTraceSummary]
    public var screenshotReferences: [SlowPlannerScreenshotReference]
    public var metadata: [String: String]

    public init(
        id: String,
        triggerReasons: [SlowPlannerTriggerReason],
        context: RunContextPackage,
        latestWorldState: HotLoopWorldState,
        latestAction: HotLoopControllerAction,
        traceSummaries: [SlowPlannerTraceSummary],
        screenshotReferences: [SlowPlannerScreenshotReference] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.triggerReasons = triggerReasons
        self.context = context
        self.latestWorldState = latestWorldState
        self.latestAction = latestAction
        self.traceSummaries = traceSummaries
        self.screenshotReferences = screenshotReferences
        self.metadata = metadata
    }
}

public struct SlowPlannerHintGenerationResult: Equatable, Sendable {
    public var hint: StructuredPlannerHint?
    public var metadata: [String: String]

    public init(
        hint: StructuredPlannerHint?,
        metadata: [String: String] = [:]
    ) {
        self.hint = hint
        self.metadata = metadata
    }
}

public protocol SlowPlannerHintGenerating: Sendable {
    func generatePlannerHint(
        snapshot: SlowPlannerSnapshot
    ) async -> SlowPlannerHintGenerationResult
}

public struct SlowPlannerTriggerPolicy: Equatable, Sendable {
    public var lowConfidenceThreshold: Double
    public var repeatedFailureThreshold: Int
    public var triggerOnFirstScene: Bool

    public init(
        lowConfidenceThreshold: Double = 0.5,
        repeatedFailureThreshold: Int = 2,
        triggerOnFirstScene: Bool = true
    ) {
        self.lowConfidenceThreshold = lowConfidenceThreshold
        self.repeatedFailureThreshold = max(1, repeatedFailureThreshold)
        self.triggerOnFirstScene = triggerOnFirstScene
    }

    public func reasons(
        state: HotLoopWorldState,
        action: HotLoopControllerAction,
        previousSceneSignature: String?,
        consecutiveFailureCount: Int,
        recentFailures: [RunFailureSummary],
        userInstruction: String?
    ) -> [SlowPlannerTriggerReason] {
        var reasons: [SlowPlannerTriggerReason] = []
        let signature = sceneSignature(for: state)

        if previousSceneSignature == nil {
            if triggerOnFirstScene {
                reasons.append(.sceneChanged)
            }
        } else if previousSceneSignature != signature {
            reasons.append(.sceneChanged)
        }

        if state.confidence < lowConfidenceThreshold
            || action.confidence < lowConfidenceThreshold
            || action.metadata["fallbackReason"] == "lowConfidence" {
            reasons.append(.lowConfidence)
        }

        if consecutiveFailureCount >= repeatedFailureThreshold
            || recentFailures.count >= repeatedFailureThreshold {
            reasons.append(.repeatedFailure)
        }

        if action.metadata["goalCompleted"] == "true"
            || action.metadata["fallbackReason"] == "alreadyFocused" {
            reasons.append(.goalCompleted)
        }

        if userInstruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            reasons.append(.userInstruction)
        }

        return Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
    }

    public func sceneSignature(for state: HotLoopWorldState) -> String {
        [
            state.targetID,
            String(format: "%.2f", state.confidence),
            state.signalSummaries
                .map { "\($0.kind):\($0.observationCount)" }
                .joined(separator: "|"),
            state.actionAffordances
                .map { "\($0.kind.rawValue):\($0.metadata["localNavigation.candidateID"] ?? $0.id)" }
                .joined(separator: "|"),
            state.metadata["localNavigation.focusedCandidateID"] ?? "",
            state.metadata["localNavigation.frontmostCandidateID"] ?? ""
        ].joined(separator: "::")
    }
}

public actor ValidatedPlannerHintBus {
    private var hints: [StructuredPlannerHint] = []
    private var validationResults: [PlannerHintValidationResult] = []
    private let capacity: Int

    public init(capacity: Int = 10) {
        self.capacity = max(1, capacity)
    }

    @discardableResult
    public func publishIfValid(
        _ hint: StructuredPlannerHint,
        context: PlannerHintValidationContext
    ) -> PlannerHintValidationResult {
        let result = PlannerHintValidator.validate(hint, context: context)
        validationResults.append(result)
        validationResults = Array(validationResults.suffix(capacity))

        if result.isValid {
            hints.append(hint)
            hints = Array(hints.suffix(capacity))
        }

        return result
    }

    public func latestValidHint(
        context: PlannerHintValidationContext
    ) -> StructuredPlannerHint? {
        PlannerHintSelector.latestValidHint(
            from: hints,
            context: context
        )
        .latestValidHint
    }

    public func summaryHints(
        now: RunTraceTimestamp
    ) -> [RunPlannerHint] {
        hints
            .filter { !$0.isExpired(at: now) }
            .map { $0.summaryHint(isValid: true) }
    }

    public func allHints() -> [StructuredPlannerHint] {
        hints
    }

    public func allValidationResults() -> [PlannerHintValidationResult] {
        validationResults
    }
}

public struct PlannerHintAwareControllerPolicy: DryRunControllerPolicy {
    public var base: any DryRunControllerPolicy
    public var hintBus: ValidatedPlannerHintBus
    public var unsafeActions: Set<HotLoopActionKind>
    public var minimumConfidence: Double

    public var name: String {
        "\(base.name)+validated-planner-hints"
    }

    public init(
        base: any DryRunControllerPolicy,
        hintBus: ValidatedPlannerHintBus,
        unsafeActions: Set<HotLoopActionKind> = [],
        minimumConfidence: Double = 0.3
    ) {
        self.base = base
        self.hintBus = hintBus
        self.unsafeActions = unsafeActions
        self.minimumConfidence = minimumConfidence
    }

    public func decide(state: HotLoopWorldState) async -> HotLoopControllerAction {
        var action = await base.decide(state: state)
        let context = PlannerHintValidationContext(
            currentStateID: state.id,
            unsafeActions: unsafeActions,
            minimumConfidence: minimumConfidence,
            now: state.observedAt
        )

        guard let hint = await hintBus.latestValidHint(context: context) else {
            return action
        }

        action.plannerHintID = hint.id
        action.metadata["plannerHintID"] = hint.id
        action.metadata["plannerHintPolicyName"] = hint.policyName
        action.metadata["plannerHintPreferredAction"] = String(hint.preferredActions.contains(action.kind))
        action.metadata["plannerHintAvoidedAction"] = String(hint.avoidActions.contains(action.kind))
        return action
    }
}

public actor DryRunSlowPlannerSidecar {
    private let coordinator: RunCoordinator
    private let memory: InMemoryRunMemory?
    private let hintBus: ValidatedPlannerHintBus
    private let planner: any SlowPlannerHintGenerating
    private let triggerPolicy: SlowPlannerTriggerPolicy
    private let unsafeActions: Set<HotLoopActionKind>
    private let screenshotReferences: [SlowPlannerScreenshotReference]
    private let maxTraceSummaries: Int
    private let memoryRetriever: SemanticRunMemoryRetriever
    private let semanticMemoryBudget: RunMemoryRetrievalBudget

    private var previousSceneSignature: String?
    private var consecutiveFailureCount = 0
    private var snapshotCount = 0
    private var plannerCallCount = 0
    private var publishedHintCount = 0

    public init(
        coordinator: RunCoordinator,
        memory: InMemoryRunMemory? = nil,
        hintBus: ValidatedPlannerHintBus,
        planner: any SlowPlannerHintGenerating,
        triggerPolicy: SlowPlannerTriggerPolicy = SlowPlannerTriggerPolicy(),
        unsafeActions: Set<HotLoopActionKind> = [],
        screenshotReferences: [SlowPlannerScreenshotReference] = [],
        maxTraceSummaries: Int = 5,
        memoryRetriever: SemanticRunMemoryRetriever = SemanticRunMemoryRetriever(),
        semanticMemoryBudget: RunMemoryRetrievalBudget = RunMemoryRetrievalBudget(maxRecords: 4, maxPromptCharacters: 1_200)
    ) {
        self.coordinator = coordinator
        self.memory = memory
        self.hintBus = hintBus
        self.planner = planner
        self.triggerPolicy = triggerPolicy
        self.unsafeActions = unsafeActions
        self.screenshotReferences = screenshotReferences
        self.maxTraceSummaries = max(1, maxTraceSummaries)
        self.memoryRetriever = memoryRetriever
        self.semanticMemoryBudget = semanticMemoryBudget
    }

    public func observe(
        worldState: HotLoopWorldState,
        action: HotLoopControllerAction,
        trace: ReflexTraceRecord,
        userInstruction: String? = nil
    ) async {
        let now = trace.timestamps.inputExecuted
            ?? trace.timestamps.actionEnqueued
            ?? worldState.observedAt
        let memorySnapshot = await memory?.snapshot(now: now)
        let recentFailures = memorySnapshot?.recentFailures ?? []
        updateFailureCounter(action: action)

        let reasons = triggerPolicy.reasons(
            state: worldState,
            action: action,
            previousSceneSignature: previousSceneSignature,
            consecutiveFailureCount: consecutiveFailureCount,
            recentFailures: recentFailures,
            userInstruction: userInstruction
        )
        previousSceneSignature = triggerPolicy.sceneSignature(for: worldState)
        guard !reasons.isEmpty else { return }

        let activeHints = await hintBus.summaryHints(now: now)
        let summary = Self.worldStateSummary(for: worldState)
        await memory?.rememberState(summary)
        let semanticMemoryResults = await retrieveSemanticMemory(
            goal: userInstruction ?? summary.summary,
            memorySnapshot: memorySnapshot
        )

        guard let context = await coordinator.buildContext(
            latestWorldState: summary,
            activeHints: activeHints,
            recentFailures: recentFailures,
            memorySnapshot: memorySnapshot,
            semanticMemoryResults: semanticMemoryResults
        ) else {
            return
        }

        let traces = await coordinator.reflexTraces()
        snapshotCount += 1
        let snapshot = SlowPlannerSnapshot(
            id: "slow-planner-snapshot-\(snapshotCount)",
            triggerReasons: reasons,
            context: context,
            latestWorldState: worldState,
            latestAction: action,
            traceSummaries: Self.traceSummaries(
                from: traces.isEmpty ? [trace] : traces,
                limit: maxTraceSummaries
            ),
            screenshotReferences: screenshotReferences,
            metadata: [
                "rawPixelsExposed": "false",
                "triggerReasons": reasons.map(\.rawValue).joined(separator: ",")
            ]
        )

        let decision = await coordinator.recordToolCall(
            capability: .model,
            toolName: "slow-planner-sidecar"
        )
        guard decision.isAllowed else { return }

        plannerCallCount += 1
        let result = await planner.generatePlannerHint(snapshot: snapshot)
        guard let hint = result.hint else { return }

        let validation = await hintBus.publishIfValid(
            hint,
            context: PlannerHintValidationContext(
                currentStateID: worldState.id,
                unsafeActions: unsafeActions,
                now: now
            )
        )

        if validation.isValid {
            publishedHintCount += 1
            let hints = await hintBus.summaryHints(now: now)
            await memory?.setActiveHints(hints)
        }
    }

    public func stats() -> (snapshotCount: Int, plannerCallCount: Int, publishedHintCount: Int) {
        (snapshotCount, plannerCallCount, publishedHintCount)
    }

    private func updateFailureCounter(action: HotLoopControllerAction) {
        if action.metadata["fallback"] == "true",
           action.metadata["fallbackReason"] != "alreadyFocused" {
            consecutiveFailureCount += 1
        } else {
            consecutiveFailureCount = 0
        }
    }

    private func retrieveSemanticMemory(
        goal: String,
        memorySnapshot: RunMemorySnapshot?
    ) async -> [RunMemorySemanticResult] {
        guard let records = memorySnapshot?.targetRecords,
              !records.isEmpty
        else {
            return []
        }

        return await memoryRetriever.retrieve(
            query: RunMemorySemanticQuery(
                text: goal,
                scope: .target,
                budget: semanticMemoryBudget
            ),
            records: records
        )
    }

    private static func worldStateSummary(for state: HotLoopWorldState) -> RunWorldStateSummary {
        let signalSummary = state.signalSummaries
            .map { "\($0.kind):\($0.observationCount)" }
            .joined(separator: ",")
        let affordanceSummary = state.actionAffordances
            .map(\.kind.rawValue)
            .joined(separator: ",")

        return RunWorldStateSummary(
            stateID: state.id,
            summary: "confidence=\(state.confidence); signals=[\(signalSummary)]; affordances=[\(affordanceSummary)]",
            confidence: state.confidence
        )
    }

    private static func traceSummaries(
        from traces: [ReflexTraceRecord],
        limit: Int
    ) -> [SlowPlannerTraceSummary] {
        traces.suffix(limit).map { trace in
            SlowPlannerTraceSummary(
                traceID: trace.traceID,
                frameID: trace.frameID,
                stateID: trace.stateID,
                actionID: trace.actionID,
                actionKind: trace.metadata["action.kind"],
                confidence: trace.confidence,
                fallbackReason: trace.metadata["fallbackReason"],
                softwareLoopMS: trace.latencyBreakdown.softwareLoopMS
            )
        }
    }
}
