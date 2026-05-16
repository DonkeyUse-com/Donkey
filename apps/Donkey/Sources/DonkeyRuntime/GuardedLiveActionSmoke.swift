import DonkeyContracts
import Foundation

public enum GuardedLiveActionSmokeStatus: String, Codable, Equatable, Sendable {
    case executed
    case skipped
    case denied
}

public struct GuardedLiveActionSmokeResult: Equatable, Sendable {
    public var status: GuardedLiveActionSmokeStatus
    public var reason: String
    public var commandTrace: ActionEngineCommandTrace?
    public var metadata: [String: String]

    public init(
        status: GuardedLiveActionSmokeStatus,
        reason: String,
        commandTrace: ActionEngineCommandTrace? = nil,
        metadata: [String: String] = [:]
    ) {
        self.status = status
        self.reason = reason
        self.commandTrace = commandTrace
        self.metadata = metadata
    }
}

public struct GuardedLiveActionSmokeRunner: Sendable {
    public var actionEngine: ActionEngineGuardrail

    public init(actionEngine: ActionEngineGuardrail) {
        self.actionEngine = actionEngine
    }

    public func run(
        dryRunResult: DryRunReflexLoopResult,
        latencyReport: ReflexLatencyReport,
        session: RunSession,
        issuedAt: RunTraceTimestamp
    ) async -> GuardedLiveActionSmokeResult {
        guard latencyReport.traceCount > 0,
              latencyReport.softwareLoopMS.p95 != nil
        else {
            return GuardedLiveActionSmokeResult(
                status: .skipped,
                reason: "dry-run latency report is missing p95 evidence",
                metadata: reportMetadata(latencyReport)
            )
        }

        guard let state = dryRunResult.latestWorldState,
              let action = dryRunResult.latestAction
        else {
            return GuardedLiveActionSmokeResult(
                status: .skipped,
                reason: "dry-run loop did not produce state and action"
            )
        }

        guard action.metadata["fallback"] != "true" else {
            return GuardedLiveActionSmokeResult(
                status: .skipped,
                reason: "latest dry-run action is a fallback",
                metadata: [
                    "fallbackReason": action.metadata["fallbackReason"] ?? "unknown"
                ]
            )
        }

        guard let command = Self.command(
            for: action,
            state: state,
            targetID: session.targetID,
            issuedAt: issuedAt
        ) else {
            return GuardedLiveActionSmokeResult(
                status: .skipped,
                reason: "latest dry-run action cannot be mapped to a live command",
                metadata: [
                    "action.kind": action.kind.rawValue
                ]
            )
        }

        let trace = await actionEngine.handle(
            command,
            permissionPolicy: session.permissionPolicy
        )

        switch trace.decision {
        case .executedLive:
            return GuardedLiveActionSmokeResult(
                status: .executed,
                reason: "guarded live action executed",
                commandTrace: trace,
                metadata: reportMetadata(latencyReport)
            )
        case .projectedDryRun:
            return GuardedLiveActionSmokeResult(
                status: .skipped,
                reason: "action engine projected dry-run instead of live input",
                commandTrace: trace,
                metadata: reportMetadata(latencyReport)
            )
        case .denied(let reason):
            return GuardedLiveActionSmokeResult(
                status: .denied,
                reason: reason,
                commandTrace: trace,
                metadata: reportMetadata(latencyReport)
            )
        }
    }

    public static func command(
        for action: HotLoopControllerAction,
        state: HotLoopWorldState,
        targetID: String,
        issuedAt: RunTraceTimestamp
    ) -> ActionEngineCommand? {
        switch action.kind {
        case .tapTarget, .focusWindow, .switchTab, .activateCandidate:
            guard let target = action.target else { return nil }
            return ActionEngineCommand(
                id: "live-smoke-\(action.id)",
                traceID: action.traceID,
                targetID: targetID,
                stateID: state.id,
                actionID: action.id,
                kind: .tap,
                issuedAt: issuedAt,
                targetBounds: target,
                metadata: [
                    "sourceActionKind": action.kind.rawValue,
                    "smoke": "guardedLiveAction"
                ].merging(action.metadata) { current, _ in current }
            )
        case .observe, .wait, .openAppSwitcher:
            return nil
        }
    }

    private func reportMetadata(_ report: ReflexLatencyReport) -> [String: String] {
        [
            "dryRun.traceCount": String(report.traceCount),
            "dryRun.softwareLoopP95MS": format(report.softwareLoopMS.p95),
            "dryRun.droppedFrameCount": String(report.droppedFrameCount),
            "dryRun.staleActionCount": String(report.staleActionCount)
        ]
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return String(format: "%.2f", value)
    }
}
