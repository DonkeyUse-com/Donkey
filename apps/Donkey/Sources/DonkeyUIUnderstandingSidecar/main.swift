import AppKit
import DonkeyContracts
import DonkeyRuntime
import Foundation
import ImageIO
import UniformTypeIdentifiers
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
    var outputDirectory: String?
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

private struct DebugInspectionArtifactResponse: Codable {
    var status: String
    var runtimeID: String
    var modelID: String
    var artifacts: [DebugInspectionArtifact]
    var metadata: [String: String]
}

private struct DebugInspectionArtifact: Codable {
    var screenID: UInt32
    var screenshotPath: String
    var annotatedPath: String
    var framePath: String
    var elementCount: Int
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
            case "debugInspectAccessibility":
                output = try JSONEncoder().encode(try debugInspectAccessibility(request))
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

    private static func debugInspectAccessibility(_ request: SidecarRequest) throws -> DebugInspectionArtifactResponse {
        let outputDirectory = URL(
            fileURLWithPath: request.outputDirectory
                ?? request.artifactURL
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("donkey-debug-ui-inspection", isDirectory: true)
                    .path,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let minConfidence = Double(request.metadata?["minConfidence"] ?? "") ?? 0.25
        let startedAt = ProcessInfo.processInfo.systemUptime
        let results = try DebugUIAccessibilityInspectionService().inspect(
            scope: DebugUIInspectionScreenScope(rawValue: request.metadata?["screenScope"] ?? "") ?? .main,
            minConfidence: minConfidence,
            frontmostOnly: request.metadata?["frontmostOnly"] == "true",
            focusedOnly: request.metadata?["focusedOnly"] == "true",
            targetBundleIdentifiers: commaSeparatedList(request.metadata?["targetBundleIdentifiers"]),
            targetAppNames: commaSeparatedList(request.metadata?["targetAppNames"])
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let prefix = slug(request.traceID ?? request.targetID ?? "debug-ui")
        let artifacts = try results.map { result in
            let screenSlug = "\(prefix)-screen-\(result.snapshot.screenID)"
            let screenshotURL = outputDirectory.appendingPathComponent("\(screenSlug).png")
            let frameURL = outputDirectory.appendingPathComponent("\(screenSlug).frame.json")
            let annotatedURL = outputDirectory.appendingPathComponent("\(screenSlug).annotated.png")

            try result.snapshot.pngData.write(to: screenshotURL, options: .atomic)
            try encoder.encode(result.frame).write(to: frameURL, options: .atomic)
            let annotated = annotatedPNGData(
                screenshotPNGData: result.snapshot.pngData,
                frame: result.frame
            ) ?? result.snapshot.pngData
            try annotated.write(to: annotatedURL, options: .atomic)

            return DebugInspectionArtifact(
                screenID: result.snapshot.screenID,
                screenshotPath: screenshotURL.path,
                annotatedPath: annotatedURL.path,
                framePath: frameURL.path,
                elementCount: result.frame.elements.count,
                metadata: [
                    "snapshot.fingerprint": result.snapshot.fingerprint,
                    "pixel.width": String(result.snapshot.pixelSize.width),
                    "pixel.height": String(result.snapshot.pixelSize.height)
                ]
            )
        }
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        return DebugInspectionArtifactResponse(
            status: "ok",
            runtimeID: runtimeID,
            modelID: modelID,
            artifacts: artifacts,
            metadata: [
                "runtime.backend": "accessibility-native-ui-detection",
                "targetID": request.targetID ?? "",
                "traceID": request.traceID ?? "",
                "artifact.count": String(artifacts.count),
                "element.count": String(artifacts.map(\.elementCount).reduce(0, +)),
                "latency.debugInspectAccessibilityMS": String(format: "%.3f", elapsedMS),
                "visibleSystemA11yToggled": "false",
                "rawPixelsPersisted": "true"
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
        let imageData = try Data(contentsOf: imageURL)
        let pixelSize = request.pixelSize ?? imagePixelSize(from: imageData)
        let startedAt = ProcessInfo.processInfo.systemUptime
        let trace = LocalUIElementDetectionService().detect(
            LocalUIElementDetectionRequest(
                traceID: request.traceID ?? "ui-understanding-\(UUID().uuidString)",
                screenshotPNGData: imageData,
                pixelSize: pixelSize,
                minConfidence: Double(request.metadata?["minConfidence"] ?? "") ?? 0.25,
                metadata: [
                    "runtime.backend": "apple-vision-native-ui-detection",
                    "targetID": request.targetID ?? ""
                ].merging(request.metadata ?? [:]) { current, _ in current }
            )
        )
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        let result = LocalUIElementDetectionService().localUIUnderstandingResult(from: trace)
        return LocalUIUnderstandingResult(
            visibleText: result.visibleText,
            controls: result.controls,
            formFields: result.formFields,
            confidence: result.confidence,
            metadata: result.metadata.merging([
                "runtime.backend": "apple-vision-native-ui-detection",
                "recognition.count": String(trace.candidates.filter { $0.source == .ocr }.count),
                "latency.appleVisionTextMS": String(format: "%.3f", trace.metrics.latencyMS["nativeVisual.ocr"] ?? 0),
                "latency.localUIElementSidecarMS": String(format: "%.3f", elapsedMS),
                "directInputActionsAllowed": "false"
            ]) { current, _ in current }
        )
    }

    private static func imagePixelSize(from data: Data) -> HotLoopSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return HotLoopSize(width: 1, height: 1, space: .screen)
        }
        return HotLoopSize(width: width.doubleValue, height: height.doubleValue, space: .screen)
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

    private static func annotatedPNGData(
        screenshotPNGData: Data,
        frame: DebugUIInspectionFrame
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(screenshotPNGData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineWidth(2)
        for element in frame.elements {
            let rect = CGRect(
                x: element.bbox.x,
                y: Double(height) - element.bbox.y - element.bbox.height,
                width: element.bbox.width,
                height: element.bbox.height
            ).integral
            guard rect.width > 1, rect.height > 1 else { continue }

            let border = nsColor(hex: element.visualStyle.borderColor) ?? .systemBlue
            context.setStrokeColor(border.cgColor)
            context.setFillColor(border.withAlphaComponent(0.13).cgColor)
            context.fill(rect)
            context.stroke(rect)

            let label = annotationLabel(for: element)
            guard !label.isEmpty else { continue }
            let labelHeight: CGFloat = 18
            let labelWidth = min(
                CGFloat(width) - rect.minX - 4,
                max(44, CGFloat(label.count) * 6.7 + 10)
            )
            let labelY = min(CGFloat(height) - labelHeight - 2, max(2, rect.maxY - labelHeight))
            let labelRect = CGRect(
                x: rect.minX,
                y: labelY,
                width: labelWidth,
                height: labelHeight
            )
            context.setFillColor(border.withAlphaComponent(0.82).cgColor)
            context.fill(labelRect)

            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            (label as NSString).draw(
                in: labelRect.insetBy(dx: 4, dy: 2),
                withAttributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
                ]
            )
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let output = context.makeImage() else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func annotationLabel(for element: DebugUIElement) -> String {
        let sources = (element.metadata["localUIElement.sources"] ?? "")
            .split(separator: ",")
            .map(sourceBadge)
            .filter { !$0.isEmpty }
            .joined(separator: "+")
        let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = label.isEmpty ? element.type.rawValue : label
        let cappedTitle = title.count > 34 ? "\(title.prefix(31))..." : title
        return sources.isEmpty ? cappedTitle : "[\(sources)] \(cappedTitle)"
    }

    private static func sourceBadge(_ source: Substring) -> String {
        switch source {
        case "accessibility": return "AX"
        case "ocr": return "OCR"
        case "shape": return "SHAPE"
        case "template": return "TPL"
        case "color": return "COLOR"
        case "connectedComponent": return "CC"
        case "hoverProbe": return "HOVER"
        case "layout": return "LAYOUT"
        default: return String(source).uppercased()
        }
    }

    private static func nsColor(hex: String) -> NSColor? {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6,
              let value = Int(trimmed, radix: 16)
        else {
            return nil
        }
        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func slug(_ value: String) -> String {
        let slug = value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(8)
            .joined(separator: "-")
        return slug.isEmpty ? "debug-ui" : slug
    }

    private static func commaSeparatedList(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
