import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct LocalNavigationControllerTests {
    @Test
    func metadataProjectorBuildsTypedLocalNavigationWorldState() {
        let projector = LocalNavigationMetadataProjector()

        let state = projector.project(
            snapshot: MacWindowCandidateListSnapshot(candidates: [
                window(
                    id: 100,
                    appName: "Code",
                    bundleIdentifier: "com.microsoft.VSCode",
                    title: "Donkey",
                    isFrontmost: false,
                    isFocused: false
                ),
                window(
                    id: 200,
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    title: "Docs",
                    isFrontmost: true,
                    isFocused: true
                )
            ]),
            traceID: "trace-nav",
            targetID: "local-navigation",
            observedAt: timestamp(20),
            sourceCapturedAt: timestamp(10),
            requestedBundleIdentifier: "com.microsoft.VSCode"
        )

        #expect(state.candidates.map(\.id) == ["window-100", "window-200"])
        #expect(state.focusedCandidateID == "window-200")
        #expect(state.frontmostCandidateID == "window-200")
        #expect(state.requestedBundleIdentifier == "com.microsoft.VSCode")
        #expect(state.hotLoopWorldState().actionAffordances.count == 2)
        #expect(state.hotLoopWorldState().metadata["localNavigation.candidateCount"] == "2")
    }

    @Test
    func metadataProjectorIncludesBrowserTabsWhenAvailable() {
        let state = LocalNavigationMetadataProjector().project(
            snapshot: MacWindowCandidateListSnapshot(candidates: [
                window(
                    id: 200,
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    title: "Docs Window",
                    isFrontmost: true,
                    isFocused: true
                )
            ]),
            traceID: "trace-tabs",
            targetID: "local-navigation",
            observedAt: timestamp(20),
            sourceCapturedAt: timestamp(10),
            requestedTitleContains: "Install",
            browserTabs: [
                LocalNavigationBrowserTabMetadata(
                    id: "safari-tab-1",
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    title: "Install Guide",
                    url: "https://example.test/install",
                    windowID: 200,
                    isActive: false,
                    isFrontmost: true,
                    confidence: 0.9
                )
            ]
        )

        #expect(state.candidates.map(\.kind) == [.window, .browserTab])
        #expect(state.metadata["browserTabMetadataAvailable"] == "true")
        #expect(state.metadata["browserTabCandidateCount"] == "1")
        #expect(state.hotLoopWorldState().actionAffordances.last?.kind == .switchTab)
        #expect(state.hotLoopWorldState().actionAffordances.last?.metadata["browserTabID"] == "safari-tab-1")
    }

    @Test
    func controllerSelectsRequestedWindowFocusAction() {
        let state = navigationState(
            requestedBundleIdentifier: "com.microsoft.VSCode",
            windows: [
                window(
                    id: 100,
                    appName: "Code",
                    bundleIdentifier: "com.microsoft.VSCode",
                    title: "Donkey",
                    isFrontmost: false,
                    isFocused: false
                ),
                window(
                    id: 200,
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    title: "Docs",
                    isFrontmost: true,
                    isFocused: true
                )
            ]
        )

        let action = LocalNavigationControllerPolicy().decide(state: state)

        #expect(action.kind == .focusWindow)
        #expect(action.metadata["candidateID"] == "window-100")
        #expect(action.metadata["bundleIdentifier"] == "com.microsoft.VSCode")
        #expect(action.metadata["fallback"] == "false")
    }

    @Test
    func controllerFallsBackWhenRequestedTargetIsAlreadyFocusedOrMissing() {
        let alreadyFocused = navigationState(
            requestedBundleIdentifier: "com.apple.Safari",
            windows: [
                window(
                    id: 200,
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    title: "Docs",
                    isFrontmost: true,
                    isFocused: true
                )
            ]
        )
        let wait = LocalNavigationControllerPolicy().decide(state: alreadyFocused)
        #expect(wait.kind == .wait)
        #expect(wait.metadata["fallbackReason"] == "alreadyFocused")

        let missing = navigationState(
            requestedBundleIdentifier: "com.apple.Terminal",
            windows: [
                window(
                    id: 200,
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    title: "Docs",
                    isFrontmost: true,
                    isFocused: true
                )
            ]
        )
        let observe = LocalNavigationControllerPolicy().decide(state: missing)
        #expect(observe.kind == .observe)
        #expect(observe.metadata["fallbackReason"] == "targetNotFound")
    }

    @Test
    func blockedWindowsAreNotSelectedForNavigation() {
        let state = navigationState(
            requestedBundleIdentifier: "com.apple.systempreferences",
            windows: [
                window(
                    id: 300,
                    appName: "System Settings",
                    bundleIdentifier: "com.apple.systempreferences",
                    title: "Passwords",
                    isFrontmost: false,
                    isFocused: false,
                    safetyStatus: .blocked
                )
            ]
        )

        let action = LocalNavigationControllerPolicy().decide(state: state)

        #expect(action.kind == .observe)
        #expect(action.metadata["fallbackReason"] == "targetNotFound")
    }

    @Test
    func dryRunLoopUsesLocalNavigationMetadataProjectionAndController() async {
        let coordinator = RunCoordinator()
        let source = LocalNavigationMetadataFrameSource(
            windowResolver: MacWindowResolver(
                provider: FixtureWindowProvider(
                    windows: [
                        providerWindow(
                            windowID: 100,
                            processID: 1000,
                            appName: "Code",
                            bundleIdentifier: "com.microsoft.VSCode",
                            title: "Donkey"
                        ),
                        providerWindow(
                            windowID: 200,
                            processID: 2000,
                            appName: "Safari",
                            bundleIdentifier: "com.apple.Safari",
                            title: "Docs"
                        )
                    ],
                    frontmostProcessID: 2000,
                    focusedWindowID: 200
                )
            ),
            timestampProvider: FixtureTimestampProvider(),
            request: LocalNavigationMetadataFrameRequest(
                traceID: "trace-local-nav-loop",
                requestedTitleContains: "Install",
                browserTabs: [
                    LocalNavigationBrowserTabMetadata(
                        id: "tab-install",
                        appName: "Safari",
                        bundleIdentifier: "com.apple.Safari",
                        title: "Install Guide",
                        url: "https://example.test/install",
                        windowID: 200,
                        isActive: false,
                        isFrontmost: true,
                        confidence: 0.95
                    )
                ]
            )
        )
        let loop = DryRunReflexLoop(
            coordinator: coordinator,
            frameSource: source,
            perceptionAdapter: LocalNavigationDryRunPerceptionAdapter(),
            worldStateProjector: LocalNavigationDryRunWorldStateProjector(),
            controllerPolicy: LocalNavigationDryRunControllerPolicy()
        )

        let result = await loop.run(
            session: RunSession(
                id: "session-local-nav-loop",
                userGoal: "switch to install guide tab",
                targetID: "local-navigation"
            )
        )

        #expect(result.processedFrameCount == 1)
        #expect(result.latestWorldState?.metadata["browserTabMetadataAvailable"] == "true")
        #expect(result.latestAction?.kind == .switchTab)
        #expect(result.latestAction?.metadata["candidateKind"] == "browserTab")
        #expect(result.latestAction?.metadata["browserTabID"] == "tab-install")

        let trace = await coordinator.latestReflexTrace()
        #expect(trace?.metadata["latency.metadataReadMS"] == "5.00")
        #expect(trace?.latencyBreakdown.preprocessMS == 0)
        #expect(trace?.latencyBreakdown.modelInferenceMS == 0)
        #expect(trace?.latencyBreakdown.stateUpdateMS == 1)
        #expect(trace?.metadata["action.kind"] == "switchTab")
    }

    private func navigationState(
        requestedBundleIdentifier: String?,
        windows: [MacWindowTargetCandidate]
    ) -> LocalNavigationWorldState {
        LocalNavigationMetadataProjector().project(
            snapshot: MacWindowCandidateListSnapshot(candidates: windows),
            traceID: "trace-nav",
            targetID: "local-navigation",
            observedAt: timestamp(20),
            sourceCapturedAt: timestamp(10),
            requestedBundleIdentifier: requestedBundleIdentifier
        )
    }

    private func window(
        id: UInt32,
        appName: String,
        bundleIdentifier: String,
        title: String,
        isFrontmost: Bool,
        isFocused: Bool,
        safetyStatus: WindowTargetSafetyStatus = .allowed
    ) -> MacWindowTargetCandidate {
        MacWindowTargetCandidate(
            windowID: id,
            processID: Int32(id),
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            bounds: WindowTargetBounds(x: 10, y: 20, width: 300, height: 200),
            isVisible: true,
            isOnScreen: true,
            isFrontmost: isFrontmost,
            isFocused: isFocused,
            isIPhoneMirroring: false,
            safetyAssessment: WindowTargetSafetyAssessment(
                status: safetyStatus,
                reasons: safetyStatus == .blocked ? [.passwordSurface] : [],
                summary: safetyStatus.rawValue
            )
        )
    }

    private func providerWindow(
        windowID: UInt32,
        processID: Int32,
        appName: String,
        bundleIdentifier: String,
        title: String
    ) -> MacWindowProviderWindow {
        MacWindowProviderWindow(
            windowID: windowID,
            processID: processID,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            bounds: WindowTargetBounds(x: 10, y: 20, width: 300, height: 200)
        )
    }

    private func timestamp(_ milliseconds: UInt64) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(milliseconds) / 1_000),
            monotonicUptimeNanoseconds: milliseconds * 1_000_000
        )
    }
}

private final class FixtureTimestampProvider: RunTraceTimestampProviding, @unchecked Sendable {
    private var nextMilliseconds: UInt64 = 0

    func now() -> RunTraceTimestamp {
        let timestamp = RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(nextMilliseconds) / 1_000),
            monotonicUptimeNanoseconds: nextMilliseconds * 1_000_000
        )
        nextMilliseconds += 5
        return timestamp
    }
}

private struct FixtureWindowProvider: MacWindowMetadataProviding {
    var fixtureWindows: [MacWindowProviderWindow]
    var frontmostProcessID: Int32?
    var focusedWindowID: UInt32?

    init(
        windows: [MacWindowProviderWindow],
        frontmostProcessID: Int32? = nil,
        focusedWindowID: UInt32? = nil
    ) {
        self.fixtureWindows = windows
        self.frontmostProcessID = frontmostProcessID
        self.focusedWindowID = focusedWindowID
    }

    func windows() -> [MacWindowProviderWindow] {
        fixtureWindows
    }

    func frontmostProcessIdentifier() -> Int32? {
        frontmostProcessID
    }

    func focusedWindowIdentifier() -> UInt32? {
        focusedWindowID
    }
}
