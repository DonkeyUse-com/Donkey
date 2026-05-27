import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct OffTheShelfVisionPerceptionTests {
    @Test
    func modelCatalogDoesNotExposeRunnableScreenshotSegmentationCandidate() {
        let candidate = OffTheShelfVisionModelCatalog.defaultCandidate(
            signalKind: .segmentation,
            inputSource: .screenshot
        )

        #expect(candidate == nil)
        #expect(OffTheShelfVisionModelCatalog.screenshotSegmentationCandidates.isEmpty)
        #expect(OffTheShelfVisionModelCatalog.stubbedScreenshotSegmentation.metadata["reason"] == "cvPipelineRemovedPendingReplacement")
    }

    @Test
    func metadataCodecRemainsReadOnlyTraceCodecForLegacyArtifacts() throws {
        let metadata = RecordedOffTheShelfVisionMetadataCodec.encode(signals: [
            RecordedOffTheShelfVisionSignal(
                id: "legacy-signal",
                kind: .segmentation,
                componentID: "legacy-component",
                modelID: "legacy-model",
                cropID: "legacy-crop",
                confidence: 0.88,
                observations: [
                    RecordedOffTheShelfVisionObservation(
                        id: "legacy-observation",
                        label: "legacy",
                        bounds: HotLoopRect(
                            x: 0.42,
                            y: 0.58,
                            width: 0.12,
                            height: 0.08,
                            space: .normalizedTarget
                        ),
                        confidence: 0.82
                    )
                ]
            )
        ])

        let signals = RecordedOffTheShelfVisionMetadataCodec.decode(from: metadata)

        #expect(metadata["vision.offTheShelf.rawPixelsExposed"] == "false")
        #expect(signals.first?.kind == .segmentation)
        #expect(signals.first?.observations.first?.bounds?.space == .normalizedTarget)
    }

    @Test
    func adapterIgnoresRecordedVisionMetadataWhilePipelineIsStubbed() async throws {
        let frame = HotLoopFrame(
            id: "frame-local-vision",
            traceID: "trace-local-vision",
            targetID: "target-visual-game",
            capturedAt: timestamp(10),
            sourceKind: .recorded,
            windowBounds: HotLoopRect(x: 0, y: 0, width: 390, height: 844, space: .screen),
            crop: nil,
            pixelSize: HotLoopSize(width: 390, height: 844, space: .window),
            metadata: RecordedOffTheShelfVisionMetadataCodec.encode(signals: [
                RecordedOffTheShelfVisionSignal(
                    id: "legacy-signal",
                    kind: .segmentation,
                    componentID: "legacy-component",
                    confidence: 0.88,
                    observations: [
                        RecordedOffTheShelfVisionObservation(
                            id: "legacy-observation",
                            label: "legacy",
                            bounds: HotLoopRect(x: 0.42, y: 0.58, width: 0.12, height: 0.08, space: .normalizedTarget),
                            confidence: 0.82
                        )
                    ]
                )
            ])
        )

        let signals = await OffTheShelfVisionPerceptionAdapter().perceive(frame: frame)
        let state = await OffTheShelfVisionWorldStateProjector().project(
            frame: frame,
            signals: signals,
            observedAt: timestamp(16)
        )

        #expect(signals.isEmpty)
        #expect(state.actionAffordances.isEmpty)
        #expect(state.metadata["vision.localEvidence"] == "false")
        #expect(state.metadata["reason"] == "cvPipelineRemovedPendingReplacement")
    }

    @Test
    func screenshotSegmentationStubRunnerReturnsStubEvidenceOnly() async throws {
        let runner = ScreenshotSegmentationStubRunner(now: fixedClock([100, 118]))
        let result = try await runner.run(
            ScreenshotSegmentationRequest(
                traceID: "trace-segmentation-stub",
                frameID: "frame-segmentation-stub",
                targetID: "target-segmentation-stub",
                cropID: "crop-search",
                cropImageFileURL: URL(fileURLWithPath: "/tmp/crop-search.png"),
                cropBounds: HotLoopRect(x: 0, y: 0, width: 320, height: 180, space: .window),
                pixelSize: HotLoopSize(width: 320, height: 180, space: .crop)
            )
        )
        let decoded = RecordedOffTheShelfVisionMetadataCodec.decode(from: result.metadata)
        let signal = try #require(decoded.first)

        #expect(result.model.id == "stubbed-screenshot-segmentation")
        #expect(signal.kind == .segmentation)
        #expect(signal.observations.isEmpty)
        #expect(signal.metadata["reason"] == "cvPipelineRemovedPendingReplacement")
        #expect(signal.metadata["rawPixelsRead"] == "false")
    }

    @Test
    func processBackedScreenshotSegmentationRuntimeIsStubbed() async throws {
        let backend = ProcessBackedScreenshotSegmentationBackend()
        let result = try await backend.segment(
            request: ScreenshotSegmentationRequest(
                traceID: "trace-sidecar-segmentation-stub",
                frameID: "frame-sidecar-segmentation-stub",
                targetID: "target-sidecar-segmentation-stub",
                cropID: "crop-play",
                cropBounds: HotLoopRect(x: 0, y: 0, width: 100, height: 100, space: .window),
                pixelSize: HotLoopSize(width: 100, height: 100, space: .crop)
            ),
            model: OffTheShelfVisionModelCatalog.stubbedScreenshotSegmentation
        )

        #expect(result.masks.isEmpty)
        #expect(result.preprocessMS == 0)
        #expect(result.modelInferenceMS == 0)
        #expect(result.metadata["reason"] == "cvPipelineRemovedPendingReplacement")
    }

    @Test
    func localUIUnderstandingSidecarFeedsObservationShape() async throws {
        let adapter = ProcessBackedLocalUIUnderstandingAdapter(
            sidecarRunner: StubbedLocalUIUnderstandingSidecarRunner(
                result: LocalJSONSidecarResult(
                    status: .completed,
                    outputData: Data("""
                    {"visibleText":{"title":"Music","result":"Sample Result"},"controls":[{"id":"search","label":"Search","kind":"searchField","frame":{"x":0.1,"y":0.1,"width":0.8,"height":0.08,"space":"normalizedTarget"},"confidence":0.86,"metadata":{"controlID":"search"}}],"formFields":[],"confidence":0.84,"metadata":{"understander":"fake-local-llm"}}
                    """.utf8),
                    metadata: ["sidecar.reason": "completed"]
                )
            )
        )
        let request = LocalUIUnderstandingRequest(
            traceID: "trace-ui-understanding",
            targetID: "music-app",
            imageFileURL: URL(fileURLWithPath: "/tmp/music-crop.png")
        )

        let result = try await adapter.understand(request)
        let observation = result.observation(for: request)

        #expect(observation.availableControls["search"] == true)
        #expect(observation.visibleText["result"] == "Sample Result")
        #expect(observation.metadata["directInputActionsAllowed"] == "false")
        #expect(observation.metadata["understander"] == "fake-local-llm")
    }

    private func timestamp(_ milliseconds: UInt64) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(milliseconds) / 1_000),
            monotonicUptimeNanoseconds: milliseconds * 1_000_000
        )
    }

    private func fixedClock(_ milliseconds: [UInt64]) -> @Sendable () -> RunTraceTimestamp {
        let clock = FixedVisionClock(milliseconds: milliseconds)
        return {
            clock.next()
        }
    }
}

private final class FixedVisionClock: @unchecked Sendable {
    private var milliseconds: [UInt64]
    private var index = 0

    init(milliseconds: [UInt64]) {
        self.milliseconds = milliseconds
    }

    func next() -> RunTraceTimestamp {
        let value = milliseconds[min(index, milliseconds.count - 1)]
        index += 1
        return RunTraceTimestamp(
            wallClock: Date(timeIntervalSince1970: Double(value) / 1_000),
            monotonicUptimeNanoseconds: value * 1_000_000
        )
    }
}

private struct StubbedLocalUIUnderstandingSidecarRunner: LocalJSONSidecarRunning {
    var result: LocalJSONSidecarResult

    func run(_ request: LocalJSONSidecarRequest) async -> LocalJSONSidecarResult {
        _ = request
        return result
    }
}
