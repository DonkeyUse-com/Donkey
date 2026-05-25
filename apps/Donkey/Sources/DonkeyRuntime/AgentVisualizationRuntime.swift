import DonkeyContracts
import Foundation

public enum LocalAppTaskAgentVisualizationBuilder {
    public static func plan(
        for result: LocalAppTaskLiveRunResult,
        sourceTraceID: String? = nil
    ) -> AgentVisualizationPlan? {
        guard let definition = result.resolution.definition else { return nil }

        let evidencePlan = result.finalActionPlan ?? result.initialActionPlan
        let initialStepsByID = Dictionary(
            uniqueKeysWithValues: (result.initialActionPlan?.steps ?? []).map { ($0.id, $0) }
        )
        var steps = (evidencePlan?.steps ?? []).map { actionPlanStep in
            visualizationStep(
                from: actionPlanStep,
                definition: definition,
                fallbackStep: initialStepsByID[actionPlanStep.id],
                actionTrace: matchingTrace(for: actionPlanStep, in: result.actionTraces)
            )
        }

        let actionPlanStepIDs = Set((evidencePlan?.steps ?? []).map(\.id))
        let extraTraceSteps = result.actionTraces
            .filter { trace in
                guard let workflowStepID = trace.command.metadata["workflowStepID"] else { return true }
                return !actionPlanStepIDs.contains(workflowStepID)
            }
            .map { trace in
                actionTraceStep(
                    trace,
                    definition: definition
                )
            }
        steps.append(contentsOf: extraTraceSteps)

        guard !steps.isEmpty else { return nil }

        let verification = verificationReport(for: result)
        let cursorGuideEligible = steps.contains(where: hasCursorTarget)
        return AgentVisualizationPlan(
            id: "agent-visualization-\(result.traceID)",
            title: title(for: result, definition: definition),
            executionMode: .live,
            sourceTraceID: sourceTraceID ?? result.traceID,
            steps: steps,
            verification: verification,
            metadata: [
                "source": "local-app-live-runner",
                "targetApp": definition.targetApp.appName,
                "taskType": definition.taskType,
                "realPointerMoved": "false",
                "cursorGuideEligible": String(cursorGuideEligible),
                "cursorGuide.reason": cursorGuideEligible ? "" : "noGroundedTargets",
                "actionTraceCount": String(result.actionTraces.count),
                "workflowStageCount": String(result.workflowProgress.stages.count)
            ].merging(result.metadata.filter { key, _ in
                key.hasPrefix("latency.") || key.hasPrefix("verification.")
            }) { current, _ in current }
        )
    }

    private static func visualizationStep(
        from step: LocalAppEvidenceBackedActionStep,
        definition: LocalAppTaskDefinition,
        fallbackStep: LocalAppEvidenceBackedActionStep?,
        actionTrace: ActionEngineCommandTrace?
    ) -> AgentVisualizationStep {
        var metadata = step.metadata.merging([
            "evidencePlan.stepID": step.id,
            "evidencePlan.stepRole": step.role.rawValue,
            "evidencePlan.stepStatus": step.status.rawValue,
            "targetApp": definition.targetApp.appName
        ]) { current, _ in current }

        if let actionTrace {
            metadata.merge(actionTraceMetadata(actionTrace)) { current, _ in current }
        }
        if LocalAppObservationGeometry.normalizedStepBounds(metadata: metadata) == nil,
           let fallbackStep {
            metadata.merge(fallbackStep.metadata.filter { key, _ in
                key.hasPrefix("control.")
            }) { current, _ in current }
        }
        let groundedBounds = LocalAppObservationGeometry.normalizedStepBounds(metadata: metadata)
        let actionTraceBounds = normalizedBounds(actionTrace?.command.targetBounds)
        let targetSource = groundingSource(
            metadata["control.source"],
            fallback: actionTrace == nil ? .evidenceBackedActionPlan : .actionTrace
        )
        let target = stepTarget(
            point: centerPoint(for: groundedBounds) ?? centerPoint(for: actionTraceBounds),
            bounds: groundedBounds ?? actionTraceBounds,
            description: step.summary,
            controlID: step.metadata["controlID"],
            source: groundedBounds == nil ? (actionTraceBounds == nil ? nil : .actionTrace) : targetSource,
            confidence: groundedBounds == nil ? confidence(for: step.status, actionTrace: actionTrace) : 0.9,
            metadata: metadata
        )

        return AgentVisualizationStep(
            id: step.id,
            kind: kind(for: step.role),
            label: label(for: step),
            target: target,
            travelDuration: duration(for: step.role).travel,
            holdDuration: duration(for: step.role).hold,
            metadata: metadata
        )
    }

    private static func actionTraceStep(
        _ trace: ActionEngineCommandTrace,
        definition: LocalAppTaskDefinition
    ) -> AgentVisualizationStep {
        let role = trace.command.metadata["workflowStepRole"] ?? "custom"
        let label = trace.executed ? "Acted safely" : "Checked action safety"
        var metadata = actionTraceMetadata(trace)
        metadata["targetApp"] = definition.targetApp.appName
        metadata["workflowStepRole"] = role

        return AgentVisualizationStep(
            id: trace.command.id,
            kind: kind(forActionTraceRole: role),
            label: label,
            target: stepTarget(
                point: centerPoint(for: normalizedBounds(trace.command.targetBounds)),
                bounds: normalizedBounds(trace.command.targetBounds),
                description: trace.command.metadata["workflowStepID"] ?? trace.command.id,
                controlID: trace.command.metadata["controlID"],
                source: .actionTrace,
                confidence: trace.executed ? 0.88 : 0.45,
                metadata: metadata
            ),
            travelDuration: 0.55,
            holdDuration: 1.0,
            metadata: metadata
        )
    }

    private static func matchingTrace(
        for step: LocalAppEvidenceBackedActionStep,
        in traces: [ActionEngineCommandTrace]
    ) -> ActionEngineCommandTrace? {
        traces.first { trace in
            trace.command.metadata["workflowStepID"] == step.id
        }
    }

    private static func verificationReport(
        for result: LocalAppTaskLiveRunResult
    ) -> AgentVisualizationVerificationReport {
        let status: AgentVisualizationVerificationStatus
        switch result.status {
        case .completed:
            status = .verified
        case .needsUserReview, .needsConfirmation:
            status = .needsReview
        case .appUnavailable, .unsupportedCommand:
            status = .blocked
        case .failedSafe:
            status = .failed
        }

        let verificationStep = result.finalActionPlan?.steps.first(where: { $0.role == .verifyResult })
            ?? result.initialActionPlan?.steps.first(where: { $0.role == .verifyResult })
        let confidence = result.finalActionPlan?.verificationConfidence
            ?? result.initialActionPlan?.verificationConfidence
            ?? 0
        return AgentVisualizationVerificationReport(
            status: status,
            summary: verificationStep?.summary ?? result.status.rawValue,
            confidence: confidence,
            evidenceCount: result.actionTraces.count + (result.observation == nil ? 0 : 1),
            metadata: (verificationStep?.metadata ?? [:]).merging([
                "liveRun.status": result.status.rawValue
            ]) { current, _ in current }
        )
    }

    private static func title(
        for result: LocalAppTaskLiveRunResult,
        definition: LocalAppTaskDefinition
    ) -> String {
        if result.status == .completed {
            return "Did \(definition.targetApp.appName)"
        }
        return "Worked in \(definition.targetApp.appName)"
    }

    private static func label(for step: LocalAppEvidenceBackedActionStep) -> String {
        label(for: step.role, summary: step.summary)
    }

    private static func label(
        for role: LocalAppTaskStepRole,
        summary: String
    ) -> String {
        switch role {
        case .parseIntent:
            return "Planning the task"
        case .launchOrFocusApp:
            return "Opening the app"
        case .observeApp:
            return "Checking the screen"
        case .focusControl:
            return "Finding the control"
        case .enterText:
            return "Entering text"
        case .submit:
            return "Submitting"
        case .verifyResult:
            return "Verifying the result"
        case .custom:
            return summary
        }
    }

    private static func kind(for role: LocalAppTaskStepRole) -> AgentVisualizationStepKind {
        switch role {
        case .parseIntent:
            return .plan
        case .launchOrFocusApp:
            return .navigate
        case .observeApp:
            return .observe
        case .focusControl:
            return .focusControl
        case .enterText:
            return .enterText
        case .submit:
            return .submit
        case .verifyResult:
            return .verify
        case .custom:
            return .moveToTarget
        }
    }

    private static func kind(forActionTraceRole role: String) -> AgentVisualizationStepKind {
        switch role {
        case LocalAppTaskStepRole.focusControl.rawValue:
            return .focusControl
        case LocalAppTaskStepRole.enterText.rawValue:
            return .enterText
        case LocalAppTaskStepRole.submit.rawValue:
            return .submit
        default:
            return .moveToTarget
        }
    }

    private static func confidence(
        for status: LocalAppTaskStepStatus,
        actionTrace: ActionEngineCommandTrace?
    ) -> Double {
        if actionTrace?.executed == true { return 0.9 }
        switch status {
        case .verified:
            return 0.84
        case .needsEvidence:
            return 0.35
        case .blocked:
            return 0.2
        }
    }

    private static func duration(for role: LocalAppTaskStepRole) -> (travel: TimeInterval, hold: TimeInterval) {
        switch role {
        case .enterText:
            return (0.45, 1.0)
        case .submit:
            return (0.35, 0.8)
        case .verifyResult:
            return (0.6, 1.2)
        default:
            return (0.55, 1.0)
        }
    }

    private static func centerPoint(for rect: HotLoopRect?) -> HotLoopPoint? {
        guard let rect,
              rect.space == .normalizedTarget else {
            return nil
        }

        return point(
            rect.origin.x + rect.size.width / 2,
            rect.origin.y + rect.size.height / 2
        )
    }

    private static func normalizedBounds(_ rect: HotLoopRect?) -> HotLoopRect? {
        guard let rect,
              rect.space == .normalizedTarget,
              rect.hasPositiveArea else {
            return nil
        }
        return rect
    }

    private static func stepTarget(
        point: HotLoopPoint?,
        bounds: HotLoopRect?,
        description: String,
        controlID: String?,
        source: AgentVisualizationGroundingSource?,
        confidence: Double,
        metadata: [String: String]
    ) -> AgentVisualizationStepTarget? {
        let usableBounds = normalizedBounds(bounds)
        guard let source,
              point != nil || usableBounds != nil
        else {
            return nil
        }

        return AgentVisualizationStepTarget(
            point: point,
            bounds: usableBounds,
            description: description,
            controlID: controlID,
            source: source,
            confidence: confidence,
            metadata: metadata
        )
    }

    private static func hasCursorTarget(_ step: AgentVisualizationStep) -> Bool {
        if step.target?.point?.space == .normalizedTarget {
            return true
        }
        return step.target?.bounds?.space == .normalizedTarget
    }

    private static func groundingSource(
        _ value: String?,
        fallback: AgentVisualizationGroundingSource
    ) -> AgentVisualizationGroundingSource {
        guard let value,
              let source = AgentVisualizationGroundingSource(rawValue: value)
        else {
            return fallback
        }
        return source
    }

    private static func point(_ x: Double, _ y: Double) -> HotLoopPoint {
        HotLoopPoint(x: min(max(x, 0.04), 0.96), y: min(max(y, 0.06), 0.94), space: .normalizedTarget)
    }

    private static func actionTraceMetadata(_ trace: ActionEngineCommandTrace) -> [String: String] {
        [
            "actionTrace.commandID": trace.command.id,
            "actionTrace.executed": String(trace.executed),
            "actionTrace.decision": decisionDescription(trace.decision),
            "actionTrace.focusGuardPassed": String(trace.focusGuardPassed),
            "actionTrace.rateLimited": String(trace.rateLimited),
            "actionTrace.liveInputEnabled": String(trace.liveInputEnabled)
        ].merging(trace.command.metadata) { current, _ in current }
    }

    private static func decisionDescription(_ decision: ActionEngineCommandDecision) -> String {
        switch decision {
        case .skippedNoLiveInput:
            return "skippedNoLiveInput"
        case .executedLive:
            return "executedLive"
        case .denied(let reason):
            return "denied:\(reason)"
        }
    }
}

public struct AgentVisualizationGrounder: Sendable {
    public init() {}

    public func ground(
        plan: AgentVisualizationPlan,
        targetAppName: String?,
        candidates: [MacWindowTargetCandidate]
    ) -> AgentVisualizationPlan {
        guard let target = candidate(
            named: targetAppName ?? plan.metadata["targetApp"],
            in: candidates
        ) else {
            return plan
        }

        guard target.safetyAssessment.status == .allowed else {
            return blockedPlan(plan, target: target)
        }

        var grounded = plan
        grounded.steps = grounded.steps.map { step in
            var copy = step
            let targetMetadata = [
                "target.windowID": String(target.windowID),
                "target.appName": target.appName ?? "",
                "target.bundleIdentifier": target.bundleIdentifier ?? "",
                "target.bounds.x": String(target.bounds.x),
                "target.bounds.y": String(target.bounds.y),
                "target.bounds.width": String(target.bounds.width),
                "target.bounds.height": String(target.bounds.height),
                "target.bounds.space": HotLoopCoordinateSpace.screen.rawValue,
                "grounding.source": AgentVisualizationGroundingSource.windowMetadata.rawValue
            ]
            if var stepTarget = copy.target {
                stepTarget.metadata = stepTarget.metadata.merging(targetMetadata) { current, _ in current }
                copy.target = stepTarget
            }
            copy.metadata = copy.metadata.merging(targetMetadata) { current, _ in current }
            return copy
        }
        grounded.metadata["grounding.source"] = AgentVisualizationGroundingSource.windowMetadata.rawValue
        grounded.metadata["grounding.targetWindowID"] = String(target.windowID)
        grounded.metadata["target.bounds.x"] = String(target.bounds.x)
        grounded.metadata["target.bounds.y"] = String(target.bounds.y)
        grounded.metadata["target.bounds.width"] = String(target.bounds.width)
        grounded.metadata["target.bounds.height"] = String(target.bounds.height)
        grounded.metadata["target.bounds.space"] = HotLoopCoordinateSpace.screen.rawValue
        return grounded
    }

    private func blockedPlan(
        _ plan: AgentVisualizationPlan,
        target: MacWindowTargetCandidate
    ) -> AgentVisualizationPlan {
        var blocked = plan
        blocked.steps = [
            AgentVisualizationStep(
                id: "\(plan.id)-blocked",
                kind: .recover,
                label: "Stopped on a sensitive screen",
                target: nil,
                holdDuration: 1.4,
                metadata: [
                    "target.windowID": String(target.windowID),
                    "target.safety.status": target.safetyAssessment.status.rawValue,
                    "target.safety.reasons": target.safetyAssessment.reasons.map(\.rawValue).joined(separator: ",")
                ]
            )
        ]
        blocked.verification = AgentVisualizationVerificationReport(
            status: .blocked,
            summary: target.safetyAssessment.summary,
            confidence: 1,
            evidenceCount: 1,
            metadata: [
                "target.windowID": String(target.windowID),
                "target.safety.status": target.safetyAssessment.status.rawValue,
                "screenshotGroundingAllowed": "false"
            ]
        )
        blocked.metadata["grounding.blocked"] = "true"
        blocked.metadata["screenshotGroundingAllowed"] = "false"
        return blocked
    }

    private func candidate(
        named appName: String?,
        in candidates: [MacWindowTargetCandidate]
    ) -> MacWindowTargetCandidate? {
        guard let appName,
              !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return candidates.first(where: \.isFocused) ?? candidates.first(where: \.isFrontmost)
        }

        let normalized = normalize(appName)
        return candidates.first { candidate in
            normalize(candidate.appName ?? "") == normalized
                || normalize(candidate.bundleIdentifier ?? "") == normalized
                || normalize(candidate.title ?? "") == normalized
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
