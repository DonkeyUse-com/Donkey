import CoreGraphics
import DonkeyContracts
import Foundation
import ScreenCaptureKit

public struct TargetWindowFrameCaptureRequest: Equatable, Sendable {
    public var selection: MacWindowSelectionRequest
    public var targetID: String
    public var traceID: String
    public var frameIDPrefix: String
    public var maxFrameCount: Int
    public var cropBoundsInWindow: HotLoopRect?
    public var plannerHintID: String?

    public init(
        selection: MacWindowSelectionRequest = MacWindowSelectionRequest(),
        targetID: String,
        traceID: String,
        frameIDPrefix: String = "target-frame",
        maxFrameCount: Int,
        cropBoundsInWindow: HotLoopRect? = nil,
        plannerHintID: String? = nil
    ) {
        self.selection = selection
        self.targetID = targetID
        self.traceID = traceID
        self.frameIDPrefix = frameIDPrefix
        self.maxFrameCount = maxFrameCount
        self.cropBoundsInWindow = cropBoundsInWindow
        self.plannerHintID = plannerHintID
    }
}

public struct TargetWindowFrameCaptureResult: Equatable, Sendable {
    public var target: MacWindowTargetCandidate
    public var frames: [HotLoopFrame]
    public var captureMethod: WindowScreenshotCaptureMethod
    public var overlapStatus: WindowScreenshotOverlapStatus

    public init(
        target: MacWindowTargetCandidate,
        frames: [HotLoopFrame],
        captureMethod: WindowScreenshotCaptureMethod,
        overlapStatus: WindowScreenshotOverlapStatus
    ) {
        self.target = target
        self.frames = frames
        self.captureMethod = captureMethod
        self.overlapStatus = overlapStatus
    }
}

struct CapturedTargetWindowFrame: Equatable, Sendable {
    var imageWidth: Int
    var imageHeight: Int
    var captureMethod: WindowScreenshotCaptureMethod
    var coordinateSpace: String

    init(
        imageWidth: Int,
        imageHeight: Int,
        captureMethod: WindowScreenshotCaptureMethod,
        coordinateSpace: String
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.captureMethod = captureMethod
        self.coordinateSpace = coordinateSpace
    }
}

protocol TargetWindowFrameCapturing: Sendable {
    var captureMethod: WindowScreenshotCaptureMethod { get }
    var requiresOverlapFreeTarget: Bool { get }

    func captureFrame(
        target: MacWindowTargetCandidate
    ) async throws -> CapturedTargetWindowFrame
}

protocol RunTraceTimestampProviding: Sendable {
    func now() -> RunTraceTimestamp
}

public final class TargetWindowFrameCaptureService: @unchecked Sendable {
    private let windowResolver: MacWindowResolver
    private let capturer: any TargetWindowFrameCapturing
    private let timestampProvider: any RunTraceTimestampProviding

    public convenience init() {
        self.init(
            windowResolver: MacWindowResolver(),
            capturer: ScreenCaptureKitTargetWindowFrameCapturer(),
            timestampProvider: SystemRunTraceTimestampProvider()
        )
    }

    init(
        windowResolver: MacWindowResolver,
        capturer: any TargetWindowFrameCapturing,
        timestampProvider: any RunTraceTimestampProviding = SystemRunTraceTimestampProvider()
    ) {
        self.windowResolver = windowResolver
        self.capturer = capturer
        self.timestampProvider = timestampProvider
    }

    public func captureFrames(
        request: TargetWindowFrameCaptureRequest
    ) async throws -> TargetWindowFrameCaptureResult {
        let candidates = windowResolver.enumerateCandidates()
        let target = try selectTarget(request.selection, from: candidates)
        guard target.safetyAssessment.status == .allowed else {
            throw WindowScreenshotCaptureError.unsafeTarget(
                windowID: target.windowID,
                status: target.safetyAssessment.status
            )
        }

        let overlapStatus = try validateOverlap(
            for: target,
            in: candidates
        )
        let frameCount = max(0, request.maxFrameCount)
        var frames: [HotLoopFrame] = []
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            frames.append(
                try await captureFrame(
                    request: request,
                    target: target,
                    frameIndex: index
                )
            )
        }

        return TargetWindowFrameCaptureResult(
            target: target,
            frames: frames,
            captureMethod: capturer.captureMethod,
            overlapStatus: overlapStatus
        )
    }

    private func captureFrame(
        request: TargetWindowFrameCaptureRequest,
        target: MacWindowTargetCandidate,
        frameIndex: Int
    ) async throws -> HotLoopFrame {
        let captureStart = timestampProvider.now()
        let captured: CapturedTargetWindowFrame
        do {
            captured = try await capturer.captureFrame(target: target)
        } catch let error as WindowScreenshotCaptureError {
            throw error
        } catch {
            throw WindowScreenshotCaptureError.captureFailed(
                windowID: target.windowID,
                reason: String(describing: error)
            )
        }

        let captureEnd = timestampProvider.now()
        let copyStart = timestampProvider.now()
        let frame = HotLoopFrame(
            id: "\(request.frameIDPrefix)-\(frameIndex + 1)",
            traceID: request.traceID,
            targetID: request.targetID,
            capturedAt: captureEnd,
            sourceKind: .targetWindow,
            windowBounds: HotLoopRect(
                x: target.bounds.x,
                y: target.bounds.y,
                width: target.bounds.width,
                height: target.bounds.height,
                space: .screen
            ),
            crop: crop(
                request.cropBoundsInWindow,
                fallbackWidth: captured.imageWidth,
                fallbackHeight: captured.imageHeight
            ),
            pixelSize: HotLoopSize(
                width: Double(captured.imageWidth),
                height: Double(captured.imageHeight),
                space: .window
            ),
            plannerHintID: request.plannerHintID,
            metadata: metadata(
                target: target,
                captured: captured,
                captureStart: captureStart,
                captureEnd: captureEnd,
                copyStart: copyStart,
                copyEnd: timestampProvider.now()
            )
        )

        return frame
    }

    private func selectTarget(
        _ selection: MacWindowSelectionRequest,
        from candidates: [MacWindowTargetCandidate]
    ) throws -> MacWindowTargetCandidate {
        guard !candidates.isEmpty else {
            throw MacWindowResolverError.noVisibleWindows
        }

        if let windowID = selection.windowID {
            guard let target = candidates.first(where: { $0.windowID == windowID }) else {
                throw MacWindowResolverError.windowNotFound(windowID: windowID)
            }

            return target
        }

        if let focused = candidates.first(where: \.isFocused) {
            return focused
        }

        if let frontmost = candidates.first(where: \.isFrontmost) {
            return frontmost
        }

        throw MacWindowResolverError.noFocusedWindow
    }

    private func validateOverlap(
        for target: MacWindowTargetCandidate,
        in candidates: [MacWindowTargetCandidate]
    ) throws -> WindowScreenshotOverlapStatus {
        guard capturer.requiresOverlapFreeTarget else {
            return .notRequired
        }

        guard let targetIndex = candidates.firstIndex(where: { $0.windowID == target.windowID }) else {
            return .clear
        }

        if let occludingWindow = candidates[..<targetIndex].first(where: { candidate in
            candidate.windowID != target.windowID
                && candidate.isVisible
                && candidate.isOnScreen
                && candidate.bounds.intersects(target.bounds)
        }) {
            throw WindowScreenshotCaptureError.occludedTarget(
                windowID: target.windowID,
                occludingWindowID: occludingWindow.windowID
            )
        }

        return .clear
    }

    private func crop(
        _ cropBoundsInWindow: HotLoopRect?,
        fallbackWidth: Int,
        fallbackHeight: Int
    ) -> HotLoopCrop? {
        guard let cropBoundsInWindow else { return nil }

        return HotLoopCrop(
            id: "target-window-crop",
            bounds: cropBoundsInWindow,
            outputSize: HotLoopSize(
                width: min(Double(fallbackWidth), cropBoundsInWindow.size.width),
                height: min(Double(fallbackHeight), cropBoundsInWindow.size.height),
                space: .crop
            )
        )
    }

    private func metadata(
        target: MacWindowTargetCandidate,
        captured: CapturedTargetWindowFrame,
        captureStart: RunTraceTimestamp,
        captureEnd: RunTraceTimestamp,
        copyStart: RunTraceTimestamp,
        copyEnd: RunTraceTimestamp
    ) -> [String: String] {
        var metadata = [
            "target.windowID": String(target.windowID),
            "target.processID": String(target.processID),
            "target.bounds.x": String(target.bounds.x),
            "target.bounds.y": String(target.bounds.y),
            "target.bounds.width": String(target.bounds.width),
            "target.bounds.height": String(target.bounds.height),
            "target.isIPhoneMirroring": String(target.isIPhoneMirroring),
            "target.safety.status": target.safetyAssessment.status.rawValue,
            "capture.method": captured.captureMethod.rawValue,
            "capture.coordinateSpace": captured.coordinateSpace,
            "capture.imageWidth": String(captured.imageWidth),
            "capture.imageHeight": String(captured.imageHeight),
            "capture.latencyMS": String(captureStart.milliseconds(until: captureEnd) ?? 0),
            "capture.copyCostMS": String(copyStart.milliseconds(until: copyEnd) ?? 0),
            "capture.encoded": "false",
            "capture.artifactWritten": "false"
        ]

        if let appName = target.appName {
            metadata["target.appName"] = appName
        }

        if let bundleIdentifier = target.bundleIdentifier {
            metadata["target.bundleIdentifier"] = bundleIdentifier
        }

        if let title = target.title {
            metadata["target.title"] = title
        }

        return metadata
    }
}

public struct TargetWindowFrameSource: DryRunFrameSource {
    public let service: TargetWindowFrameCaptureService
    public let request: TargetWindowFrameCaptureRequest

    public init(
        service: TargetWindowFrameCaptureService = TargetWindowFrameCaptureService(),
        request: TargetWindowFrameCaptureRequest
    ) {
        self.service = service
        self.request = request
    }

    public func frameBatches() async -> [[HotLoopFrame]] {
        do {
            return try await service.captureFrames(request: request).frames.map { [$0] }
        } catch {
            return []
        }
    }
}

private final class ScreenCaptureKitTargetWindowFrameCapturer: TargetWindowFrameCapturing {
    var captureMethod: WindowScreenshotCaptureMethod {
        .screenCaptureKitDesktopIndependentWindow
    }

    var requiresOverlapFreeTarget: Bool {
        false
    }

    func captureFrame(
        target: MacWindowTargetCandidate
    ) async throws -> CapturedTargetWindowFrame {
        let content = try await SCShareableContent.current
        guard let window = content.windows.first(where: { $0.windowID == target.windowID }) else {
            throw WindowScreenshotCaptureError.targetWindowUnavailable(windowID: target.windowID)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let contentInfo = SCShareableContent.info(for: filter)
        let scale = CGFloat(contentInfo.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(ceil(contentInfo.contentRect.width * scale)))
        configuration.height = max(1, Int(ceil(contentInfo.contentRect.height * scale)))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return CapturedTargetWindowFrame(
            imageWidth: image.width,
            imageHeight: image.height,
            captureMethod: .screenCaptureKitDesktopIndependentWindow,
            coordinateSpace: "screenCaptureKit.contentRect.pixels"
        )
    }
}

private struct SystemRunTraceTimestampProvider: RunTraceTimestampProviding {
    func now() -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(),
            monotonicUptimeNanoseconds: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        )
    }
}

private extension WindowTargetBounds {
    func intersects(_ other: WindowTargetBounds) -> Bool {
        let maxX = x + width
        let maxY = y + height
        let otherMaxX = other.x + other.width
        let otherMaxY = other.y + other.height

        return x < otherMaxX
            && maxX > other.x
            && y < otherMaxY
            && maxY > other.y
    }
}
