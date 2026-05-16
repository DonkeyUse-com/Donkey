import DonkeyContracts
import Foundation

public enum AIModelProvider: String, Codable, Equatable, Sendable {
    case openAI
}

public enum AIModelRole: String, Codable, Equatable, Sendable {
    case plannerHint
    case traceSummary
    case recovery
}

public enum AIModelCapability: String, Codable, Equatable, Hashable, Sendable {
    case textInput
    case structuredOutputs
    case imageInput
}

public enum AIModelEvalStatus: String, Codable, Equatable, Sendable {
    case candidate
    case passing
    case failing
    case disabled
}

public struct AIModelRegistryEntry: Codable, Equatable, Sendable {
    public var id: String
    public var role: AIModelRole
    public var provider: AIModelProvider
    public var modelID: String
    public var endpoint: URL
    public var capabilities: Set<AIModelCapability>
    public var timeoutMS: Int
    public var promptVersion: String
    public var evalStatus: AIModelEvalStatus
    public var docsURL: URL
    public var rollbackID: String?
    public var metadata: [String: String]

    public init(
        id: String,
        role: AIModelRole,
        provider: AIModelProvider,
        modelID: String,
        endpoint: URL,
        capabilities: Set<AIModelCapability>,
        timeoutMS: Int,
        promptVersion: String,
        evalStatus: AIModelEvalStatus,
        docsURL: URL,
        rollbackID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.provider = provider
        self.modelID = modelID
        self.endpoint = endpoint
        self.capabilities = capabilities
        self.timeoutMS = timeoutMS
        self.promptVersion = promptVersion
        self.evalStatus = evalStatus
        self.docsURL = docsURL
        self.rollbackID = rollbackID
        self.metadata = metadata
    }
}

public struct AIModelRegistry: Codable, Equatable, Sendable {
    public var entries: [AIModelRegistryEntry]

    public init(entries: [AIModelRegistryEntry]) {
        self.entries = entries
    }

    public static let defaultOpenAIPlanner = AIModelRegistry(
        entries: [
            AIModelRegistryEntry(
                id: "openai-planner-hint-default",
                role: .plannerHint,
                provider: .openAI,
                modelID: "gpt-5.2",
                endpoint: URL(string: "https://api.openai.com/v1/responses")!,
                capabilities: [.textInput, .structuredOutputs],
                timeoutMS: 8_000,
                promptVersion: "planner-hint-v1",
                evalStatus: .candidate,
                docsURL: URL(string: "https://platform.openai.com/docs/api-reference/responses/create")!,
                rollbackID: nil,
                metadata: [
                    "lastVerifiedAt": "2026-05-16",
                    "docsSource": "official OpenAI Responses API and models docs"
                ]
            )
        ]
    )
}

public enum AIModelJobType: String, Codable, Equatable, Sendable {
    case plannerHint
    case traceSummary
    case recovery
}

public enum AIModelRisk: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum AIModelPrivacyMode: String, Codable, Equatable, Sendable {
    case standard
    case privacySensitive
}

public enum AIModelLatencyTolerance: String, Codable, Equatable, Sendable {
    case interactive
    case background
}

public struct AIModelRouteRequest: Codable, Equatable, Sendable {
    public var jobType: AIModelJobType
    public var risk: AIModelRisk
    public var privacyMode: AIModelPrivacyMode
    public var latencyTolerance: AIModelLatencyTolerance
    public var failedModelEntryIDs: Set<String>
    public var requiredCapabilities: Set<AIModelCapability>

    public init(
        jobType: AIModelJobType,
        risk: AIModelRisk = .low,
        privacyMode: AIModelPrivacyMode = .privacySensitive,
        latencyTolerance: AIModelLatencyTolerance = .interactive,
        failedModelEntryIDs: Set<String> = [],
        requiredCapabilities: Set<AIModelCapability> = [.structuredOutputs]
    ) {
        self.jobType = jobType
        self.risk = risk
        self.privacyMode = privacyMode
        self.latencyTolerance = latencyTolerance
        self.failedModelEntryIDs = failedModelEntryIDs
        self.requiredCapabilities = requiredCapabilities
    }
}

public enum AIModelRouteError: Error, Equatable, Sendable {
    case noMatchingModel
}

public struct AIModelRouter: Sendable {
    public var registry: AIModelRegistry

    public init(registry: AIModelRegistry = .defaultOpenAIPlanner) {
        self.registry = registry
    }

    public func route(
        _ request: AIModelRouteRequest
    ) throws -> AIModelRegistryEntry {
        let role = role(for: request.jobType)
        let candidates = registry.entries
            .filter { entry in
                entry.role == role
                    && entry.evalStatus != .disabled
                    && !request.failedModelEntryIDs.contains(entry.id)
                    && request.requiredCapabilities.isSubset(of: entry.capabilities)
                    && allowsRisk(request.risk, entry: entry)
            }
            .sorted { lhs, rhs in
                score(lhs, request: request) > score(rhs, request: request)
            }

        guard let selected = candidates.first else {
            throw AIModelRouteError.noMatchingModel
        }

        return selected
    }

    private func role(for jobType: AIModelJobType) -> AIModelRole {
        switch jobType {
        case .plannerHint:
            return .plannerHint
        case .traceSummary:
            return .traceSummary
        case .recovery:
            return .recovery
        }
    }

    private func allowsRisk(_ risk: AIModelRisk, entry: AIModelRegistryEntry) -> Bool {
        if risk == .high {
            return entry.evalStatus == .passing
        }

        return true
    }

    private func score(
        _ entry: AIModelRegistryEntry,
        request: AIModelRouteRequest
    ) -> Int {
        var value = 0
        if entry.evalStatus == .passing { value += 10 }
        if request.latencyTolerance == .interactive { value -= entry.timeoutMS / 1_000 }
        if request.privacyMode == .privacySensitive,
           entry.provider == .openAI {
            value += 1
        }
        return value
    }
}
