import DonkeyContracts
import Foundation

public enum OffTheShelfVisionSignalKind: String, Codable, Equatable, Sendable {
    case detector
    case template
    case ocr
    case segmentation
}

public enum OffTheShelfVisionInputSource: String, Codable, Equatable, Sendable {
    case screenshot
    case crop
    case recorded
}

public struct OffTheShelfVisionModelCandidate: Codable, Equatable, Sendable {
    public var id: String
    public var family: String
    public var modelName: String
    public var signalKind: OffTheShelfVisionSignalKind
    public var preferredInputSource: OffTheShelfVisionInputSource
    public var componentID: String
    public var docsURL: URL
    public var lastVerifiedAt: String
    public var metadata: [String: String]

    public init(
        id: String,
        family: String,
        modelName: String,
        signalKind: OffTheShelfVisionSignalKind,
        preferredInputSource: OffTheShelfVisionInputSource,
        componentID: String,
        docsURL: URL,
        lastVerifiedAt: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.family = family
        self.modelName = modelName
        self.signalKind = signalKind
        self.preferredInputSource = preferredInputSource
        self.componentID = componentID
        self.docsURL = docsURL
        self.lastVerifiedAt = lastVerifiedAt
        self.metadata = metadata
    }
}

public enum OffTheShelfVisionModelCatalog {
    public static let stubbedScreenshotSegmentation = OffTheShelfVisionModelCandidate(
        id: "stubbed-screenshot-segmentation",
        family: "stub",
        modelName: "stubbed",
        signalKind: .segmentation,
        preferredInputSource: .recorded,
        componentID: "screenshot-segmentation-stub",
        docsURL: URL(string: "https://github.com/dle87/donkey")!,
        lastVerifiedAt: "2026-05-26",
        metadata: [
            "provider": "none",
            "task": "stub",
            "reason": "cvPipelineRemovedPendingReplacement",
            "liveDefault": "false",
            "rawPixelsRead": "false"
        ]
    )

    public static var screenshotSegmentationCandidates: [OffTheShelfVisionModelCandidate] {
        []
    }

    public static func defaultCandidate(
        signalKind: OffTheShelfVisionSignalKind,
        inputSource: OffTheShelfVisionInputSource
    ) -> OffTheShelfVisionModelCandidate? {
        _ = signalKind
        _ = inputSource
        return nil
    }
}

public struct RecordedOffTheShelfVisionObservation: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var bounds: HotLoopRect?
    public var confidence: Double
    public var metadata: [String: String]

    public init(
        id: String,
        label: String,
        bounds: HotLoopRect? = nil,
        confidence: Double,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.label = label
        self.bounds = bounds
        self.confidence = Self.clamped(confidence)
        self.metadata = metadata
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct RecordedOffTheShelfVisionSignal: Codable, Equatable, Sendable {
    public var id: String
    public var kind: OffTheShelfVisionSignalKind
    public var componentID: String
    public var modelID: String?
    public var cropID: String?
    public var confidence: Double
    public var observations: [RecordedOffTheShelfVisionObservation]
    public var preprocessMS: Double
    public var modelInferenceMS: Double
    public var adapterOverheadMS: Double
    public var metadata: [String: String]

    public init(
        id: String,
        kind: OffTheShelfVisionSignalKind,
        componentID: String,
        modelID: String? = nil,
        cropID: String? = nil,
        confidence: Double,
        observations: [RecordedOffTheShelfVisionObservation],
        preprocessMS: Double = 0,
        modelInferenceMS: Double = 0,
        adapterOverheadMS: Double = 1,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.componentID = componentID
        self.modelID = modelID
        self.cropID = cropID
        self.confidence = Self.clamped(confidence)
        self.observations = observations
        self.preprocessMS = max(0, preprocessMS)
        self.modelInferenceMS = max(0, modelInferenceMS)
        self.adapterOverheadMS = max(0, adapterOverheadMS)
        self.metadata = metadata
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public enum RecordedOffTheShelfVisionMetadataCodec {
    public static func encode(signals: [RecordedOffTheShelfVisionSignal]) -> [String: String] {
        var metadata = [
            "vision.offTheShelf.encoded": "true",
            "vision.offTheShelf.rawPixelsExposed": "false",
            "vision.offTheShelf.signal.count": String(signals.count)
        ]

        for (signalIndex, signal) in signals.enumerated() {
            let prefix = "vision.offTheShelf.signal.\(signalIndex)."
            metadata[prefix + "id"] = signal.id
            metadata[prefix + "kind"] = signal.kind.rawValue
            metadata[prefix + "componentID"] = signal.componentID
            metadata[prefix + "modelID"] = signal.modelID ?? ""
            metadata[prefix + "cropID"] = signal.cropID ?? ""
            metadata[prefix + "confidence"] = String(signal.confidence)
            metadata[prefix + "latency.preprocessMS"] = String(signal.preprocessMS)
            metadata[prefix + "latency.modelInferenceMS"] = String(signal.modelInferenceMS)
            metadata[prefix + "latency.adapterOverheadMS"] = String(signal.adapterOverheadMS)
            metadata[prefix + "observation.count"] = String(signal.observations.count)
            for (key, value) in signal.metadata {
                metadata[prefix + "metadata.\(key)"] = value
            }

            for (observationIndex, observation) in signal.observations.enumerated() {
                let observationPrefix = prefix + "observation.\(observationIndex)."
                metadata[observationPrefix + "id"] = observation.id
                metadata[observationPrefix + "label"] = observation.label
                metadata[observationPrefix + "confidence"] = String(observation.confidence)
                if let bounds = observation.bounds {
                    metadata[observationPrefix + "bounds.x"] = String(bounds.origin.x)
                    metadata[observationPrefix + "bounds.y"] = String(bounds.origin.y)
                    metadata[observationPrefix + "bounds.width"] = String(bounds.size.width)
                    metadata[observationPrefix + "bounds.height"] = String(bounds.size.height)
                    metadata[observationPrefix + "bounds.space"] = bounds.space.rawValue
                }
                for (key, value) in observation.metadata {
                    metadata[observationPrefix + "metadata.\(key)"] = value
                }
            }
        }

        return metadata
    }

    public static func decode(from metadata: [String: String]) -> [RecordedOffTheShelfVisionSignal] {
        let count = Int(metadata["vision.offTheShelf.signal.count"] ?? "") ?? 0
        guard count > 0 else { return [] }

        return (0..<count).compactMap { index -> RecordedOffTheShelfVisionSignal? in
            let prefix = "vision.offTheShelf.signal.\(index)."
            guard let id = nonEmpty(metadata[prefix + "id"]),
                  let kind = OffTheShelfVisionSignalKind(rawValue: metadata[prefix + "kind"] ?? ""),
                  let componentID = nonEmpty(metadata[prefix + "componentID"])
            else {
                return nil
            }

            let observationCount = Int(metadata[prefix + "observation.count"] ?? "") ?? 0
            let observations = (0..<observationCount).compactMap { observationIndex -> RecordedOffTheShelfVisionObservation? in
                let observationPrefix = prefix + "observation.\(observationIndex)."
                guard let observationID = nonEmpty(metadata[observationPrefix + "id"]),
                      let label = nonEmpty(metadata[observationPrefix + "label"])
                else {
                    return nil
                }

                return RecordedOffTheShelfVisionObservation(
                    id: observationID,
                    label: label,
                    bounds: decodeBounds(prefix: observationPrefix + "bounds.", metadata: metadata),
                    confidence: Double(metadata[observationPrefix + "confidence"] ?? "") ?? 0,
                    metadata: prefixedMetadata(
                        prefix: observationPrefix + "metadata.",
                        metadata: metadata
                    )
                )
            }

            return RecordedOffTheShelfVisionSignal(
                id: id,
                kind: kind,
                componentID: componentID,
                modelID: nonEmpty(metadata[prefix + "modelID"]),
                cropID: nonEmpty(metadata[prefix + "cropID"]),
                confidence: Double(metadata[prefix + "confidence"] ?? "") ?? 0,
                observations: observations,
                preprocessMS: Double(metadata[prefix + "latency.preprocessMS"] ?? "") ?? 0,
                modelInferenceMS: Double(metadata[prefix + "latency.modelInferenceMS"] ?? "") ?? 0,
                adapterOverheadMS: Double(metadata[prefix + "latency.adapterOverheadMS"] ?? "") ?? 1,
                metadata: prefixedMetadata(prefix: prefix + "metadata.", metadata: metadata)
            )
        }
    }

    private static func decodeBounds(
        prefix: String,
        metadata: [String: String]
    ) -> HotLoopRect? {
        guard let x = Double(metadata[prefix + "x"] ?? ""),
              let y = Double(metadata[prefix + "y"] ?? ""),
              let width = Double(metadata[prefix + "width"] ?? ""),
              let height = Double(metadata[prefix + "height"] ?? ""),
              let space = HotLoopCoordinateSpace(rawValue: metadata[prefix + "space"] ?? "")
        else {
            return nil
        }

        return HotLoopRect(x: x, y: y, width: width, height: height, space: space)
    }

    private static func prefixedMetadata(
        prefix: String,
        metadata: [String: String]
    ) -> [String: String] {
        metadata.reduce(into: [:]) { result, item in
            guard item.key.hasPrefix(prefix) else { return }
            let key = String(item.key.dropFirst(prefix.count))
            guard !key.isEmpty else { return }
            result[key] = item.value
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public struct OffTheShelfVisionPerceptionAdapter: DryRunPerceptionAdapting {
    public var adapterName: String

    public init(adapterName: String = "off-the-shelf-vision-perception") {
        self.adapterName = adapterName
    }

    public func perceive(frame: HotLoopFrame) async -> [HotLoopPerceptionSignal] {
        _ = frame
        return []
    }
}

public struct OffTheShelfVisionWorldStateProjector: DryRunWorldStateProjecting {
    public var staleSignalThresholdMS: Double

    public init(staleSignalThresholdMS: Double = 250) {
        self.staleSignalThresholdMS = staleSignalThresholdMS
    }

    public func project(
        frame: HotLoopFrame,
        signals: [HotLoopPerceptionSignal],
        observedAt: RunTraceTimestamp
    ) async -> HotLoopWorldState {
        HotLoopWorldState.build(
            id: "state-\(frame.id)",
            frame: frame,
            signals: signals,
            observedAt: observedAt,
            staleThresholdMS: staleSignalThresholdMS,
            actionAffordances: [],
            metadata: [
                "projector": "off-the-shelf-vision-world-state-projector-stub",
                "vision.localEvidence": "false",
                "rawPixelsExposed": "false",
                "reason": "cvPipelineRemovedPendingReplacement"
            ]
        )
    }
}
