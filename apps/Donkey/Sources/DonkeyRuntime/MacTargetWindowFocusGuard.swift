import DonkeyContracts
import Foundation

public struct MacTargetWindowFocusGuard: ActionEngineFocusGuard {
    public var targetID: String
    public var windowID: UInt32
    public var processID: Int32?
    public var expectedBundleIdentifier: String?
    public var expectedBounds: WindowTargetBounds?
    public var boundsTolerance: Double
    public var requireFocusedWindow: Bool

    private let windowResolver: MacWindowResolver

    public init(
        targetID: String,
        windowID: UInt32,
        processID: Int32? = nil,
        expectedBundleIdentifier: String? = nil,
        expectedBounds: WindowTargetBounds? = nil,
        boundsTolerance: Double = 2,
        requireFocusedWindow: Bool = true,
        windowResolver: MacWindowResolver = MacWindowResolver()
    ) {
        self.targetID = targetID
        self.windowID = windowID
        self.processID = processID
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.expectedBounds = expectedBounds
        self.boundsTolerance = max(0, boundsTolerance)
        self.requireFocusedWindow = requireFocusedWindow
        self.windowResolver = windowResolver
    }

    init(
        targetID: String,
        target: MacWindowTargetCandidate,
        boundsTolerance: Double = 2,
        requireFocusedWindow: Bool = true,
        windowResolver: MacWindowResolver = MacWindowResolver()
    ) {
        self.init(
            targetID: targetID,
            windowID: target.windowID,
            processID: target.processID,
            expectedBundleIdentifier: target.bundleIdentifier,
            expectedBounds: target.bounds,
            boundsTolerance: boundsTolerance,
            requireFocusedWindow: requireFocusedWindow,
            windowResolver: windowResolver
        )
    }

    public func targetIsSafeForInput(targetID: String) async -> Bool {
        guard targetID == self.targetID else { return false }
        guard let target = windowResolver
            .enumerateCandidates()
            .first(where: { $0.windowID == windowID })
        else {
            return false
        }

        guard target.safetyAssessment.status == .allowed,
              target.isVisible,
              target.isOnScreen
        else {
            return false
        }

        if let processID, target.processID != processID {
            return false
        }

        if let expectedBundleIdentifier,
           target.bundleIdentifier != expectedBundleIdentifier {
            return false
        }

        if requireFocusedWindow, !target.isFocused {
            return false
        }

        if let expectedBounds,
           !target.bounds.matches(expectedBounds, tolerance: boundsTolerance) {
            return false
        }

        return true
    }
}

private extension WindowTargetBounds {
    func matches(_ other: WindowTargetBounds, tolerance: Double) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
