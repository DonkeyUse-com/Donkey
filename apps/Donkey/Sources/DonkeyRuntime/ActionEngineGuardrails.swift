import DonkeyContracts
import Foundation

public enum ActionEngineCommandKind: String, Codable, Equatable, Sendable {
    case tap
    case swipe
    case key
    case mouse
    case controller
    case releaseAll
}

public struct ActionEngineCommand: Codable, Equatable, Sendable {
    public var id: String
    public var traceID: String
    public var targetID: String
    public var stateID: String?
    public var actionID: String?
    public var kind: ActionEngineCommandKind
    public var issuedAt: RunTraceTimestamp
    public var targetBounds: HotLoopRect?
    public var key: String?
    public var holdDurationMS: Double?
    public var metadata: [String: String]

    public init(
        id: String,
        traceID: String,
        targetID: String,
        stateID: String? = nil,
        actionID: String? = nil,
        kind: ActionEngineCommandKind,
        issuedAt: RunTraceTimestamp,
        targetBounds: HotLoopRect? = nil,
        key: String? = nil,
        holdDurationMS: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.traceID = traceID
        self.targetID = targetID
        self.stateID = stateID
        self.actionID = actionID
        self.kind = kind
        self.issuedAt = issuedAt
        self.targetBounds = targetBounds
        self.key = key
        self.holdDurationMS = holdDurationMS
        self.metadata = metadata
    }
}

public enum ActionEngineCommandDecision: Codable, Equatable, Sendable {
    case skippedNoLiveInput
    case executedLive
    case denied(reason: String)
}

public struct ActionEngineCommandTrace: Codable, Equatable, Sendable {
    public var command: ActionEngineCommand
    public var decision: ActionEngineCommandDecision
    public var recordedAt: RunTraceTimestamp
    public var executed: Bool
    public var liveInputEnabled: Bool
    public var focusGuardPassed: Bool
    public var permissionDecision: ToolCallDecision
    public var rateLimited: Bool
    public var releaseAll: Bool
    public var metadata: [String: String]

    public init(
        command: ActionEngineCommand,
        decision: ActionEngineCommandDecision,
        recordedAt: RunTraceTimestamp,
        executed: Bool,
        liveInputEnabled: Bool,
        focusGuardPassed: Bool,
        permissionDecision: ToolCallDecision,
        rateLimited: Bool,
        releaseAll: Bool,
        metadata: [String: String] = [:]
    ) {
        self.command = command
        self.decision = decision
        self.recordedAt = recordedAt
        self.executed = executed
        self.liveInputEnabled = liveInputEnabled
        self.focusGuardPassed = focusGuardPassed
        self.permissionDecision = permissionDecision
        self.rateLimited = rateLimited
        self.releaseAll = releaseAll
        self.metadata = metadata
    }
}

public struct ActionEngineConfiguration: Equatable, Sendable {
    public var liveInputEnabled: Bool
    public var minimumCommandIntervalMS: Double
    public var maximumHoldDurationMS: Double

    public init(
        liveInputEnabled: Bool = false,
        minimumCommandIntervalMS: Double = 20,
        maximumHoldDurationMS: Double = 500
    ) {
        self.liveInputEnabled = liveInputEnabled
        self.minimumCommandIntervalMS = minimumCommandIntervalMS
        self.maximumHoldDurationMS = maximumHoldDurationMS
    }
}

public protocol ActionEngineFocusGuard: Sendable {
    func targetIsSafeForInput(targetID: String) async -> Bool
}

public struct ActionEngineInputBackendResult: Equatable, Sendable {
    public var executed: Bool
    public var completedAt: RunTraceTimestamp
    public var metadata: [String: String]

    public init(
        executed: Bool,
        completedAt: RunTraceTimestamp,
        metadata: [String: String] = [:]
    ) {
        self.executed = executed
        self.completedAt = completedAt
        self.metadata = metadata
    }
}

public protocol ActionEngineInputBackend: Sendable {
    func execute(_ command: ActionEngineCommand) async -> ActionEngineInputBackendResult
}

public struct AlwaysSafeActionEngineFocusGuard: ActionEngineFocusGuard {
    public init() {}

    public func targetIsSafeForInput(targetID: String) async -> Bool {
        true
    }
}

public struct UnavailableActionEngineInputBackend: ActionEngineInputBackend {
    public init() {}

    public func execute(_ command: ActionEngineCommand) async -> ActionEngineInputBackendResult {
        ActionEngineInputBackendResult(
            executed: false,
            completedAt: command.issuedAt,
            metadata: [
                "liveInputBackend": "notImplemented"
            ]
        )
    }
}

public actor ActionEngineGuardrail {
    private let configuration: ActionEngineConfiguration
    private let focusGuard: any ActionEngineFocusGuard
    private let inputBackend: any ActionEngineInputBackend
    private var traces: [ActionEngineCommandTrace] = []
    private var heldCommandIDs: Set<String> = []
    private var lastAcceptedCommandAt: RunTraceTimestamp?

    public init(
        configuration: ActionEngineConfiguration = ActionEngineConfiguration(),
        focusGuard: any ActionEngineFocusGuard = AlwaysSafeActionEngineFocusGuard(),
        inputBackend: any ActionEngineInputBackend = UnavailableActionEngineInputBackend()
    ) {
        self.configuration = configuration
        self.focusGuard = focusGuard
        self.inputBackend = inputBackend
    }

    @discardableResult
    public func handle(
        _ command: ActionEngineCommand,
        permissionPolicy: ToolCallPolicy = .default
    ) async -> ActionEngineCommandTrace {
        if command.kind == .releaseAll {
            heldCommandIDs.removeAll()
            return appendTrace(
                command: command,
                decision: .skippedNoLiveInput,
                focusGuardPassed: true,
                permissionDecision: .allow,
                rateLimited: false,
                releaseAll: true,
                metadata: ["heldInputReleased": "true"]
            )
        }

        let permissionDecision = permissionPolicy.decision(for: .input)
        guard permissionDecision.isAllowed else {
            return appendTrace(
                command: command,
                decision: .denied(reason: "input permission denied"),
                focusGuardPassed: false,
                permissionDecision: permissionDecision,
                rateLimited: false,
                releaseAll: false
            )
        }

        let focusPassed = await focusGuard.targetIsSafeForInput(targetID: command.targetID)
        guard focusPassed else {
            return appendTrace(
                command: command,
                decision: .denied(reason: "focus guard failed"),
                focusGuardPassed: false,
                permissionDecision: permissionDecision,
                rateLimited: false,
                releaseAll: false
            )
        }

        if let holdDurationMS = command.holdDurationMS,
           holdDurationMS > configuration.maximumHoldDurationMS {
            return appendTrace(
                command: command,
                decision: .denied(reason: "hold duration exceeds maximum"),
                focusGuardPassed: true,
                permissionDecision: permissionDecision,
                rateLimited: false,
                releaseAll: false,
                metadata: [
                    "maximumHoldDurationMS": String(configuration.maximumHoldDurationMS)
                ]
            )
        }

        if let lastAcceptedCommandAt,
           let elapsedMS = lastAcceptedCommandAt.milliseconds(until: command.issuedAt),
           elapsedMS < configuration.minimumCommandIntervalMS {
            return appendTrace(
                command: command,
                decision: .denied(reason: "rate limited"),
                focusGuardPassed: true,
                permissionDecision: permissionDecision,
                rateLimited: true,
                releaseAll: false,
                metadata: [
                    "minimumCommandIntervalMS": String(configuration.minimumCommandIntervalMS),
                    "elapsedMS": String(elapsedMS)
                ]
            )
        }

        lastAcceptedCommandAt = command.issuedAt

        guard configuration.liveInputEnabled else {
            if (command.holdDurationMS ?? 0) > 0 {
                heldCommandIDs.insert(command.id)
            }

            return appendTrace(
                command: command,
                decision: .skippedNoLiveInput,
                executed: false,
                focusGuardPassed: true,
                permissionDecision: permissionDecision,
                rateLimited: false,
                releaseAll: false,
                metadata: [
                    "heldInputCount": String(heldCommandIDs.count),
                    "liveInputBackend": "disabled"
                ]
            )
        }

        let backendResult = await inputBackend.execute(command)
        if backendResult.executed, (command.holdDurationMS ?? 0) > 0 {
            heldCommandIDs.insert(command.id)
        }

        var metadata = backendResult.metadata
        metadata["heldInputCount"] = String(heldCommandIDs.count)
        metadata["liveInputCompletedAt"] = String(backendResult.completedAt.monotonicUptimeNanoseconds)

        return appendTrace(
            command: command,
            decision: backendResult.executed
                ? .executedLive
                : .denied(reason: "live input backend did not execute"),
            executed: backendResult.executed,
            recordedAt: backendResult.completedAt,
            focusGuardPassed: true,
            permissionDecision: permissionDecision,
            rateLimited: false,
            releaseAll: false,
            metadata: metadata
        )
    }

    public func releaseAll(
        traceID: String,
        targetID: String,
        issuedAt: RunTraceTimestamp
    ) async -> ActionEngineCommandTrace {
        await handle(
            ActionEngineCommand(
                id: "release-all-\(traceID)",
                traceID: traceID,
                targetID: targetID,
                kind: .releaseAll,
                issuedAt: issuedAt
            ),
            permissionPolicy: ToolCallPolicy(deniedCapabilities: [])
        )
    }

    public func allTraces() -> [ActionEngineCommandTrace] {
        traces
    }

    public func heldInputCount() -> Int {
        heldCommandIDs.count
    }

    private func appendTrace(
        command: ActionEngineCommand,
        decision: ActionEngineCommandDecision,
        executed: Bool = false,
        recordedAt: RunTraceTimestamp? = nil,
        focusGuardPassed: Bool,
        permissionDecision: ToolCallDecision,
        rateLimited: Bool,
        releaseAll: Bool,
        metadata: [String: String] = [:]
    ) -> ActionEngineCommandTrace {
        let trace = ActionEngineCommandTrace(
            command: command,
            decision: decision,
            recordedAt: recordedAt ?? command.issuedAt,
            executed: executed,
            liveInputEnabled: configuration.liveInputEnabled,
            focusGuardPassed: focusGuardPassed,
            permissionDecision: permissionDecision,
            rateLimited: rateLimited,
            releaseAll: releaseAll,
            metadata: metadata
        )

        traces.append(trace)
        return trace
    }
}
