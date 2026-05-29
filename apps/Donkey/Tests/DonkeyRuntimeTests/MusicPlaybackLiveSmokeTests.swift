import AppKit
@testable import Donkey
import DonkeyContracts
import DonkeyRuntime
import DonkeyUI
import Foundation
import Testing

/// Live, end-to-end smoke test for playing music through the real Donkey agent harness.
///
/// This intentionally does almost nothing itself: it hands the raw query to the production
/// `LocalAppUserQueryCommandHandler`, which does ALL of the work — parse intent against the real
/// hosted backend, plan the task, execute it through the harness runtime (launching the resolved
/// media app and playing the track), and derive the cursor-path visualization from the actual run.
/// The test only requests Accessibility (so the harness can drive the app) and presents the
/// harness-produced cursor overlay so the pointer is visible.
///
/// Because it makes real network calls and can launch a media app, it is gated behind
/// `DONKEY_LIVE_SMOKE=1` and no-ops in normal `swift test` runs. To run it live:
///
///     env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
///       DONKEY_LIVE_SMOKE=1 DONKEY_WEB_BASE_URL=http://localhost:3000 DONKEY_DEV_AUTH_BYPASS=1 \
///       swift test --filter MusicPlaybackLiveSmokeTests
@Suite
struct MusicPlaybackLiveSmokeTests {
    private static let query = "play some cold play"

    @Test
    @MainActor
    func playsColdplayThroughRealHarnessAndVisualizesPointerPath() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DONKEY_LIVE_SMOKE"] == "1" else {
            // Skipped by default: this is a live smoke test, not a CI unit test.
            return
        }
        if environment["DONKEY_WEB_BASE_URL"]?.isEmpty != false {
            Issue.record("DONKEY_LIVE_SMOKE=1 but DONKEY_WEB_BASE_URL is not set; cannot reach a backend.")
            return
        }

        // Request Accessibility via the app's real requester so the harness can drive the media app
        // (the planned UI-control steps need it). Shows the system prompt / opens System Settings.
        _ = await SystemMacPermissionRequester().request(.accessibility)

        // Hand the raw query to the real handler. It parses, plans, executes (plays the music), and
        // builds the agent-visualization plan from the run — nothing is hand-authored here. The
        // music-media skill is responsible for picking a representative song for a vague request
        // and acting directly (no clarification gate), so this should run to completion.
        let handler = LocalAppUserQueryCommandHandler()
        let result = await handler.handleSubmittedCommand(Self.query)

        // The harness should have routed this to a local app task and completed it.
        #expect(result.decision.kind == .runLocalTask)
        if result.status != .completed {
            Issue.record("Harness run did not complete: status=\(result.status) summary=\(result.summary) metadata=\(result.metadata)")
        }

        // Present the harness-derived cursor path so the pointer is visible during playback.
        let cursorRequest = try #require(
            result.cursorOverlayRequest,
            "Harness produced no cursor overlay request for the run (no grounded agent path)."
        )
        if NSApplication.shared.activationPolicy() == .prohibited {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        let overlay = PointerCoachCursorOverlayController()
        overlay.show(request: cursorRequest)
        let overlayDuration = cursorRequest.steps.reduce(1.0) { $0 + $1.travelDuration + $1.holdDuration }
        Self.pumpMainRunLoop(forSeconds: overlayDuration)
    }

    /// Runs the main run loop for `seconds` so the AppKit overlay panel renders/animates. Lives in
    /// a synchronous method because `RunLoop.run(until:)` is unavailable directly in async contexts.
    @MainActor
    private static func pumpMainRunLoop(forSeconds seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
