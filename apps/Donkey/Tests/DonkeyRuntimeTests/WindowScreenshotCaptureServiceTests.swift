import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct WindowScreenshotCaptureServiceTests {
    @Test
    func safeTargetCaptureWritesPngBytesAndRecordsArtifactMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let session = RunSession(
            id: "run-screenshot",
            userGoal: "capture context",
            targetID: "target-1"
        )
        _ = try await store.prepareRun(session: session, traceID: "trace-screenshot")
        let capturer = FakeWindowScreenshotCapturer(
            pngData: pngBytes(),
            imageWidth: 320,
            imageHeight: 240,
            captureMethod: .screenCaptureKitDesktopIndependentWindow,
            requiresOverlapFreeTarget: false
        )
        let service = makeService(
            store: store,
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Notes", title: "Plan")
            ],
            frontmostProcessID: 100,
            capturer: capturer
        )

        let result = try await service.captureScreenshot(
            runID: "run-screenshot",
            artifactID: "screenshot-1"
        )

        #expect(result.target.windowID == 10)
        #expect(result.artifact.relativePath == "screenshots/screenshot-1.png")
        #expect(result.artifact.contentType == "image/png")
        #expect(result.artifact.byteCount == Int64(pngBytes().count))
        #expect(result.imageWidth == 320)
        #expect(result.imageHeight == 240)
        #expect(result.captureMethod == .screenCaptureKitDesktopIndependentWindow)
        #expect(result.overlapStatus == .notRequired)
        #expect(capturer.capturedWindowIDs == [10])

        let fileURL = root
            .appendingPathComponent("run-screenshot", isDirectory: true)
            .appendingPathComponent("screenshots/screenshot-1.png")
        #expect(try Data(contentsOf: fileURL) == pngBytes())

        let summary = try await store.summary(runID: "run-screenshot")
        #expect(summary.artifacts.count == 1)
        #expect(summary.artifacts.first?.metadata["runID"] == "run-screenshot")
        #expect(summary.artifacts.first?.metadata["traceID"] == "trace-screenshot")
        #expect(summary.artifacts.first?.metadata["target.windowID"] == "10")
        #expect(summary.artifacts.first?.metadata["target.appName"] == "Notes")
        #expect(summary.artifacts.first?.metadata["target.title"] == "Plan")
        #expect(summary.artifacts.first?.metadata["capture.method"] == "screenCaptureKitDesktopIndependentWindow")
        #expect(summary.artifacts.first?.metadata["capture.imageWidth"] == "320")
        #expect(summary.artifacts.first?.metadata["capture.imageHeight"] == "240")
        #expect(summary.artifacts.first?.metadata["capture.overlapStatus"] == "notRequired")
    }

    @Test
    func explicitWindowSelectionIsPassedToCapturer() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        _ = try await store.prepareRun(
            session: RunSession(id: "run-explicit", userGoal: "capture", targetID: "target-1"),
            traceID: "trace-explicit"
        )
        let capturer = FakeWindowScreenshotCapturer()
        let service = makeService(
            store: store,
            windows: [
                fixtureWindow(windowID: 1, processID: 100, appName: "Terminal"),
                fixtureWindow(windowID: 2, processID: 200, appName: "Safari")
            ],
            frontmostProcessID: 100,
            capturer: capturer
        )

        let result = try await service.captureScreenshot(
            runID: "run-explicit",
            selection: MacWindowSelectionRequest(windowID: 2),
            artifactID: "screenshot-explicit"
        )

        #expect(result.target.windowID == 2)
        #expect(capturer.capturedWindowIDs == [2])
    }

    @Test
    func unsafeTargetRefusesBeforeWritingFileOrArtifact() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        _ = try await store.prepareRun(
            session: RunSession(id: "run-unsafe", userGoal: "capture", targetID: "target-1"),
            traceID: "trace-unsafe"
        )
        let capturer = FakeWindowScreenshotCapturer()
        let service = makeService(
            store: store,
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Safari", title: "Checkout Payment")
            ],
            frontmostProcessID: 100,
            capturer: capturer
        )

        do {
            _ = try await service.captureScreenshot(
                runID: "run-unsafe",
                artifactID: "screenshot-unsafe"
            )
            Issue.record("Expected unsafe target to be refused")
        } catch WindowScreenshotCaptureError.unsafeTarget(let windowID, let status) {
            #expect(windowID == 10)
            #expect(status == .blocked)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let summary = try await store.summary(runID: "run-unsafe")
        #expect(summary.artifacts.isEmpty)
        #expect(capturer.capturedWindowIDs.isEmpty)
        #expect(!fileExists(root
            .appendingPathComponent("run-unsafe", isDirectory: true)
            .appendingPathComponent("screenshots/screenshot-unsafe.png")))
    }

    @Test
    func missingPreparedRunFailsWithoutWritingFile() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let capturer = FakeWindowScreenshotCapturer()
        let service = makeService(
            store: store,
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Notes")
            ],
            frontmostProcessID: 100,
            capturer: capturer
        )

        do {
            _ = try await service.captureScreenshot(
                runID: "missing-run",
                artifactID: "screenshot-missing"
            )
            Issue.record("Expected missing prepared run to fail")
        } catch WindowScreenshotCaptureError.missingPreparedRun(let runID) {
            #expect(runID == "missing-run")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(capturer.capturedWindowIDs.isEmpty)
        #expect(!fileExists(root
            .appendingPathComponent("missing-run", isDirectory: true)
            .appendingPathComponent("screenshots/screenshot-missing.png")))
    }

    @Test
    func fakeCapturerRecordsImageDimensionsAndMethodMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        _ = try await store.prepareRun(
            session: RunSession(id: "run-method", userGoal: "capture", targetID: "target-1"),
            traceID: "trace-method"
        )
        let service = makeService(
            store: store,
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Preview")
            ],
            frontmostProcessID: 100,
            capturer: FakeWindowScreenshotCapturer(
                imageWidth: 640,
                imageHeight: 480,
                captureMethod: .boundsCrop,
                requiresOverlapFreeTarget: true
            )
        )

        let result = try await service.captureScreenshot(
            runID: "run-method",
            artifactID: "screenshot-method"
        )

        #expect(result.captureMethod == .boundsCrop)
        #expect(result.overlapStatus == .clear)
        #expect(result.imageWidth == 640)
        #expect(result.imageHeight == 480)

        let summary = try await store.summary(runID: "run-method")
        #expect(summary.artifacts.first?.metadata["capture.method"] == "boundsCrop")
        #expect(summary.artifacts.first?.metadata["capture.imageWidth"] == "640")
        #expect(summary.artifacts.first?.metadata["capture.imageHeight"] == "480")
        #expect(summary.artifacts.first?.metadata["capture.overlapStatus"] == "clear")
    }

    @Test
    func overlapSensitiveBackendRefusesOccludedBoundsCropTarget() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        _ = try await store.prepareRun(
            session: RunSession(id: "run-occluded", userGoal: "capture", targetID: "target-1"),
            traceID: "trace-occluded"
        )
        let capturer = FakeWindowScreenshotCapturer(
            captureMethod: .boundsCrop,
            requiresOverlapFreeTarget: true
        )
        let service = makeService(
            store: store,
            windows: [
                fixtureWindow(
                    windowID: 1,
                    processID: 100,
                    appName: "Occluder",
                    bounds: WindowTargetBounds(x: 25, y: 25, width: 50, height: 50)
                ),
                fixtureWindow(
                    windowID: 2,
                    processID: 200,
                    appName: "Target",
                    bounds: WindowTargetBounds(x: 0, y: 0, width: 100, height: 100)
                )
            ],
            frontmostProcessID: 200,
            capturer: capturer
        )

        do {
            _ = try await service.captureScreenshot(
                runID: "run-occluded",
                selection: MacWindowSelectionRequest(windowID: 2),
                artifactID: "screenshot-occluded"
            )
            Issue.record("Expected occluded bounds crop target to be refused")
        } catch WindowScreenshotCaptureError.occludedTarget(let windowID, let occludingWindowID) {
            #expect(windowID == 2)
            #expect(occludingWindowID == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(capturer.capturedWindowIDs.isEmpty)
        let summary = try await store.summary(runID: "run-occluded")
        #expect(summary.artifacts.isEmpty)
    }

    @Test
    func trueWindowBackendAllowsOverlappedTarget() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        _ = try await store.prepareRun(
            session: RunSession(id: "run-overlap-allowed", userGoal: "capture", targetID: "target-1"),
            traceID: "trace-overlap-allowed"
        )
        let capturer = FakeWindowScreenshotCapturer(
            captureMethod: .screenCaptureKitDesktopIndependentWindow,
            requiresOverlapFreeTarget: false
        )
        let service = makeService(
            store: store,
            windows: [
                fixtureWindow(
                    windowID: 1,
                    processID: 100,
                    appName: "Occluder",
                    bounds: WindowTargetBounds(x: 25, y: 25, width: 50, height: 50)
                ),
                fixtureWindow(
                    windowID: 2,
                    processID: 200,
                    appName: "Target",
                    bounds: WindowTargetBounds(x: 0, y: 0, width: 100, height: 100)
                )
            ],
            frontmostProcessID: 200,
            capturer: capturer
        )

        let result = try await service.captureScreenshot(
            runID: "run-overlap-allowed",
            selection: MacWindowSelectionRequest(windowID: 2),
            artifactID: "screenshot-overlap-allowed"
        )

        #expect(result.target.windowID == 2)
        #expect(result.overlapStatus == .notRequired)
        #expect(capturer.capturedWindowIDs == [2])
    }

    private func makeService(
        store: LocalRunArtifactStore,
        windows: [MacWindowProviderWindow],
        frontmostProcessID: Int32? = nil,
        focusedWindowID: UInt32? = nil,
        capturer: FakeWindowScreenshotCapturer
    ) -> WindowScreenshotCaptureService {
        WindowScreenshotCaptureService(
            artifactStore: store,
            windowResolver: MacWindowResolver(
                provider: FixtureWindowProvider(
                    windows: windows,
                    frontmostProcessID: frontmostProcessID,
                    focusedWindowID: focusedWindowID
                )
            ),
            capturer: capturer
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
            "DonkeyWindowScreenshotTests-\(UUID().uuidString)",
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

    private func pngBytes() -> Data {
        Data([0x89, 0x50, 0x4E, 0x47])
    }
}

private final class FakeWindowScreenshotCapturer: WindowScreenshotCapturing {
    var pngData: Data
    var imageWidth: Int
    var imageHeight: Int
    var captureMethod: WindowScreenshotCaptureMethod
    var requiresOverlapFreeTarget: Bool
    var capturedWindowIDs: [UInt32] = []

    init(
        pngData: Data = Data([0x89, 0x50, 0x4E, 0x47]),
        imageWidth: Int = 100,
        imageHeight: Int = 100,
        captureMethod: WindowScreenshotCaptureMethod = .screenCaptureKitDesktopIndependentWindow,
        requiresOverlapFreeTarget: Bool = false
    ) {
        self.pngData = pngData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.captureMethod = captureMethod
        self.requiresOverlapFreeTarget = requiresOverlapFreeTarget
    }

    func capture(
        target: MacWindowTargetCandidate
    ) async throws -> CapturedWindowScreenshot {
        capturedWindowIDs.append(target.windowID)
        return CapturedWindowScreenshot(
            pngData: pngData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            captureMethod: captureMethod,
            coordinateSpace: "fixture.pixels"
        )
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
