@preconcurrency import ApplicationServices
import DonkeyContracts
import Foundation

/// A resolved live accessibility observation of one app window: the window target and its controls.
struct ResolvedAccessibilityObservation {
    var target: MacWindowTargetCandidate
    var controls: [LocalAppDiscoveredControl]
}

/// Captures a running app's accessibility tree and discovers its controls. Shared by the guidance
/// overlay and the accessibility action executor so both ground against the same observation.
@MainActor
public enum AccessibilityObserver {
    static func observe(
        appName: String?,
        bundleIdentifier: String?,
        resolver: MacWindowResolver = MacWindowResolver()
    ) -> ResolvedAccessibilityObservation? {
        guard AXIsProcessTrusted(),
              let target = resolveTarget(appName: appName, bundleIdentifier: bundleIdentifier, resolver: resolver)
        else {
            return nil
        }
        let limits = MacAccessibilitySnapshotLimits(maxDepth: 8, maxChildrenPerNode: 120, maxTotalNodes: 1_200)
        guard let tree = try? ApplicationServicesMacAccessibilitySnapshotCapturer().captureTree(
            target: target,
            limits: limits
        ) else {
            return nil
        }
        let snapshot = MacAccessibilitySnapshot(
            target: target,
            limits: limits,
            root: tree.root,
            totalNodeCount: tree.totalNodeCount,
            isTreeTruncated: tree.isTreeTruncated
        )
        let index = LocalAppAccessibilityControlDiscovery().discover(in: snapshot)
        return ResolvedAccessibilityObservation(target: target, controls: index.controls)
    }

    public static func resolveTarget(
        appName: String?,
        bundleIdentifier: String?,
        resolver: MacWindowResolver = MacWindowResolver()
    ) -> MacWindowTargetCandidate? {
        if appName != nil || bundleIdentifier != nil {
            let candidates = resolver.enumerateCandidates()
            if let match = candidates.first(where: { candidate in
                if let bundleIdentifier, let candidateBundle = candidate.bundleIdentifier {
                    return candidateBundle.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
                }
                if let appName, let candidateApp = candidate.appName {
                    return candidateApp.localizedCaseInsensitiveContains(appName)
                        || appName.localizedCaseInsensitiveContains(candidateApp)
                }
                return false
            }) {
                return match
            }
        }
        return try? resolver.selectTarget()
    }
}
