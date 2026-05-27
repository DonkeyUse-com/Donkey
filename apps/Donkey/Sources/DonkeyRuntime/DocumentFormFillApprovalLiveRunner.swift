@preconcurrency import AppKit
import DonkeyContracts
import Foundation

public enum DocumentFormFillApprovalRunStatus: String, Equatable, Sendable {
    case completed
    case partiallyCompleted
    case noApprovedFields
    case failedSafe
}

public struct DocumentFormFillApprovalRunResult: Equatable, Sendable {
    public var status: DocumentFormFillApprovalRunStatus
    public var approval: DocumentFormFillApproval
    public var actionTraces: [ActionEngineCommandTrace]
    public var metadata: [String: String]

    public init(
        status: DocumentFormFillApprovalRunStatus,
        approval: DocumentFormFillApproval,
        actionTraces: [ActionEngineCommandTrace],
        metadata: [String: String] = [:]
    ) {
        self.status = status
        self.approval = approval
        self.actionTraces = actionTraces
        self.metadata = metadata
    }
}

public struct DocumentFormFillApprovalLiveRunner: Sendable {
    public typealias ActionEngineFactory = @Sendable (LocalAppTaskDefinition) -> ActionEngineGuardrail

    public var planner: DocumentFormFillPlanner
    public var appController: any LocalAppTaskAppControlling
    public var availabilityProvider: any LocalAppAvailabilityProviding
    public var permissionPolicy: ToolCallPolicy
    public var coordinator: RunCoordinator?
    public var actionEngineFactory: ActionEngineFactory

    public init(
        planner: DocumentFormFillPlanner = DocumentFormFillPlanner(),
        appController: any LocalAppTaskAppControlling = MacLocalAppTaskController(),
        availabilityProvider: any LocalAppAvailabilityProviding = MacLocalAppAvailabilityProvider(),
        permissionPolicy: ToolCallPolicy = ToolCallPolicy(
            allowedCapabilities: ToolCallPolicy.defaultAllowedCapabilities.union([.input]),
            deniedCapabilities: []
        ),
        coordinator: RunCoordinator? = nil,
        actionEngineFactory: @escaping ActionEngineFactory = LocalAppTaskActionEngines.accessibility(for:)
    ) {
        self.planner = planner
        self.appController = appController
        self.availabilityProvider = availabilityProvider
        self.permissionPolicy = permissionPolicy
        self.coordinator = coordinator
        self.actionEngineFactory = actionEngineFactory
    }

    public func run(
        plan: DocumentFormFillPlan,
        definition: LocalAppTaskDefinition,
        traceID: String,
        approvedFieldIDs: [String]
    ) async -> DocumentFormFillApprovalRunResult {
        let approval = planner.approval(
            for: plan,
            traceID: traceID,
            approvedFieldIDs: Set(approvedFieldIDs)
        )
        guard !approval.approvedProposals.isEmpty else {
            return DocumentFormFillApprovalRunResult(
                status: .noApprovedFields,
                approval: approval,
                actionTraces: [],
                metadata: ["reason": "noApprovedFields"]
            )
        }

        let targetID = LocalAppTaskAdapter(definition: definition).targetID
        await coordinator?.setTraceID(traceID)
        _ = await coordinator?.start(
            RunSession(
                userGoal: "approve document form fill",
                targetID: targetID,
                runtimeProfile: "document-form-fill-approval",
                permissionPolicy: permissionPolicy
            )
        )

        let availability = availabilityProvider.availability(for: definition.targetApp)
        await coordinator?.recordToolEvent(
            capability: .input,
            decision: permissionPolicy.decision(for: .input),
            toolName: "mac-launch-focus",
            summary: "Refocusing document app before approved field entry",
            traceID: traceID,
            metadata: [
                "targetApp": definition.targetApp.appName,
                "bundleIdentifier": definition.targetApp.bundleIdentifier ?? ""
            ]
        )
        _ = await appController.launchOrFocus(
            definition: definition,
            availability: availability
        )

        let commands = LocalAppAccessibilityActionPlanner().fillCommands(
            approval: approval,
            definition: definition,
            issuedAt: Self.now()
        )
        let engine = actionEngineFactory(definition)
        var traces: [ActionEngineCommandTrace] = []
        for command in commands {
            await coordinator?.recordToolEvent(
                capability: .accessibility,
                decision: permissionPolicy.decision(for: .accessibility),
                toolName: "mac-accessibility-action-engine",
                summary: "Executing approved document field entry",
                traceID: traceID,
                metadata: [
                    "commandID": command.id,
                    "fieldID": command.metadata["accessibility.nodeID"] ?? ""
                ]
            )
            let trace = await engine.handle(command, permissionPolicy: permissionPolicy)
            traces.append(trace)
            guard trace.executed || trace.decision == .skippedNoLiveInput else {
                break
            }
        }

        let executedCount = traces.filter(\.executed).count
        let status: DocumentFormFillApprovalRunStatus
        if executedCount == approval.approvedProposals.count {
            status = .completed
            await coordinator?.complete(reason: "Approved document form fields filled")
        } else if executedCount > 0 {
            status = .partiallyCompleted
            await coordinator?.pause(reason: "Document form fill partially completed")
        } else {
            status = .failedSafe
            await coordinator?.fail(reason: "Document form fill approval was not executed")
        }

        return DocumentFormFillApprovalRunResult(
            status: status,
            approval: approval,
            actionTraces: traces,
            metadata: [
                "approvedFieldCount": String(approval.approvedProposals.count),
                "executedCommandCount": String(executedCount)
            ]
        )
    }

    private static func now() -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(),
            monotonicUptimeNanoseconds: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        )
    }
}
