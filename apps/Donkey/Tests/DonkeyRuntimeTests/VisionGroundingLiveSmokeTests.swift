import AppKit
import DonkeyAI
import DonkeyContracts
import DonkeyRuntime
import Foundation
import Testing

/// Live, env-gated test that hosted VISION can ground a control AX can't (e.g. Spotify's search
/// box). Captures the app window, sends it to the hosted UI-inspection model, and maps the located
/// element to a screen point.
///
///     env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
///       DONKEY_LIVE_SMOKE=1 DONKEY_WEB_BASE_URL=http://localhost:3000 DONKEY_DEV_AUTH_BYPASS=1 \
///       [DONKEY_GUIDE_APP=Spotify] [DONKEY_GUIDE_TARGET=Search] \
///       swift test --filter VisionGroundingLiveSmokeTests
@Suite
struct VisionGroundingLiveSmokeTests {
    @Test
    @MainActor
    func hostedVisionLocatesAControl() async {
        let env = ProcessInfo.processInfo.environment
        guard env["DONKEY_LIVE_SMOKE"] == "1" else { return }
        guard env["DONKEY_WEB_BASE_URL"]?.isEmpty == false else {
            Issue.record("DONKEY_WEB_BASE_URL not set")
            return
        }
        guard let config = try? DonkeyBackendInferenceConfiguration.fromEnvironment() else {
            Issue.record("could not load backend configuration")
            return
        }

        let app = env["DONKEY_GUIDE_APP"] ?? "Spotify"
        let target = env["DONKEY_GUIDE_TARGET"] ?? "Search"
        NSWorkspace.shared.launchApplication(app)
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let analyzer = HostedDebugUIInspectionAnalyzer(
            backend: DonkeyBackendInferenceClient(configuration: config, httpClient: URLSessionAIHTTPClient())
        )
        let outcome = await VisionGroundingFlow.locate(
            appName: app,
            bundleIdentifier: nil,
            targetQuery: target,
            analyzer: analyzer
        )

        guard let point = outcome.screenPoint else {
            Issue.record("Hosted vision did not locate '\(target)' in \(app): reason=\(outcome.reason) app=\(outcome.resolvedAppName ?? "nil"). Needs Screen Recording permission + a reachable backend.")
            return
        }
        #expect(point.x > 0 && point.y > 0)
        #expect(outcome.matchedLabel != nil)
    }
}
