import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct ManualTargetContextCaptureServiceTests {
    @Test
    func happyPathCreatesArtifactsAndPersistsOrderedCoordinatorEvents() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let coordinator = RunCoordinator()
        let screenshotCapturer = FakeWindowScreenshotCapturer()
        let accessibilityCapturer = FakeMacAccessibilitySnapshotCapturer(
            tree: MacAccessibilitySnapshotTreeBuilder.build(
                root: RawMacAccessibilitySnapshotNode(
                    role: "AXWindow",
                    title: "Manual Target",
                    children: [
                        RawMacAccessibilitySnapshotNode(role: "AXButton", title: "OK")
                    ]
                ),
                limits: .default
            )
        )
        let service = makeService(
            store: store,
            coordinator: coordinator,
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Notes", title: "Manual Target")
            ],
            frontmostProcessID: 100,
            screenshotCapturer: screenshotCapturer,
            accessibilityCapturer: accessibilityCapturer
        )

        let result = try await service.capture(
            session: RunSession(id: "run-manual", userGoal: "capture context", targetID: "target-1"),
            traceID: "trace-manual",
            screenshotArtifactID: "screenshot-manual",
            accessibilityArtifactID: "accessibility-manual"
        )

        #expect(result.target.windowID == 10)
        #expect(result.screenshot.artifact.relativePath == "screenshots/screenshot-manual.png")
        guard case .captured(let accessibilityResult) = result.accessibility else {
            Issue.record("Expected Accessibility capture")
            return
        }
        #expect(accessibilityResult.artifact.relativePath == "accessibility/accessibility-manual.json")
        #expect(screenshotCapturer.capturedWindowIDs == [10])
        #expect(accessibilityCapturer.capturedWindowIDs == [10])

        let summary = try await store.summary(runID: "run-manual")
        #expect(summary.artifacts.map(\.kind) == [.screenshot, .accessibilitySnapshot])
        #expect(summary.eventCount == 9)
        #expect(fileExists(root
            .appendingPathComponent("run-manual", isDirectory: true)
            .appendingPathComponent("screenshots/screenshot-manual.png")))
        #expect(fileExists(root
            .appendingPathComponent("run-manual", isDirectory: true)
            .appendingPathComponent("accessibility/accessibility-manual.json")))

        let records = try jsonlRecords(
            from: root
                .appendingPathComponent("run-manual", isDirectory: true)
                .appendingPathComponent("events.jsonl")
        )
        #expect(records.map(\.event.sequence) == Array(1...9))
        #expect(records.map(\.event.stream) == [
            .lifecycle,
            .lifecycle,
            .tool,
            .tool,
            .tool,
            .tool,
            .tool,
            .lifecycle,
            .lifecycle
        ])
        #expect(records.map(\.event.summary) == [
            "Run starting",
            "Run running",
            "Target window resolved",
            "Screenshot capture started",
            "Screenshot artifact persisted",
            "Accessibility snapshot captured",
            "Accessibility artifact persisted",
            "Run stopping",
            "Run completed"
        ])
        #expect(records.allSatisfy { $0.traceID == "trace-manual" })
        #expect(records.allSatisfy { $0.event.traceID == "trace-manual" })
        #expect(toolPayloads(in: records).allSatisfy { $0.capability != .input })
    }

    @Test
    func labeledWindowSelectionUsesDurableWindowIDForBothCaptureServices() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let windows = [
            fixtureWindow(windowID: 11, processID: 100, appName: "Terminal"),
            fixtureWindow(windowID: 22, processID: 200, appName: "Safari")
        ]
        let snapshot = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: windows,
                frontmostProcessID: 100
            )
        )
        .enumerateCandidateList()
        let screenshotCapturer = FakeWindowScreenshotCapturer()
        let accessibilityCapturer = FakeMacAccessibilitySnapshotCapturer()
        let service = makeService(
            store: store,
            coordinator: RunCoordinator(),
            windows: windows,
            frontmostProcessID: 100,
            screenshotCapturer: screenshotCapturer,
            accessibilityCapturer: accessibilityCapturer
        )

        guard let selection = snapshot.selectionRequest(forLabel: "window 2") else {
            Issue.record("Expected window 2 selection")
            return
        }
        let result = try await service.capture(
            session: RunSession(id: "run-labeled-manual", userGoal: "capture context", targetID: "target-1"),
            selection: selection,
            traceID: "trace-labeled-manual",
            screenshotArtifactID: "screenshot-labeled-manual",
            accessibilityArtifactID: "accessibility-labeled-manual"
        )

        #expect(result.target.windowID == 22)
        #expect(screenshotCapturer.capturedWindowIDs == [22])
        #expect(accessibilityCapturer.capturedWindowIDs == [22])
    }

    @Test
    func missingAccessibilityTrustRecordsCoordinatorPartialEventAndNoAXArtifact() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let accessibilityCapturer = FakeMacAccessibilitySnapshotCapturer(trustStatus: .notTrusted)
        let service = makeService(
            store: store,
            coordinator: RunCoordinator(),
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Notes")
            ],
            frontmostProcessID: 100,
            screenshotCapturer: FakeWindowScreenshotCapturer(),
            accessibilityCapturer: accessibilityCapturer
        )

        let result = try await service.capture(
            session: RunSession(id: "run-manual-ax-denied", userGoal: "capture context", targetID: "target-1"),
            traceID: "trace-manual-ax-denied",
            screenshotArtifactID: "screenshot-manual-ax-denied",
            accessibilityArtifactID: "accessibility-manual-ax-denied"
        )

        guard case .permissionDenied = result.accessibility else {
            Issue.record("Expected Accessibility permission denial")
            return
        }
        #expect(accessibilityCapturer.capturedWindowIDs.isEmpty)

        let summary = try await store.summary(runID: "run-manual-ax-denied")
        #expect(summary.artifacts.map(\.kind) == [.screenshot])
        #expect(summary.eventCount == 8)
        #expect(!fileExists(root
            .appendingPathComponent("run-manual-ax-denied", isDirectory: true)
            .appendingPathComponent("accessibility/accessibility-manual-ax-denied.json")))

        let records = try jsonlRecords(
            from: root
                .appendingPathComponent("run-manual-ax-denied", isDirectory: true)
                .appendingPathComponent("events.jsonl")
        )
        #expect(records.map(\.event.summary).filter { $0 == "Accessibility permission is not granted" }.count == 1)
        #expect(records.map(\.event.summary).contains("Run completed"))
        #expect(toolPayloads(in: records).filter { $0.capability == .accessibility && !$0.decision.isAllowed }.count == 1)
    }

    @Test
    func unsafeTargetFailsBeforeCaptureArtifacts() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let screenshotCapturer = FakeWindowScreenshotCapturer()
        let accessibilityCapturer = FakeMacAccessibilitySnapshotCapturer()
        let service = makeService(
            store: store,
            coordinator: RunCoordinator(),
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Safari", title: "Checkout Payment")
            ],
            frontmostProcessID: 100,
            screenshotCapturer: screenshotCapturer,
            accessibilityCapturer: accessibilityCapturer
        )

        do {
            _ = try await service.capture(
                session: RunSession(id: "run-manual-unsafe", userGoal: "capture context", targetID: "target-1"),
                traceID: "trace-manual-unsafe",
                screenshotArtifactID: "screenshot-manual-unsafe",
                accessibilityArtifactID: "accessibility-manual-unsafe"
            )
            Issue.record("Expected unsafe target refusal")
        } catch ManualTargetContextCaptureError.unsafeTarget(let windowID, let status) {
            #expect(windowID == 10)
            #expect(status == .blocked)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(screenshotCapturer.capturedWindowIDs.isEmpty)
        #expect(accessibilityCapturer.capturedWindowIDs.isEmpty)
        let summary = try await store.summary(runID: "run-manual-unsafe")
        #expect(summary.artifacts.isEmpty)
        #expect(summary.eventCount == 4)

        let records = try jsonlRecords(
            from: root
                .appendingPathComponent("run-manual-unsafe", isDirectory: true)
                .appendingPathComponent("events.jsonl")
        )
        #expect(records.map(\.event.summary) == [
            "Run starting",
            "Run running",
            "Target window refused",
            "Run failed"
        ])
    }

    @Test
    func screenshotFailureRecordsFailureAndNoArtifacts() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let screenshotCapturer = FakeWindowScreenshotCapturer(error: FixtureScreenshotError.failed)
        let accessibilityCapturer = FakeMacAccessibilitySnapshotCapturer()
        let service = makeService(
            store: store,
            coordinator: RunCoordinator(),
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Notes")
            ],
            frontmostProcessID: 100,
            screenshotCapturer: screenshotCapturer,
            accessibilityCapturer: accessibilityCapturer
        )

        do {
            _ = try await service.capture(
                session: RunSession(id: "run-manual-screenshot-failure", userGoal: "capture context", targetID: "target-1"),
                traceID: "trace-manual-screenshot-failure",
                screenshotArtifactID: "screenshot-manual-failure",
                accessibilityArtifactID: "accessibility-manual-failure"
            )
            Issue.record("Expected screenshot failure")
        } catch ManualTargetContextCaptureError.screenshotFailed(let reason) {
            #expect(reason.contains("failed"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(screenshotCapturer.capturedWindowIDs == [10])
        #expect(accessibilityCapturer.capturedWindowIDs.isEmpty)
        let summary = try await store.summary(runID: "run-manual-screenshot-failure")
        #expect(summary.artifacts.isEmpty)

        let records = try jsonlRecords(
            from: root
                .appendingPathComponent("run-manual-screenshot-failure", isDirectory: true)
                .appendingPathComponent("events.jsonl")
        )
        #expect(records.map(\.event.summary).contains("Screenshot capture failed"))
        #expect(records.map(\.event.summary).last == "Run failed")
        #expect(!fileExists(root
            .appendingPathComponent("run-manual-screenshot-failure", isDirectory: true)
            .appendingPathComponent("screenshots/screenshot-manual-failure.png")))
    }

    @Test
    func persistencePolicyDenialStopsBeforeDeniedWrite() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let screenshotCapturer = FakeWindowScreenshotCapturer()
        let accessibilityCapturer = FakeMacAccessibilitySnapshotCapturer()
        let service = makeService(
            store: store,
            coordinator: RunCoordinator(),
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Notes")
            ],
            frontmostProcessID: 100,
            screenshotCapturer: screenshotCapturer,
            accessibilityCapturer: accessibilityCapturer
        )
        let session = RunSession(
            id: "run-manual-persistence-denied",
            userGoal: "capture context",
            targetID: "target-1",
            permissionPolicy: ToolCallPolicy(deniedCapabilities: [.input, .persistence])
        )

        do {
            _ = try await service.capture(
                session: session,
                traceID: "trace-manual-persistence-denied",
                screenshotArtifactID: "screenshot-denied",
                accessibilityArtifactID: "accessibility-denied"
            )
            Issue.record("Expected persistence policy denial")
        } catch ManualTargetContextCaptureError.policyDenied(let capability, let reason) {
            #expect(capability == .persistence)
            #expect(reason == "persistence capability is denied by policy")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(screenshotCapturer.capturedWindowIDs.isEmpty)
        #expect(accessibilityCapturer.capturedWindowIDs.isEmpty)
        let summary = try await store.summary(runID: "run-manual-persistence-denied")
        #expect(summary.artifacts.isEmpty)

        let records = try jsonlRecords(
            from: root
                .appendingPathComponent("run-manual-persistence-denied", isDirectory: true)
                .appendingPathComponent("events.jsonl")
        )
        #expect(records.map(\.event.summary).contains("Screenshot artifact persistence denied by policy"))
        #expect(records.map(\.event.summary).last == "Run failed")
    }

    private func makeService(
        store: LocalRunArtifactStore,
        coordinator: RunCoordinator,
        windows: [MacWindowProviderWindow],
        frontmostProcessID: Int32? = nil,
        focusedWindowID: UInt32? = nil,
        screenshotCapturer: FakeWindowScreenshotCapturer,
        accessibilityCapturer: FakeMacAccessibilitySnapshotCapturer
    ) -> ManualTargetContextCaptureService {
        let windowResolver = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: windows,
                frontmostProcessID: frontmostProcessID,
                focusedWindowID: focusedWindowID
            )
        )
        let screenshotService = WindowScreenshotCaptureService(
            artifactStore: store,
            windowResolver: MacWindowResolver(
                provider: FixtureWindowProvider(
                    windows: windows,
                    frontmostProcessID: frontmostProcessID,
                    focusedWindowID: focusedWindowID
                )
            ),
            capturer: screenshotCapturer
        )
        let accessibilityService = MacAccessibilitySnapshotCaptureService(
            artifactStore: store,
            windowResolver: MacWindowResolver(
                provider: FixtureWindowProvider(
                    windows: windows,
                    frontmostProcessID: frontmostProcessID,
                    focusedWindowID: focusedWindowID
                )
            ),
            capturer: accessibilityCapturer
        )

        return ManualTargetContextCaptureService(
            coordinator: coordinator,
            artifactStore: store,
            windowResolver: windowResolver,
            screenshotService: screenshotService,
            accessibilityService: accessibilityService
        )
    }

    private func fixtureWindow(
        windowID: UInt32,
        processID: Int32,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        title: String? = nil,
        bounds: WindowTargetBounds = WindowTargetBounds(
            x: 0,
            y: 0,
            width: 100,
            height: 100
        )
    ) -> MacWindowProviderWindow {
        MacWindowProviderWindow(
            windowID: windowID,
            processID: processID,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            bounds: bounds
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "DonkeyManualTargetContextCaptureTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }

    private func jsonlRecords(from url: URL) throws -> [RunTraceEventRecord] {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        return try text
            .split(separator: "\n")
            .map { line in
                try JSONDecoder().decode(
                    RunTraceEventRecord.self,
                    from: Data(line.utf8)
                )
            }
    }

    private func toolPayloads(in records: [RunTraceEventRecord]) -> [ToolRunEvent] {
        records.compactMap { record in
            guard case .tool(let payload) = record.event.payload else {
                return nil
            }

            return payload
        }
    }
}

private final class FakeWindowScreenshotCapturer: WindowScreenshotCapturing {
    var pngData: Data
    var imageWidth: Int
    var imageHeight: Int
    var captureMethod: WindowScreenshotCaptureMethod
    var requiresOverlapFreeTarget: Bool
    var error: Error?
    var capturedWindowIDs: [UInt32] = []

    init(
        pngData: Data = Data([0x89, 0x50, 0x4E, 0x47]),
        imageWidth: Int = 100,
        imageHeight: Int = 100,
        captureMethod: WindowScreenshotCaptureMethod = .screenCaptureKitDesktopIndependentWindow,
        requiresOverlapFreeTarget: Bool = false,
        error: Error? = nil
    ) {
        self.pngData = pngData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.captureMethod = captureMethod
        self.requiresOverlapFreeTarget = requiresOverlapFreeTarget
        self.error = error
    }

    func capture(
        target: MacWindowTargetCandidate
    ) async throws -> CapturedWindowScreenshot {
        capturedWindowIDs.append(target.windowID)
        if let error {
            throw error
        }

        return CapturedWindowScreenshot(
            pngData: pngData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            captureMethod: captureMethod,
            coordinateSpace: "fixture.pixels"
        )
    }
}

private final class FakeMacAccessibilitySnapshotCapturer: MacAccessibilitySnapshotCapturing, @unchecked Sendable {
    var trust: MacAccessibilityTrustStatus
    var tree: MacAccessibilitySnapshotTree
    var error: Error?
    var capturedWindowIDs: [UInt32] = []

    init(
        trustStatus: MacAccessibilityTrustStatus = .trusted,
        tree: MacAccessibilitySnapshotTree = MacAccessibilitySnapshotTreeBuilder.build(
            root: RawMacAccessibilitySnapshotNode(role: "AXWindow", title: "Window"),
            limits: .default
        ),
        error: Error? = nil
    ) {
        self.trust = trustStatus
        self.tree = tree
        self.error = error
    }

    func trustStatus() -> MacAccessibilityTrustStatus {
        trust
    }

    func captureTree(
        target: MacWindowTargetCandidate,
        limits: MacAccessibilitySnapshotLimits
    ) throws -> MacAccessibilitySnapshotTree {
        capturedWindowIDs.append(target.windowID)
        if let error {
            throw error
        }

        return tree
    }
}

private enum FixtureScreenshotError: Error {
    case failed
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
