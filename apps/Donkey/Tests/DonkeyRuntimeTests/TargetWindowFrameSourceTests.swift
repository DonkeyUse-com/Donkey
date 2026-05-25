import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct TargetWindowFrameSourceTests {
    @Test
    func captureFramesProducesBoundedTargetWindowHotLoopFrames() async throws {
        let capturer = FakeTargetWindowFrameCapturer(
            imageWidth: 320,
            imageHeight: 240
        )
        let service = makeService(
            windows: [
                fixtureWindow(
                    windowID: 10,
                    processID: 100,
                    appName: "Preview",
                    title: "Target"
                )
            ],
            frontmostProcessID: 100,
            capturer: capturer
        )

        let result = try await service.captureFrames(
            request: TargetWindowFrameCaptureRequest(
                selection: MacWindowSelectionRequest(windowID: 10),
                targetID: "target-1",
                traceID: "trace-window",
                frameIDPrefix: "window-frame",
                maxFrameCount: 2,
                plannerHintID: "hint-1"
            )
        )

        #expect(result.target.windowID == 10)
        #expect(result.captureMethod == .screenCaptureKitDesktopIndependentWindow)
        #expect(result.overlapStatus == .notRequired)
        #expect(capturer.capturedWindowIDs == [10, 10])
        #expect(result.frames.map(\.id) == ["window-frame-1", "window-frame-2"])
        #expect(result.frames.allSatisfy { $0.sourceKind == .targetWindow })
        #expect(result.frames.allSatisfy { $0.traceID == "trace-window" })
        #expect(result.frames.allSatisfy { $0.targetID == "target-1" })
        #expect(result.frames.allSatisfy { $0.plannerHintID == "hint-1" })
        #expect(result.frames.first?.pixelSize == HotLoopSize(width: 320, height: 240, space: .window))
        #expect(result.frames.first?.windowBounds == HotLoopRect(x: 0, y: 0, width: 100, height: 100, space: .screen))
        #expect(result.frames.first?.metadata["capture.encoded"] == "false")
        #expect(result.frames.first?.metadata["capture.artifactWritten"] == "false")
        #expect(result.frames.first?.metadata["capture.latencyMS"] == "5.0")
        #expect(result.frames.first?.metadata["capture.copyCostMS"] == "2.0")
    }

    @Test
    func screenCaptureKitFrameCapturerFailsFastWhenScreenRecordingPermissionIsDenied() async throws {
        let capturer = ScreenCaptureKitTargetWindowFrameCapturer(
            permissionChecker: FakeScreenRecordingPermissionChecker(hasAccess: false)
        )

        do {
            _ = try await capturer.captureFrame(target: allowedTargetWindow())
            Issue.record("Expected screen recording permission denial")
        } catch WindowScreenshotCaptureError.screenRecordingPermissionDenied {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func captureFramesAppliesOptionalCropWithoutWritingPlannerSnapshotArtifact() async throws {
        let service = makeService(
            windows: [
                fixtureWindow(windowID: 22, processID: 200, appName: "Game")
            ],
            frontmostProcessID: 200,
            capturer: FakeTargetWindowFrameCapturer(
                imageWidth: 400,
                imageHeight: 300
            )
        )
        let cropBounds = HotLoopRect(
            x: 25,
            y: 50,
            width: 200,
            height: 100,
            space: .window
        )

        let result = try await service.captureFrames(
            request: TargetWindowFrameCaptureRequest(
                selection: MacWindowSelectionRequest(windowID: 22),
                targetID: "target-game",
                traceID: "trace-crop",
                maxFrameCount: 1,
                cropBoundsInWindow: cropBounds
            )
        )

        #expect(result.frames.first?.crop?.bounds == cropBounds)
        #expect(result.frames.first?.crop?.outputSize == HotLoopSize(width: 200, height: 100, space: .crop))
        #expect(result.frames.first?.metadata["capture.artifactWritten"] == "false")
    }

    @Test
    func iPhoneMirroringFramesDefaultToCenteredPhoneContentCrop() async throws {
        let service = makeService(
            windows: [
                fixtureWindow(
                    windowID: 33,
                    processID: 300,
                    appName: "iPhone Mirroring",
                    bundleIdentifier: "com.apple.ScreenContinuity"
                )
            ],
            frontmostProcessID: 300,
            capturer: FakeTargetWindowFrameCapturer(
                imageWidth: 500,
                imageHeight: 1_000
            )
        )

        let result = try await service.captureFrames(
            request: TargetWindowFrameCaptureRequest(
                selection: MacWindowSelectionRequest(windowID: 33),
                targetID: "target-iphone",
                traceID: "trace-iphone",
                maxFrameCount: 1
            )
        )

        let crop = try #require(result.frames.first?.crop)
        #expect(crop.id == "target-window-content")
        #expect(abs(crop.bounds.origin.x - 19.230_769) < 0.001)
        #expect(crop.bounds.origin.y == 0)
        #expect(abs(crop.bounds.size.width - 461.538_461) < 0.001)
        #expect(crop.bounds.size.height == 1_000)
        #expect(result.frames.first?.metadata["contentCalibration.mode"] == "centeredAspectFit")
        #expect(result.frames.first?.metadata["contentCalibration.target.isIPhoneMirroring"] == "true")
    }

    @Test
    func unsafeTargetRefusesBeforeCapturingFrames() async throws {
        let capturer = FakeTargetWindowFrameCapturer()
        let service = makeService(
            windows: [
                fixtureWindow(windowID: 10, processID: 100, appName: "Safari", title: "Checkout Payment")
            ],
            frontmostProcessID: 100,
            capturer: capturer
        )

        do {
            _ = try await service.captureFrames(
                request: TargetWindowFrameCaptureRequest(
                    selection: MacWindowSelectionRequest(windowID: 10),
                    targetID: "target-1",
                    traceID: "trace-unsafe",
                    maxFrameCount: 1
                )
            )
            Issue.record("Expected unsafe target to be refused")
        } catch WindowScreenshotCaptureError.unsafeTarget(let windowID, let status) {
            #expect(windowID == 10)
            #expect(status == .blocked)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(capturer.capturedWindowIDs.isEmpty)
    }

    @Test
    func overlapSensitiveFrameBackendRefusesOccludedTarget() async throws {
        let capturer = FakeTargetWindowFrameCapturer(
            captureMethod: .boundsCrop,
            requiresOverlapFreeTarget: true
        )
        let service = makeService(
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
            _ = try await service.captureFrames(
                request: TargetWindowFrameCaptureRequest(
                    selection: MacWindowSelectionRequest(windowID: 2),
                    targetID: "target-1",
                    traceID: "trace-occluded",
                    maxFrameCount: 1
                )
            )
            Issue.record("Expected occluded target to be refused")
        } catch WindowScreenshotCaptureError.occludedTarget(let windowID, let occludingWindowID) {
            #expect(windowID == 2)
            #expect(occludingWindowID == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(capturer.capturedWindowIDs.isEmpty)
    }

    @Test
    func targetWindowFrameSourceFeedsDryRunFrameBatches() async {
        let service = makeService(
            windows: [
                fixtureWindow(windowID: 30, processID: 300, appName: "Game")
            ],
            frontmostProcessID: 300,
            capturer: FakeTargetWindowFrameCapturer()
        )
        let source = TargetWindowFrameSource(
            service: service,
            request: TargetWindowFrameCaptureRequest(
                selection: MacWindowSelectionRequest(windowID: 30),
                targetID: "target-game",
                traceID: "trace-source",
                frameIDPrefix: "source-frame",
                maxFrameCount: 2
            )
        )

        let batches = await source.frameBatches()

        #expect(batches.count == 2)
        #expect(batches.allSatisfy { $0.count == 1 })
        #expect(batches.flatMap { $0 }.map(\.id) == ["source-frame-1", "source-frame-2"])
    }

    @Test
    func continuousTargetWindowFrameSourceStreamsLatestFrameBatches() async {
        let capturer = FakeTargetWindowFrameCapturer()
        let service = makeService(
            windows: [
                fixtureWindow(windowID: 31, processID: 301, appName: "Game")
            ],
            frontmostProcessID: 301,
            capturer: capturer
        )
        let source = ContinuousTargetWindowFrameSource(
            service: service,
            request: TargetWindowFrameCaptureRequest(
                selection: MacWindowSelectionRequest(windowID: 31),
                targetID: "target-game",
                traceID: "trace-stream",
                frameIDPrefix: "stream-frame",
                maxFrameCount: 1
            ),
            minimumFrameIntervalNanoseconds: 0,
            maximumFrameCount: 3
        )

        var frames: [HotLoopFrame] = []
        for await batch in source.frameBatchStream() {
            frames.append(contentsOf: batch)
        }

        #expect(frames.count == 3)
        #expect(frames.map(\.id) == [
            "stream-frame-stream-1-1",
            "stream-frame-stream-2-1",
            "stream-frame-stream-3-1"
        ])
        #expect(capturer.capturedWindowIDs == [31, 31, 31])
    }

    private func makeService(
        windows: [MacWindowProviderWindow],
        frontmostProcessID: Int32? = nil,
        focusedWindowID: UInt32? = nil,
        capturer: FakeTargetWindowFrameCapturer
    ) -> TargetWindowFrameCaptureService {
        TargetWindowFrameCaptureService(
            windowResolver: MacWindowResolver(
                provider: FixtureWindowProvider(
                    windows: windows,
                    frontmostProcessID: frontmostProcessID,
                    focusedWindowID: focusedWindowID
                )
            ),
            capturer: capturer,
            timestampProvider: FixtureTimestampProvider()
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

    private func allowedTargetWindow(
        windowID: UInt32 = 10,
        processID: Int32 = 100
    ) -> MacWindowTargetCandidate {
        MacWindowTargetCandidate(
            windowID: windowID,
            processID: processID,
            bounds: WindowTargetBounds(x: 0, y: 0, width: 100, height: 100),
            isVisible: true,
            isOnScreen: true,
            isFrontmost: true,
            isFocused: true,
            isIPhoneMirroring: false,
            safetyAssessment: WindowTargetSafetyAssessment(
                status: .allowed,
                summary: "Allowed fixture window"
            )
        )
    }
}

private struct FakeScreenRecordingPermissionChecker: ScreenRecordingPermissionChecking {
    var hasAccess: Bool

    func hasScreenRecordingAccess() -> Bool {
        hasAccess
    }
}

private final class FakeTargetWindowFrameCapturer: TargetWindowFrameCapturing, @unchecked Sendable {
    var imageWidth: Int
    var imageHeight: Int
    var captureMethod: WindowScreenshotCaptureMethod
    var requiresOverlapFreeTarget: Bool
    var capturedWindowIDs: [UInt32] = []

    init(
        imageWidth: Int = 100,
        imageHeight: Int = 100,
        captureMethod: WindowScreenshotCaptureMethod = .screenCaptureKitDesktopIndependentWindow,
        requiresOverlapFreeTarget: Bool = false
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.captureMethod = captureMethod
        self.requiresOverlapFreeTarget = requiresOverlapFreeTarget
    }

    func captureFrame(
        target: MacWindowTargetCandidate
    ) async throws -> CapturedTargetWindowFrame {
        capturedWindowIDs.append(target.windowID)
        return CapturedTargetWindowFrame(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            captureMethod: captureMethod,
            coordinateSpace: "fixture.window.pixels"
        )
    }
}

private final class FixtureTimestampProvider: RunTraceTimestampProviding, @unchecked Sendable {
    private var nextMilliseconds: UInt64 = 0

    func now() -> RunTraceTimestamp {
        defer { nextMilliseconds += nextMilliseconds % 4 == 0 ? 5 : nextMilliseconds % 4 == 1 ? 1 : 2 }

        return RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(nextMilliseconds) / 1_000),
            monotonicUptimeNanoseconds: nextMilliseconds * 1_000_000
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
