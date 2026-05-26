import DonkeyContracts
import Foundation

public enum LocalUIElementCandidateSource: String, Codable, CaseIterable, Equatable, Sendable {
    case accessibility
    case shape
    case ocr
    case template
    case color
    case connectedComponent
    case hoverProbe
    case layout
}

public enum LocalUIElementSignalKind: String, Codable, CaseIterable, Equatable, Sendable {
    case accessibilityRole
    case rectangle
    case roundedRectangle
    case text
    case iconTemplate
    case colorCluster
    case connectedComponent
    case hoverHighlight
    case rowGrouping
}

public enum LocalUIElementActionEligibility: String, Codable, Equatable, Sendable {
    case overlayOnly
    case readOnlyEvidence
    case cursorVisualization
    case guardedAction
}

public struct LocalUIElementCandidate: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var source: LocalUIElementCandidateSource
    public var signalKind: LocalUIElementSignalKind
    public var typeHint: DebugUIElementType?
    public var label: String?
    public var role: String?
    public var bounds: HotLoopRect
    public var confidence: Double
    public var actions: [String]
    public var metadata: [String: String]

    public init(
        id: String,
        source: LocalUIElementCandidateSource,
        signalKind: LocalUIElementSignalKind,
        typeHint: DebugUIElementType? = nil,
        label: String? = nil,
        role: String? = nil,
        bounds: HotLoopRect,
        confidence: Double,
        actions: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.signalKind = signalKind
        self.typeHint = typeHint
        self.label = label
        self.role = role
        self.bounds = bounds
        self.confidence = min(max(confidence, 0), 1)
        self.actions = actions
        self.metadata = metadata
    }
}

public struct LocalUIElementSuppressedCandidate: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var candidate: LocalUIElementCandidate
    public var reason: String
    public var mergedIntoElementID: String?

    public init(
        candidate: LocalUIElementCandidate,
        reason: String,
        mergedIntoElementID: String? = nil
    ) {
        self.id = "\(candidate.id)-suppressed-\(reason)"
        self.candidate = candidate
        self.reason = reason
        self.mergedIntoElementID = mergedIntoElementID
    }
}

public struct LocalUIElement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var type: DebugUIElementType
    public var label: String
    public var bounds: HotLoopRect
    public var confidence: Double
    public var sources: [LocalUIElementCandidateSource]
    public var reasonCodes: [String]
    public var actionEligibility: LocalUIElementActionEligibility
    public var sourceCandidateIDs: [String]
    public var metadata: [String: String]

    public init(
        id: String,
        type: DebugUIElementType,
        label: String,
        bounds: HotLoopRect,
        confidence: Double,
        sources: [LocalUIElementCandidateSource],
        reasonCodes: [String],
        actionEligibility: LocalUIElementActionEligibility,
        sourceCandidateIDs: [String],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.bounds = bounds
        self.confidence = min(max(confidence, 0), 1)
        self.sources = Array(Set(sources)).sorted { $0.rawValue < $1.rawValue }
        self.reasonCodes = Array(Set(reasonCodes)).sorted()
        self.actionEligibility = actionEligibility
        self.sourceCandidateIDs = sourceCandidateIDs
        self.metadata = metadata
    }

    public var isGuardedActionEligible: Bool {
        actionEligibility == .guardedAction
    }
}

public struct LocalUIElementDetectionMetrics: Codable, Equatable, Sendable {
    public var sourceCounts: [String: Int]
    public var candidateCount: Int
    public var elementCount: Int
    public var suppressedCount: Int
    public var duplicateCount: Int
    public var cvOnlyElementCount: Int
    public var minConfidence: Double
    public var latencyMS: [String: Double]

    public init(
        sourceCounts: [String: Int] = [:],
        candidateCount: Int = 0,
        elementCount: Int = 0,
        suppressedCount: Int = 0,
        duplicateCount: Int = 0,
        cvOnlyElementCount: Int = 0,
        minConfidence: Double = 0,
        latencyMS: [String: Double] = [:]
    ) {
        self.sourceCounts = sourceCounts
        self.candidateCount = candidateCount
        self.elementCount = elementCount
        self.suppressedCount = suppressedCount
        self.duplicateCount = duplicateCount
        self.cvOnlyElementCount = cvOnlyElementCount
        self.minConfidence = min(max(minConfidence, 0), 1)
        self.latencyMS = latencyMS
    }
}

public struct LocalUIElementDetectionTrace: Codable, Equatable, Sendable {
    public var traceID: String
    public var candidates: [LocalUIElementCandidate]
    public var elements: [LocalUIElement]
    public var suppressedCandidates: [LocalUIElementSuppressedCandidate]
    public var metrics: LocalUIElementDetectionMetrics
    public var metadata: [String: String]

    public init(
        traceID: String,
        candidates: [LocalUIElementCandidate],
        elements: [LocalUIElement],
        suppressedCandidates: [LocalUIElementSuppressedCandidate],
        metrics: LocalUIElementDetectionMetrics,
        metadata: [String: String] = [:]
    ) {
        self.traceID = traceID
        self.candidates = candidates
        self.elements = elements
        self.suppressedCandidates = suppressedCandidates
        self.metrics = metrics
        self.metadata = metadata
    }
}

public struct LocalUIElementDetectionRequest: Equatable, Sendable {
    public var traceID: String
    public var screenshotPNGData: Data?
    public var pixelSize: HotLoopSize
    public var accessibilityCandidates: [LocalUIElementCandidate]
    public var hoverProbeCandidates: [LocalUIElementCandidate]
    public var minConfidence: Double
    public var metadata: [String: String]

    public init(
        traceID: String,
        screenshotPNGData: Data? = nil,
        pixelSize: HotLoopSize,
        accessibilityCandidates: [LocalUIElementCandidate] = [],
        hoverProbeCandidates: [LocalUIElementCandidate] = [],
        minConfidence: Double = 0.25,
        metadata: [String: String] = [:]
    ) {
        self.traceID = traceID
        self.screenshotPNGData = screenshotPNGData
        self.pixelSize = pixelSize
        self.accessibilityCandidates = accessibilityCandidates
        self.hoverProbeCandidates = hoverProbeCandidates
        self.minConfidence = min(max(minConfidence, 0), 1)
        self.metadata = metadata
    }
}

public protocol LocalUIElementDetecting: Sendable {
    func detect(_ request: LocalUIElementDetectionRequest) -> LocalUIElementDetectionTrace
}
