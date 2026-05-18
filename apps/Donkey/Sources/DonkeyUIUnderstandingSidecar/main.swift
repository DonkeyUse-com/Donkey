import AppKit
import DonkeyContracts
import DonkeyRuntime
import Foundation
@preconcurrency import Vision

private struct SidecarRequest: Codable {
    var operation: String?
    var protocolVersion: String?
    var runtimeID: String?
    var runtimeVersion: String?
    var modelID: String?
    var cacheDirectory: String?
    var traceID: String?
    var targetID: String?
    var imagePath: String?
    var artifactURL: String?
    var cropBounds: HotLoopRect?
    var pixelSize: HotLoopSize?
    var metadata: [String: String]?
}

private struct HealthResponse: Codable {
    var status: String
    var runtimeID: String
    var runtimeVersion: String
    var modelID: String
    var protocolVersion: String
    var metadata: [String: String]
}

private struct PreparationResponse: Codable {
    var status: String
    var runtimeID: String
    var modelID: String
    var cacheDirectory: String?
    var metadata: [String: String]
}

private struct ErrorResponse: Codable {
    var status: String
    var runtimeID: String
    var modelID: String
    var metadata: [String: String]
}

private let runtimeID = ProcessInfo.processInfo.environment["DONKEY_RUNTIME_ID"] ?? "ui-understander"
private let runtimeVersion = ProcessInfo.processInfo.environment["DONKEY_RUNTIME_VERSION"] ?? "0.3.0-runner"
private let modelID = ProcessInfo.processInfo.environment["DONKEY_MODEL_ID"] ?? "apple-vision-text-recognition"

@main
struct DonkeyUIUnderstandingSidecar {
    static func main() {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(SidecarRequest.self, from: input.isEmpty ? Data("{}".utf8) : input)
            let output: Data
            switch request.operation {
            case "healthCheck":
                output = try JSONEncoder().encode(health())
            case "prepareModelWeights":
                output = try JSONEncoder().encode(prepared(cacheDirectory: request.cacheDirectory))
            default:
                output = try JSONEncoder().encode(try understand(request))
            }
            FileHandle.standardOutput.write(output)
        } catch {
            let payload = ErrorResponse(
                status: "error",
                runtimeID: runtimeID,
                modelID: modelID,
                metadata: [
                    "runtime.backend": "apple-vision",
                    "reason": "uiUnderstandingSidecarFailed",
                    "detail": String(describing: error)
                ]
            )
            if let output = try? JSONEncoder().encode(payload) {
                FileHandle.standardOutput.write(output)
            }
        }
    }

    private static func health() -> HealthResponse {
        HealthResponse(
            status: "ok",
            runtimeID: runtimeID,
            runtimeVersion: runtimeVersion,
            modelID: modelID,
            protocolVersion: "v1",
            metadata: [
                "runtime.backend": "apple-vision",
                "modelWeights.status": "notRequired",
                "modelWeights.provider": "system"
            ]
        )
    }

    private static func prepared(cacheDirectory: String?) -> PreparationResponse {
        PreparationResponse(
            status: "ok",
            runtimeID: runtimeID,
            modelID: modelID,
            cacheDirectory: cacheDirectory,
            metadata: [
                "runtime.backend": "apple-vision",
                "modelWeights.status": "notRequired",
                "modelWeights.provider": "system"
            ]
        )
    }

    private static func understand(_ request: SidecarRequest) throws -> LocalUIUnderstandingResult {
        guard let imagePath = request.imagePath, !imagePath.isEmpty else {
            return LocalUIUnderstandingResult(
                confidence: 0,
                metadata: [
                    "runtime.backend": "apple-vision",
                    "reason": "missingImagePath"
                ]
            )
        }

        let imageURL = URL(fileURLWithPath: imagePath)
        let startedAt = ProcessInfo.processInfo.systemUptime
        let observations = try recognizedText(in: imageURL)
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        var visibleText: [String: String] = [:]
        var controls: [LocalUIUnderstandingControl] = []
        var totalConfidence = 0.0

        for (index, item) in observations.enumerated() {
            let id = "vision-text-\(index)"
            visibleText[id] = item.text
            totalConfidence += item.confidence
            controls.append(
                LocalUIUnderstandingControl(
                    id: id,
                    label: item.text,
                    kind: .unknown,
                    frame: item.frame,
                    confidence: item.confidence,
                    metadata: [
                        "controlID": id,
                        "source": "apple-vision-text-recognition"
                    ]
                )
            )
        }

        let averageConfidence = observations.isEmpty ? 0 : totalConfidence / Double(observations.count)
        return LocalUIUnderstandingResult(
            visibleText: visibleText,
            controls: controls,
            formFields: [],
            confidence: averageConfidence,
            metadata: [
                "runtime.backend": "apple-vision",
                "recognition.count": String(observations.count),
                "latency.appleVisionTextMS": String(format: "%.3f", elapsedMS),
                "directInputActionsAllowed": "false"
            ]
        )
    }

    private static func recognizedText(in imageURL: URL) throws -> [(text: String, confidence: Double, frame: HotLoopRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(url: imageURL)
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let box = observation.boundingBox
            return (
                text: text,
                confidence: Double(candidate.confidence),
                frame: HotLoopRect(
                    x: box.minX,
                    y: 1 - box.maxY,
                    width: box.width,
                    height: box.height,
                    space: .normalizedTarget
                )
            )
        }
    }
}
