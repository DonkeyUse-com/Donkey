import Foundation

public enum PlannerHintValidationIssue: String, Codable, Equatable, Sendable {
    case unknownAction
    case unsafeAction
    case staleStateReference
    case lowConfidenceReplacement
    case expired
}

public struct StructuredPlannerHint: Codable, Equatable, Sendable {
    public var id: String
    public var goal: String
    public var policyName: String
    public var priorities: [String]
    public var regionsOfInterest: [HotLoopRect]
    public var preferredActions: [HotLoopActionKind]
    public var avoidActions: [HotLoopActionKind]
    public var confidence: Double
    public var createdAt: RunTraceTimestamp
    public var expiresAt: RunTraceTimestamp
    public var sourceTraceID: String
    public var sourceFrameID: String?
    public var sourceStateID: String?
    public var sourceModelCallID: String?
    public var replacesHintID: String?
    public var metadata: [String: String]

    public init(
        id: String,
        goal: String,
        policyName: String,
        priorities: [String] = [],
        regionsOfInterest: [HotLoopRect] = [],
        preferredActions: [HotLoopActionKind] = [],
        avoidActions: [HotLoopActionKind] = [],
        confidence: Double,
        createdAt: RunTraceTimestamp,
        expiresAt: RunTraceTimestamp,
        sourceTraceID: String,
        sourceFrameID: String? = nil,
        sourceStateID: String? = nil,
        sourceModelCallID: String? = nil,
        replacesHintID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.goal = goal
        self.policyName = policyName
        self.priorities = priorities
        self.regionsOfInterest = regionsOfInterest
        self.preferredActions = preferredActions
        self.avoidActions = avoidActions
        self.confidence = confidence
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.sourceTraceID = sourceTraceID
        self.sourceFrameID = sourceFrameID
        self.sourceStateID = sourceStateID
        self.sourceModelCallID = sourceModelCallID
        self.replacesHintID = replacesHintID
        self.metadata = metadata
    }

    public func isExpired(at timestamp: RunTraceTimestamp) -> Bool {
        expiresAt.milliseconds(until: timestamp) != nil
    }

    public func summaryHint(isValid: Bool = true) -> RunPlannerHint {
        RunPlannerHint(
            id: id,
            summary: "\(policyName): \(goal)",
            isValid: isValid
        )
    }
}

public struct PlannerHintValidationContext: Equatable, Sendable {
    public var currentStateID: String?
    public var allowedActions: Set<HotLoopActionKind>
    public var unsafeActions: Set<HotLoopActionKind>
    public var minimumConfidence: Double
    public var minimumReplacementConfidence: Double
    public var now: RunTraceTimestamp

    public init(
        currentStateID: String? = nil,
        allowedActions: Set<HotLoopActionKind> = Set(HotLoopActionKind.allCases),
        unsafeActions: Set<HotLoopActionKind> = [],
        minimumConfidence: Double = 0.3,
        minimumReplacementConfidence: Double = 0.6,
        now: RunTraceTimestamp
    ) {
        self.currentStateID = currentStateID
        self.allowedActions = allowedActions
        self.unsafeActions = unsafeActions
        self.minimumConfidence = minimumConfidence
        self.minimumReplacementConfidence = minimumReplacementConfidence
        self.now = now
    }
}

public struct PlannerHintValidationResult: Equatable, Sendable {
    public var hint: StructuredPlannerHint
    public var issues: [PlannerHintValidationIssue]

    public init(
        hint: StructuredPlannerHint,
        issues: [PlannerHintValidationIssue] = []
    ) {
        self.hint = hint
        self.issues = issues
    }

    public var isValid: Bool {
        issues.isEmpty
    }
}

public enum PlannerHintValidator {
    public static func validate(
        _ hint: StructuredPlannerHint,
        context: PlannerHintValidationContext
    ) -> PlannerHintValidationResult {
        let actions = Set(hint.preferredActions + hint.avoidActions)
        var issues: [PlannerHintValidationIssue] = []

        if !actions.isSubset(of: context.allowedActions) {
            issues.append(.unknownAction)
        }

        if !actions.intersection(context.unsafeActions).isEmpty {
            issues.append(.unsafeAction)
        }

        if let currentStateID = context.currentStateID,
           let sourceStateID = hint.sourceStateID,
           sourceStateID != currentStateID {
            issues.append(.staleStateReference)
        }

        if hint.confidence < context.minimumConfidence {
            issues.append(.lowConfidenceReplacement)
        }

        if hint.replacesHintID != nil,
           hint.confidence < context.minimumReplacementConfidence {
            issues.append(.lowConfidenceReplacement)
        }

        if hint.isExpired(at: context.now) {
            issues.append(.expired)
        }

        return PlannerHintValidationResult(
            hint: hint,
            issues: Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
        )
    }
}

public struct PlannerHintSelection: Equatable, Sendable {
    public var latestValidHint: StructuredPlannerHint?
    public var validationResults: [PlannerHintValidationResult]

    public init(
        latestValidHint: StructuredPlannerHint?,
        validationResults: [PlannerHintValidationResult]
    ) {
        self.latestValidHint = latestValidHint
        self.validationResults = validationResults
    }
}

public enum PlannerHintSelector {
    public static func latestValidHint(
        from hints: [StructuredPlannerHint],
        context: PlannerHintValidationContext
    ) -> PlannerHintSelection {
        let results = hints.map { PlannerHintValidator.validate($0, context: context) }
        let latest = results
            .filter(\.isValid)
            .map(\.hint)
            .sorted {
                $0.createdAt.monotonicUptimeNanoseconds > $1.createdAt.monotonicUptimeNanoseconds
            }
            .first

        return PlannerHintSelection(
            latestValidHint: latest,
            validationResults: results
        )
    }
}
