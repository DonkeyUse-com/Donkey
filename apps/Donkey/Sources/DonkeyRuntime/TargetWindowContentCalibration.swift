import DonkeyContracts
import Foundation

public enum TargetWindowContentCalibrationMode: Equatable, Sendable {
    case fullWindow
    case centeredAspectFit(aspectRatioWidthOverHeight: Double)
}

public struct TargetWindowContentCalibrationRequest: Equatable, Sendable {
    public var mode: TargetWindowContentCalibrationMode
    public var minimumInset: Double

    public init(
        mode: TargetWindowContentCalibrationMode,
        minimumInset: Double = 0
    ) {
        self.mode = mode
        self.minimumInset = max(0, minimumInset)
    }

    public static let iPhonePortrait = TargetWindowContentCalibrationRequest(
        mode: .centeredAspectFit(aspectRatioWidthOverHeight: 9.0 / 19.5)
    )
}

public struct TargetWindowContentCalibrationResult: Equatable, Sendable {
    public var crop: HotLoopCrop
    public var metadata: [String: String]

    public init(crop: HotLoopCrop, metadata: [String: String]) {
        self.crop = crop
        self.metadata = metadata
    }
}

public struct TargetWindowContentCalibrator: Sendable {
    public init() {}

    public func calibrate(
        target: MacWindowTargetCandidate,
        capturedImageSize: HotLoopSize,
        request: TargetWindowContentCalibrationRequest
    ) -> TargetWindowContentCalibrationResult? {
        guard capturedImageSize.hasPositiveArea else { return nil }

        let availableWidth = max(0, capturedImageSize.width - request.minimumInset * 2)
        let availableHeight = max(0, capturedImageSize.height - request.minimumInset * 2)
        guard availableWidth > 0, availableHeight > 0 else { return nil }

        let bounds: HotLoopRect
        var metadata = [
            "contentCalibration.enabled": "true",
            "contentCalibration.minimumInset": String(request.minimumInset),
            "contentCalibration.target.isIPhoneMirroring": String(target.isIPhoneMirroring)
        ]

        switch request.mode {
        case .fullWindow:
            bounds = HotLoopRect(
                x: 0,
                y: 0,
                width: capturedImageSize.width,
                height: capturedImageSize.height,
                space: .window
            )
            metadata["contentCalibration.mode"] = "fullWindow"

        case .centeredAspectFit(let aspectRatio):
            guard aspectRatio > 0 else { return nil }

            let availableRatio = availableWidth / availableHeight
            let contentWidth: Double
            let contentHeight: Double
            if availableRatio > aspectRatio {
                contentHeight = availableHeight
                contentWidth = availableHeight * aspectRatio
            } else {
                contentWidth = availableWidth
                contentHeight = availableWidth / aspectRatio
            }

            bounds = HotLoopRect(
                x: request.minimumInset + (availableWidth - contentWidth) / 2,
                y: request.minimumInset + (availableHeight - contentHeight) / 2,
                width: contentWidth,
                height: contentHeight,
                space: .window
            )
            metadata["contentCalibration.mode"] = "centeredAspectFit"
            metadata["contentCalibration.aspectRatioWidthOverHeight"] = String(aspectRatio)
        }

        metadata["contentCalibration.bounds.x"] = String(bounds.origin.x)
        metadata["contentCalibration.bounds.y"] = String(bounds.origin.y)
        metadata["contentCalibration.bounds.width"] = String(bounds.size.width)
        metadata["contentCalibration.bounds.height"] = String(bounds.size.height)

        return TargetWindowContentCalibrationResult(
            crop: HotLoopCrop(
                id: "target-window-content",
                bounds: bounds,
                outputSize: HotLoopSize(
                    width: bounds.size.width,
                    height: bounds.size.height,
                    space: .crop
                )
            ),
            metadata: metadata
        )
    }
}
