import DonkeyContracts
import Foundation

public struct LocalAppTaskStepTracker: Sendable {
    private var states: [LocalAppTaskWorkflowStage: LocalAppTaskWorkflowStageState]
    private var metadata: [String: String]

    public init(metadata: [String: String] = [:]) {
        self.metadata = metadata
        self.states = Dictionary(
            uniqueKeysWithValues: LocalAppTaskWorkflowStage.allCases.map { stage in
                (
                    stage,
                    LocalAppTaskWorkflowStageState(
                        stage: stage,
                        status: .pending,
                        summary: Self.defaultSummary(for: stage)
                    )
                )
            }
        )
    }

    public mutating func start(
        _ stage: LocalAppTaskWorkflowStage,
        summary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        update(stage, status: .started, summary: summary, metadata: metadata)
    }

    public mutating func complete(
        _ stage: LocalAppTaskWorkflowStage,
        summary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        update(stage, status: .completed, summary: summary, metadata: metadata)
    }

    public mutating func wait(
        _ stage: LocalAppTaskWorkflowStage,
        summary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        update(stage, status: .waiting, summary: summary, metadata: metadata)
    }

    public mutating func skip(
        _ stage: LocalAppTaskWorkflowStage,
        summary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        update(stage, status: .skipped, summary: summary, metadata: metadata)
    }

    public mutating func block(
        _ stage: LocalAppTaskWorkflowStage,
        summary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        update(stage, status: .blocked, summary: summary, metadata: metadata)
    }

    public mutating func fail(
        _ stage: LocalAppTaskWorkflowStage,
        summary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        update(stage, status: .failed, summary: summary, metadata: metadata)
    }

    public mutating func mergeMetadata(_ values: [String: String]) {
        metadata.merge(values) { current, _ in current }
    }

    public func snapshot(metadata extraMetadata: [String: String] = [:]) -> LocalAppTaskWorkflowProgress {
        LocalAppTaskWorkflowProgress(
            stages: LocalAppTaskWorkflowStage.allCases.compactMap { states[$0] },
            metadata: metadata.merging(extraMetadata) { current, _ in current }
        )
    }

    private mutating func update(
        _ stage: LocalAppTaskWorkflowStage,
        status: LocalAppTaskWorkflowStageStatus,
        summary: String?,
        metadata newMetadata: [String: String]
    ) {
        var state = states[stage] ?? LocalAppTaskWorkflowStageState(stage: stage)
        state.status = status
        state.summary = summary ?? state.summary
        state.metadata.merge(newMetadata) { current, _ in current }
        states[stage] = state
    }

    private static func defaultSummary(for stage: LocalAppTaskWorkflowStage) -> String {
        switch stage {
        case .parseIntent:
            return "Parse task intent"
        case .resolveApp:
            return "Resolve task and target app"
        case .observe:
            return "Observe target app state"
        case .evidencePlan:
            return "Build evidence-backed action plan"
        case .approval:
            return "Check user review or approval boundary"
        case .execute:
            return "Execute guarded local-app actions"
        case .verify:
            return "Verify local-app task result"
        }
    }
}
