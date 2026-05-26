import DonkeyContracts
import Foundation

public struct ScreenshotSegmentationRequest: Equatable, Sendable {
    public var traceID: String
    public var frameID: String
    public var targetID: String
    public var cropID: String
    public var cropImageFileURL: URL?
    public var artifactURL: URL?
    public var cropBounds: HotLoopRect
    public var pixelSize: HotLoopSize
    public var metadata: [String: String]

    public init(
        traceID: String,
        frameID: String,
        targetID: String,
        cropID: String,
        cropImageFileURL: URL? = nil,
        artifactURL: URL? = nil,
        cropBounds: HotLoopRect,
        pixelSize: HotLoopSize,
        metadata: [String: String] = [:]
    ) {
        self.traceID = traceID
        self.frameID = frameID
        self.targetID = targetID
        self.cropID = cropID
        self.cropImageFileURL = cropImageFileURL
        self.artifactURL = artifactURL
        self.cropBounds = cropBounds
        self.pixelSize = pixelSize
        self.metadata = metadata
    }
}

public struct ScreenshotSegmentationMask: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var bounds: HotLoopRect
    public var confidence: Double
    public var pointCount: Int
    public var metadata: [String: String]

    public init(
        id: String,
        label: String,
        bounds: HotLoopRect,
        confidence: Double,
        pointCount: Int = 0,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.label = label
        self.bounds = bounds
        self.confidence = min(max(confidence, 0), 1)
        self.pointCount = max(0, pointCount)
        self.metadata = metadata
    }
}

public struct ScreenshotSegmentationBackendResult: Equatable, Sendable {
    public var masks: [ScreenshotSegmentationMask]
    public var preprocessMS: Double
    public var modelInferenceMS: Double
    public var metadata: [String: String]

    public init(
        masks: [ScreenshotSegmentationMask],
        preprocessMS: Double,
        modelInferenceMS: Double,
        metadata: [String: String] = [:]
    ) {
        self.masks = masks
        self.preprocessMS = max(0, preprocessMS)
        self.modelInferenceMS = max(0, modelInferenceMS)
        self.metadata = metadata
    }
}

public struct ScreenshotSegmentationResult: Equatable, Sendable {
    public var request: ScreenshotSegmentationRequest
    public var model: OffTheShelfVisionModelCandidate
    public var signal: RecordedOffTheShelfVisionSignal
    public var metadata: [String: String]

    public init(
        request: ScreenshotSegmentationRequest,
        model: OffTheShelfVisionModelCandidate,
        signal: RecordedOffTheShelfVisionSignal,
        metadata: [String: String]
    ) {
        self.request = request
        self.model = model
        self.signal = signal
        self.metadata = metadata
    }
}

public protocol ScreenshotSegmentationBackend: Sendable {
    func segment(
        request: ScreenshotSegmentationRequest,
        model: OffTheShelfVisionModelCandidate
    ) async throws -> ScreenshotSegmentationBackendResult
}

public enum ScreenshotSegmentationRunnerError: Error, Equatable, Sendable {
    case noModelCandidate
    case backendUnavailable(String)
    case invalidOutput(String)
}

public struct UnavailableScreenshotSegmentationBackend: ScreenshotSegmentationBackend {
    public init() {}

    public func segment(
        request: ScreenshotSegmentationRequest,
        model: OffTheShelfVisionModelCandidate
    ) async throws -> ScreenshotSegmentationBackendResult {
        throw ScreenshotSegmentationRunnerError.backendUnavailable(model.id)
    }
}

public struct ProcessBackedScreenshotSegmentationBackend: ScreenshotSegmentationBackend {
    public init(
        sidecarRunner: any LocalJSONSidecarRunning = ProcessBackedLocalJSONSidecarRunner(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        _ = sidecarRunner
        _ = encoder
        _ = decoder
    }

    public func segment(
        request: ScreenshotSegmentationRequest,
        model: OffTheShelfVisionModelCandidate
    ) async throws -> ScreenshotSegmentationBackendResult {
        _ = request
        _ = model
        return ScreenshotSegmentationBackendResult(
            masks: [],
            preprocessMS: 0,
            modelInferenceMS: 0,
            metadata: [
                "runner": "screenshot-segmentation-stub",
                "reason": "cvPipelineRemovedPendingReplacement",
                "rawPixelsRead": "false"
            ]
        )
    }
}

public struct ScreenshotSegmentationStubRunner: Sendable {
    public var model: OffTheShelfVisionModelCandidate
    public var backend: any ScreenshotSegmentationBackend
    public var now: @Sendable () -> RunTraceTimestamp

    public init(
        model: OffTheShelfVisionModelCandidate = OffTheShelfVisionModelCatalog.stubbedScreenshotSegmentation,
        backend: any ScreenshotSegmentationBackend = UnavailableScreenshotSegmentationBackend(),
        now: @escaping @Sendable () -> RunTraceTimestamp = Self.defaultNow
    ) {
        self.model = model
        self.backend = backend
        self.now = now
    }

    public func run(_ request: ScreenshotSegmentationRequest) async throws -> ScreenshotSegmentationResult {
        let startedAt = now()
        _ = backend
        let backendResult = ScreenshotSegmentationBackendResult(
            masks: [],
            preprocessMS: 0,
            modelInferenceMS: 0,
            metadata: [
                "runner": "screenshot-segmentation-stub",
                "reason": "cvPipelineRemovedPendingReplacement",
                "rawPixelsRead": "false"
            ]
        )
        let completedAt = now()
        let totalMS = startedAt.milliseconds(until: completedAt) ?? 0
        let adapterOverheadMS = max(0, totalMS - backendResult.preprocessMS - backendResult.modelInferenceMS)
        let signal = RecordedOffTheShelfVisionSignal(
            id: "segmentation-\(request.frameID)-\(request.cropID)",
            kind: .segmentation,
            componentID: model.componentID,
            modelID: model.id,
            cropID: request.cropID,
            confidence: backendResult.masks.map(\.confidence).max() ?? 0,
            observations: backendResult.masks.map { mask in
                RecordedOffTheShelfVisionObservation(
                    id: mask.id,
                    label: mask.label,
                    bounds: mask.bounds,
                    confidence: mask.confidence,
                    metadata: mask.metadata.merging([
                        "mask.pointCount": String(mask.pointCount)
                    ]) { current, _ in current }
                )
            },
            preprocessMS: backendResult.preprocessMS,
            modelInferenceMS: backendResult.modelInferenceMS,
            adapterOverheadMS: adapterOverheadMS,
            metadata: [
                "runner": "screenshot-segmentation-stub",
                "modelFamily": model.family,
                "modelName": model.modelName,
                "inputSource": model.preferredInputSource.rawValue,
                "liveDefault": model.metadata["liveDefault"] ?? "false",
                "reason": "cvPipelineRemovedPendingReplacement",
                "rawPixelsRead": "false",
                "latency.totalMS": String(totalMS)
            ].merging(backendResult.metadata) { current, _ in current }
        )

        return ScreenshotSegmentationResult(
            request: request,
            model: model,
            signal: signal,
            metadata: RecordedOffTheShelfVisionMetadataCodec.encode(signals: [signal])
        )
    }

    public static func defaultNow() -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(),
            monotonicUptimeNanoseconds: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        )
    }
}
