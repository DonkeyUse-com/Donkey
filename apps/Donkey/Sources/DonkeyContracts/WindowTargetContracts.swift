import Foundation

public struct WindowTargetBounds: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var hasPositiveArea: Bool {
        width > 0 && height > 0
    }
}

public enum WindowTargetSafetyStatus: String, Codable, Equatable, Sendable {
    case allowed
    case reviewRequired
    case blocked
}

public enum WindowTargetSafetyReason: String, Codable, Equatable, Sendable {
    case systemSurface
    case loginSurface
    case passwordSurface
    case paymentSurface
    case permissionSurface
    case unknownSurface
}

public struct WindowTargetSafetyAssessment: Codable, Equatable, Sendable {
    public var status: WindowTargetSafetyStatus
    public var reasons: [WindowTargetSafetyReason]
    public var summary: String

    public init(
        status: WindowTargetSafetyStatus,
        reasons: [WindowTargetSafetyReason] = [],
        summary: String
    ) {
        self.status = status
        self.reasons = reasons
        self.summary = summary
    }
}

public struct MacWindowTargetCandidate: Codable, Equatable, Sendable {
    public var windowID: UInt32
    public var processID: Int32
    public var appName: String?
    public var bundleIdentifier: String?
    public var title: String?
    public var bounds: WindowTargetBounds
    public var isVisible: Bool
    public var isOnScreen: Bool
    public var isFrontmost: Bool
    public var isFocused: Bool
    public var isIPhoneMirroring: Bool
    public var safetyAssessment: WindowTargetSafetyAssessment

    public init(
        windowID: UInt32,
        processID: Int32,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        title: String? = nil,
        bounds: WindowTargetBounds,
        isVisible: Bool,
        isOnScreen: Bool,
        isFrontmost: Bool,
        isFocused: Bool,
        isIPhoneMirroring: Bool,
        safetyAssessment: WindowTargetSafetyAssessment
    ) {
        self.windowID = windowID
        self.processID = processID
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.bounds = bounds
        self.isVisible = isVisible
        self.isOnScreen = isOnScreen
        self.isFrontmost = isFrontmost
        self.isFocused = isFocused
        self.isIPhoneMirroring = isIPhoneMirroring
        self.safetyAssessment = safetyAssessment
    }
}

public struct MacWindowSelectionRequest: Codable, Equatable, Sendable {
    public var windowID: UInt32?

    public init(windowID: UInt32? = nil) {
        self.windowID = windowID
    }
}

public struct LabeledMacWindowTargetCandidate: Codable, Equatable, Sendable {
    public var label: String
    public var candidate: MacWindowTargetCandidate

    public init(
        label: String,
        candidate: MacWindowTargetCandidate
    ) {
        self.label = label
        self.candidate = candidate
    }
}

public struct MacWindowCandidateListSnapshot: Codable, Equatable, Sendable {
    public var candidates: [LabeledMacWindowTargetCandidate]

    public init(candidates: [MacWindowTargetCandidate]) {
        self.candidates = candidates.enumerated().map { index, candidate in
            LabeledMacWindowTargetCandidate(
                label: "window \(index + 1)",
                candidate: candidate
            )
        }
    }

    public init(labeledCandidates: [LabeledMacWindowTargetCandidate]) {
        self.candidates = labeledCandidates
    }

    public func selectionRequest(
        forLabel label: String
    ) -> MacWindowSelectionRequest? {
        guard let candidate = candidates.first(where: { $0.label == label })?.candidate else {
            return nil
        }

        return MacWindowSelectionRequest(windowID: candidate.windowID)
    }
}
