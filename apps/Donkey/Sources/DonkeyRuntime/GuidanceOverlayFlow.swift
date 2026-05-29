@preconcurrency import ApplicationServices
import DonkeyContracts
import Foundation

/// Produces an accessibility-grounded cursor overlay for a guidance request ("show me where X is").
///
/// Visualization-only: it captures the target app's accessibility tree, grounds the requested
/// controls to a cursor path, and returns an overlay request. It never performs input
/// (`realPointerMoved` stays false). Because it relies only on the accessibility tree, it works on
/// any app that exposes one — native or Electron (Chromium) — which is exactly the case where
/// AppleScript cannot help.
@MainActor
public enum GuidanceOverlayFlow {
    public struct Outcome: Sendable {
        public var request: PointerCoachCursorGuideRequest?
        public var reason: String
        public var resolvedAppName: String?

        public init(request: PointerCoachCursorGuideRequest?, reason: String, resolvedAppName: String?) {
            self.request = request
            self.reason = reason
            self.resolvedAppName = resolvedAppName
        }
    }

    public static func cursorGuide(
        appName: String?,
        bundleIdentifier: String?,
        targets: [AccessibilityCursorPathTarget],
        title: String,
        traceID: String,
        windowResolver: MacWindowResolver = MacWindowResolver()
    ) -> Outcome {
        guard AXIsProcessTrusted() else {
            return Outcome(request: nil, reason: "accessibilityNotTrusted", resolvedAppName: nil)
        }
        guard !targets.isEmpty else {
            return Outcome(request: nil, reason: "noTargets", resolvedAppName: nil)
        }
        guard let observation = AccessibilityObserver.observe(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            resolver: windowResolver
        ) else {
            return Outcome(request: nil, reason: "accessibilityObservationUnavailable", resolvedAppName: nil)
        }
        let target = observation.target
        let steps = AccessibilityCursorPathBuilder.buildSteps(
            targetApp: target.appName ?? appName ?? "",
            windowBounds: target.bounds,
            controls: observation.controls,
            targets: targets,
            phaseID: "guidance"
        )
        guard !steps.isEmpty else {
            return Outcome(request: nil, reason: "noGroundedTargets", resolvedAppName: target.appName)
        }
        let trace = AgentPathTrace(
            taskID: traceID,
            title: title,
            sourceTraceID: traceID,
            steps: steps,
            metadata: ["mode": "guidance", "realPointerMoved": "false"]
        )
        guard let request = trace.visualizationPlan()?.cursorOverlayRequest() else {
            return Outcome(request: nil, reason: "noOverlayRequest", resolvedAppName: target.appName)
        }
        return Outcome(request: request, reason: "ok", resolvedAppName: target.appName)
    }
}
