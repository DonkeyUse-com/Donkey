import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct GuardedLiveActionSmokeTests {
    @Test
    func localNavigationLiveSmokeRequiresDryRunReportPolicyAndFocusGuard() async {
        let dryRunCoordinator = RunCoordinator()
        let dryRunSession = RunSession(
            id: "dry-run-session",
            userGoal: "focus Code",
            targetID: "local-navigation"
        )
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
                traceID: "trace-local-nav-smoke",
                requestedBundleIdentifier: "com.microsoft.VSCode"
            )
        )
        let dryRunLoop = DryRunReflexLoop(
            coordinator: dryRunCoordinator,
            frameSource: source,
            perceptionAdapter: LocalNavigationDryRunPerceptionAdapter(),
            worldStateProjector: LocalNavigationDryRunWorldStateProjector(),
            controllerPolicy: LocalNavigationDryRunControllerPolicy()
        )

        let dryRunResult = await dryRunLoop.run(session: dryRunSession)
        let report = await ReflexLatencyReportBuilder.build(
            from: dryRunCoordinator.reflexTraces(),
            droppedFrameCount: dryRunResult.droppedFrameCount
        )

        #expect(dryRunSession.permissionPolicy.decision(for: .input).isAllowed == false)
        #expect(report.traceCount == 1)
        #expect(report.softwareLoopMS.p95 != nil)
        #expect(dryRunResult.latestAction?.kind == .focusWindow)

        let backend = RecordingSmokeInputBackend()
        let runner = GuardedLiveActionSmokeRunner(
            actionEngine: ActionEngineGuardrail(
                configuration: ActionEngineConfiguration(liveInputEnabled: true),
                focusGuard: AllowingFocusGuard(),
                inputBackend: backend
            )
        )
        let liveSession = RunSession(
            id: "live-smoke-session",
            userGoal: "focus Code",
            targetID: "local-navigation",
            permissionPolicy: ToolCallPolicy(deniedCapabilities: [])
        )

        let smoke = await runner.run(
            dryRunResult: dryRunResult,
            latencyReport: report,
            session: liveSession,
            issuedAt: timestamp(100)
        )

        #expect(smoke.status == .executed)
        #expect(smoke.commandTrace?.decision == .executedLive)
        #expect(smoke.commandTrace?.executed == true)
        #expect(smoke.commandTrace?.focusGuardPassed == true)
        #expect(smoke.commandTrace?.command.kind == .tap)
        #expect(smoke.commandTrace?.command.metadata["sourceActionKind"] == "focusWindow")
        #expect(await backend.executedCommandIDs() == ["live-smoke-action-local-nav-state-trace-local-nav-smoke"])
    }

    @Test
    func liveSmokeIsDeniedWithoutExplicitInputPolicy() async {
        let state = worldState()
        let action = action(state: state)
        let result = DryRunReflexLoopResult(
            processedFrameCount: 1,
            droppedFrameCount: 0,
            latestWorldState: state,
            latestAction: action
        )
        let report = reportForDryRun()
        let backend = RecordingSmokeInputBackend()
        let runner = GuardedLiveActionSmokeRunner(
            actionEngine: ActionEngineGuardrail(
                configuration: ActionEngineConfiguration(liveInputEnabled: true),
                inputBackend: backend
            )
        )

        let smoke = await runner.run(
            dryRunResult: result,
            latencyReport: report,
            session: RunSession(id: "session-denied", userGoal: "focus", targetID: "target-1"),
            issuedAt: timestamp(100)
        )

        #expect(smoke.status == .denied)
        #expect(smoke.commandTrace?.decision == .denied(reason: "input permission denied"))
        #expect(await backend.executedCommandIDs().isEmpty)
    }

    @Test
    func liveSmokeIsDeniedWhenFocusGuardFailsAndReleasesHeldInputOnAbort() async {
        let state = worldState()
        let action = action(state: state)
        let engine = ActionEngineGuardrail(
            configuration: ActionEngineConfiguration(liveInputEnabled: true),
            focusGuard: DenyingSmokeFocusGuard(),
            inputBackend: RecordingSmokeInputBackend()
        )
        let runner = GuardedLiveActionSmokeRunner(actionEngine: engine)
        let liveSession = RunSession(
            id: "session-focus-denied",
            userGoal: "focus",
            targetID: "target-1",
            permissionPolicy: ToolCallPolicy(deniedCapabilities: [])
        )

        let smoke = await runner.run(
            dryRunResult: DryRunReflexLoopResult(
                processedFrameCount: 1,
                droppedFrameCount: 0,
                latestWorldState: state,
                latestAction: action
            ),
            latencyReport: reportForDryRun(),
            session: liveSession,
            issuedAt: timestamp(100)
        )
        #expect(smoke.status == .denied)
        #expect(smoke.commandTrace?.decision == .denied(reason: "focus guard failed"))

        let holdingEngine = ActionEngineGuardrail(
            configuration: ActionEngineConfiguration(liveInputEnabled: true),
            inputBackend: RecordingSmokeInputBackend()
        )
        _ = await holdingEngine.handle(
            ActionEngineCommand(
                id: "hold-1",
                traceID: "trace-1",
                targetID: "target-1",
                kind: .key,
                issuedAt: timestamp(110),
                key: "Command",
                holdDurationMS: 50
            ),
            permissionPolicy: ToolCallPolicy(deniedCapabilities: [])
        )
        #expect(await holdingEngine.heldInputCount() == 1)

        let release = await holdingEngine.releaseAll(
            traceID: "trace-1",
            targetID: "target-1",
            issuedAt: timestamp(120)
        )

        #expect(release.releaseAll == true)
        #expect(release.metadata["heldInputReleased"] == "true")
        #expect(await holdingEngine.heldInputCount() == 0)
    }

    private func worldState() -> HotLoopWorldState {
        HotLoopWorldState(
            id: "state-1",
            traceID: "trace-1",
            frameID: "frame-1",
            targetID: "target-1",
            observedAt: timestamp(10),
            signalSummaries: [
                HotLoopPerceptionSignalSummary(
                    id: "signal-1",
                    kind: "localNavigationMetadata",
                    confidence: 0.9,
                    observationCount: 1
                )
            ],
            actionAffordances: [],
            confidence: 0.9
        )
    }

    private func action(state: HotLoopWorldState) -> HotLoopControllerAction {
        HotLoopControllerAction(
            id: "action-1",
            traceID: state.traceID,
            frameID: state.frameID,
            stateID: state.id,
            kind: .focusWindow,
            target: HotLoopRect(x: 10, y: 20, width: 300, height: 200, space: .screen),
            policyName: "local-navigation-controller-v1",
            confidence: 0.9,
            rationale: "focus target",
            metadata: ["fallback": "false"]
        )
    }

    private func reportForDryRun() -> ReflexLatencyReport {
        ReflexLatencyReport(
            mode: .endToEndDryRun,
            traceCount: 1,
            softwareLoopMS: ReflexLatencyPercentiles(p50: 4, p95: 4, p99: 4),
            captureMS: ReflexLatencyPercentiles(p50: 0, p95: 0, p99: 0),
            perceptionMS: ReflexLatencyPercentiles(p50: 1, p95: 1, p99: 1),
            decisionMS: ReflexLatencyPercentiles(p50: 1, p95: 1, p99: 1),
            inputMS: ReflexLatencyPercentiles(p50: 0, p95: 0, p99: 0)
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

private struct AllowingFocusGuard: ActionEngineFocusGuard {
    func targetIsSafeForInput(targetID: String) async -> Bool {
        true
    }
}

private struct DenyingSmokeFocusGuard: ActionEngineFocusGuard {
    func targetIsSafeForInput(targetID: String) async -> Bool {
        false
    }
}

private actor RecordingSmokeInputBackend: ActionEngineInputBackend {
    private var commandIDs: [String] = []

    func execute(_ command: ActionEngineCommand) async -> ActionEngineInputBackendResult {
        commandIDs.append(command.id)
        return ActionEngineInputBackendResult(
            executed: true,
            completedAt: command.issuedAt,
            metadata: ["liveInputBackend": "recording-smoke"]
        )
    }

    func executedCommandIDs() -> [String] {
        commandIDs
    }
}
