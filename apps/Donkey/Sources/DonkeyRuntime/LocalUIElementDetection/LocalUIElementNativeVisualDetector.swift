import DonkeyContracts
import Foundation

public struct LocalUIElementNativeVisualDetector: Sendable {
    public init(maxAnalysisDimension: Int = 900) {}

    public func candidates(
        fromPNGData data: Data?,
        imagePath: String? = nil,
        pixelSize: HotLoopSize
    ) -> (candidates: [LocalUIElementCandidate], latencyMS: [String: Double], metadata: [String: String]) {
        _ = data
        _ = imagePath
        _ = pixelSize

        return (
            [],
            [:],
            [
                "nativeVisual.status": "stubbed",
                "nativeVisual.reason": "cvPipelineRemovedPendingReplacement",
                "nativeVisual.rawPixelsRead": "false"
            ]
        )
    }
}
