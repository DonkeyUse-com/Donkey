import CoreGraphics
import DonkeyContracts
import Foundation
import ImageIO
@preconcurrency import Vision

public struct LocalUIElementNativeVisualDetector: Sendable {
    public var maxAnalysisDimension: Int

    public init(maxAnalysisDimension: Int = 900) {
        self.maxAnalysisDimension = max(120, maxAnalysisDimension)
    }

    public func candidates(
        fromPNGData data: Data?,
        pixelSize: HotLoopSize
    ) -> (candidates: [LocalUIElementCandidate], latencyMS: [String: Double], metadata: [String: String]) {
        guard let data,
              !data.isEmpty,
              let image = Self.image(from: data)
        else {
            return ([], [:], ["nativeVisual.status": "missingImage"])
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let shapeStartedAt = ProcessInfo.processInfo.systemUptime
        let shapeCandidates = shapeCandidates(from: image, pixelSize: pixelSize)
        let shapeMS = (ProcessInfo.processInfo.systemUptime - shapeStartedAt) * 1_000

        let ocrStartedAt = ProcessInfo.processInfo.systemUptime
        let ocrImage = Self.inspectionImage(from: image, maxDimension: maxAnalysisDimension)
        let ocrResult = textCandidates(from: ocrImage, pixelSize: pixelSize)
        let ocrMS = (ProcessInfo.processInfo.systemUptime - ocrStartedAt) * 1_000

        let totalMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        return (
            shapeCandidates + ocrResult.candidates,
            [
                "nativeVisual.total": totalMS,
                "nativeVisual.shape": shapeMS,
                "nativeVisual.ocr": ocrMS
            ],
            [
                "nativeVisual.status": "completed",
                "nativeVisual.ocr.status": ocrResult.error == nil ? "completed" : "failed",
                "nativeVisual.ocr.error": ocrResult.error ?? "",
                "nativeVisual.ocr.count": String(ocrResult.candidates.count),
                "nativeVisual.shape.count": String(shapeCandidates.count)
            ]
        )
    }

    private func textCandidates(
        from image: CGImage,
        pixelSize: HotLoopSize
    ) -> (candidates: [LocalUIElementCandidate], error: String?) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return ([], String(describing: error))
        }

        return ((request.results ?? []).enumerated().compactMap { index, observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let box = observation.boundingBox
            let bounds = HotLoopRect(
                x: box.minX * pixelSize.width,
                y: (1 - box.maxY) * pixelSize.height,
                width: box.width * pixelSize.width,
                height: box.height * pixelSize.height,
                space: pixelSize.space
            )
            guard bounds.hasPositiveArea else { return nil }

            return LocalUIElementCandidate(
                id: "ocr-\(index)-\(Self.slug(text))",
                source: .ocr,
                signalKind: .text,
                label: text,
                bounds: bounds,
                confidence: Double(candidate.confidence),
                metadata: [
                    "detector": "apple-vision-text",
                    "text.length": String(text.count)
                ]
            )
        }, nil)
    }

    private func shapeCandidates(
        from image: CGImage,
        pixelSize: HotLoopSize
    ) -> [LocalUIElementCandidate] {
        guard let raster = RasterizedImage(image: image, maxDimension: maxAnalysisDimension) else {
            return []
        }

        let components = connectedComponents(in: raster)
        let scaleX = pixelSize.width / Double(raster.width)
        let scaleY = pixelSize.height / Double(raster.height)
        var candidates: [LocalUIElementCandidate] = []

        for (index, component) in components.prefix(180).enumerated() {
            guard let candidate = candidate(
                for: component,
                index: index,
                scaleX: scaleX,
                scaleY: scaleY,
                outputSpace: pixelSize.space,
                rasterWidth: raster.width,
                rasterHeight: raster.height
            ) else {
                continue
            }
            candidates.append(candidate)
        }

        return candidates
    }

    private func candidate(
        for component: PixelComponent,
        index: Int,
        scaleX: Double,
        scaleY: Double,
        outputSpace: HotLoopCoordinateSpace,
        rasterWidth: Int,
        rasterHeight: Int
    ) -> LocalUIElementCandidate? {
        let width = Double(component.maxX - component.minX + 1)
        let height = Double(component.maxY - component.minY + 1)
        guard width >= 6, height >= 6 else { return nil }
        guard width <= Double(rasterWidth) * 0.76,
              height <= Double(rasterHeight) * 0.40
        else {
            return nil
        }

        let area = width * height
        let fillRatio = Double(component.pixelCount) / max(1, area)
        let aspect = width / max(1, height)
        let bounds = HotLoopRect(
            x: Double(component.minX) * scaleX,
            y: Double(component.minY) * scaleY,
            width: width * scaleX,
            height: height * scaleY,
            space: outputSpace
        )
        let average = component.averageColor

        if let trafficLight = trafficLightCandidate(
            component: component,
            bounds: bounds,
            width: width,
            height: height,
            fillRatio: fillRatio,
            average: average
        ) {
            return trafficLight
        }

        guard component.minY > 2 else {
            return nil
        }

        if isBlue(average), width >= 24, height <= 34 {
            return LocalUIElementCandidate(
                id: "color-link-\(index)",
                source: .color,
                signalKind: .colorCluster,
                typeHint: .link,
                label: "link",
                bounds: bounds,
                confidence: min(0.78, 0.45 + fillRatio),
                metadata: [
                    "detector": "native-color-cluster",
                    "color.hint": "blue",
                    "classification.reason": "blueControlOrLink"
                ]
            )
        }

        if width >= 10, width <= 34, height >= 10, height <= 34, aspect >= 0.65, aspect <= 1.45 {
            return LocalUIElementCandidate(
                id: "shape-checkbox-\(index)",
                source: .shape,
                signalKind: .rectangle,
                typeHint: .checkbox,
                bounds: bounds,
                confidence: 0.64,
                metadata: [
                    "detector": "native-connected-component",
                    "shape": "square",
                    "classification.reason": "smallSquareControl"
                ]
            )
        }

        if width >= 26, height >= 12, height <= 40, aspect >= 1.7, aspect <= 3.4, fillRatio >= 0.30 {
            return LocalUIElementCandidate(
                id: "shape-toggle-\(index)",
                source: .shape,
                signalKind: .roundedRectangle,
                typeHint: .toggle,
                bounds: bounds,
                confidence: 0.66,
                metadata: [
                    "detector": "native-connected-component",
                    "shape": "toggleLike",
                    "classification.reason": "pillControlCluster"
                ]
            )
        }

        guard width >= 34, height >= 16, height <= 76 else {
            if width >= 10, width <= 52, height >= 10, height <= 52 {
                return LocalUIElementCandidate(
                    id: "component-icon-\(index)",
                    source: .connectedComponent,
                    signalKind: .connectedComponent,
                    typeHint: .toolbarIcon,
                    bounds: bounds,
                    confidence: 0.42,
                    metadata: [
                        "detector": "native-connected-component",
                        "classification.reason": "smallIconCluster"
                    ]
                )
            }
            return nil
        }

        let rounded = fillRatio > 0.35 || aspect > 2.6
        let typeHint: DebugUIElementType = aspect > 3.6 && width >= 140 ? .input : .button
        return LocalUIElementCandidate(
            id: "shape-control-\(index)",
            source: .shape,
            signalKind: rounded ? .roundedRectangle : .rectangle,
            typeHint: typeHint,
            bounds: bounds,
            confidence: rounded ? 0.62 : 0.56,
            metadata: [
                "detector": "native-connected-component",
                "shape": rounded ? "roundedRectangle" : "rectangle",
                "shape.fillRatio": String(format: "%.3f", fillRatio),
                "classification.reason": typeHint == .input ? "wideRoundedControl" : "rectangularControl"
            ]
        )
    }

    private func trafficLightCandidate(
        component: PixelComponent,
        bounds: HotLoopRect,
        width: Double,
        height: Double,
        fillRatio: Double,
        average: AverageColor
    ) -> LocalUIElementCandidate? {
        guard width >= 8, width <= 26,
              height >= 8, height <= 26,
              width / max(1, height) >= 0.75,
              width / max(1, height) <= 1.35,
              fillRatio >= 0.45
        else {
            return nil
        }

        let label: String
        if average.red > 160, average.green < 120, average.blue < 120 {
            label = "close"
        } else if average.red > 150, average.green > 115, average.blue < 80 {
            label = "minimize"
        } else if average.green > 130, average.red < 130, average.blue < 130 {
            label = "zoom"
        } else {
            return nil
        }

        return LocalUIElementCandidate(
            id: "template-window-control-\(label)-\(component.minX)-\(component.minY)",
            source: .template,
            signalKind: .iconTemplate,
            typeHint: .windowControl,
            label: label,
            bounds: bounds,
            confidence: 0.86,
            metadata: [
                "detector": "native-template",
                "templateID": "macos-traffic-light-\(label)",
                "classification.reason": "trafficLightColorCluster"
            ]
        )
    }

    private func connectedComponents(in raster: RasterizedImage) -> [PixelComponent] {
        var visited = [Bool](repeating: false, count: raster.width * raster.height)
        var components: [PixelComponent] = []
        let imageArea = raster.width * raster.height

        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let index = y * raster.width + x
                guard !visited[index], raster.isInterestingPixel(x: x, y: y) else {
                    visited[index] = true
                    continue
                }

                let component = floodFill(
                    startX: x,
                    startY: y,
                    raster: raster,
                    visited: &visited
                )
                guard component.pixelCount >= 18,
                      component.pixelCount <= imageArea / 3
                else {
                    continue
                }
                components.append(component)
            }
        }

        return components.sorted { lhs, rhs in
            if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
            if lhs.minX != rhs.minX { return lhs.minX < rhs.minX }
            return lhs.pixelCount > rhs.pixelCount
        }
    }

    private func floodFill(
        startX: Int,
        startY: Int,
        raster: RasterizedImage,
        visited: inout [Bool]
    ) -> PixelComponent {
        var stack = [(startX, startY)]
        var component = PixelComponent(minX: startX, minY: startY, maxX: startX, maxY: startY)
        visited[startY * raster.width + startX] = true

        while let (x, y) = stack.popLast() {
            component.add(pixel: raster.pixel(x: x, y: y), x: x, y: y)

            for ny in max(0, y - 1)...min(raster.height - 1, y + 1) {
                for nx in max(0, x - 1)...min(raster.width - 1, x + 1) {
                    let neighborIndex = ny * raster.width + nx
                    guard !visited[neighborIndex] else { continue }
                    visited[neighborIndex] = true
                    guard raster.isInterestingPixel(x: nx, y: ny) else { continue }
                    stack.append((nx, ny))
                }
            }
        }

        return component
    }

    private static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func inspectionImage(from image: CGImage, maxDimension: Int) -> CGImage {
        let longestEdge = max(image.width, image.height)
        guard longestEdge > maxDimension else {
            return image
        }

        let scale = Double(maxDimension) / Double(longestEdge)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
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
            return image
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private func isBlue(_ color: AverageColor) -> Bool {
        color.blue > 130 && color.blue > color.red * 1.25 && color.blue > color.green * 1.05
    }

    private static func slug(_ value: String) -> String {
        value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(4)
            .joined(separator: "-")
    }
}

private struct RasterizedImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init?(image: CGImage, maxDimension: Int) {
        let longestEdge = max(image.width, image.height)
        let scale = longestEdge > maxDimension ? Double(maxDimension) / Double(longestEdge) : 1
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let offset = (y * width + x) * 4
        return Pixel(
            red: pixels[offset],
            green: pixels[offset + 1],
            blue: pixels[offset + 2],
            alpha: pixels[offset + 3]
        )
    }

    func isInterestingPixel(x: Int, y: Int) -> Bool {
        let pixel = pixel(x: x, y: y)
        guard pixel.alpha > 28 else { return false }
        let luminance = pixel.luminance
        return luminance > 88 || pixel.saturation > 0.28
    }
}

private struct Pixel {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    var luminance: Double {
        (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue))
    }

    var saturation: Double {
        let maxChannel = Double(max(red, max(green, blue)))
        let minChannel = Double(min(red, min(green, blue)))
        guard maxChannel > 0 else { return 0 }
        return (maxChannel - minChannel) / maxChannel
    }
}

private struct AverageColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

private struct PixelComponent {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int
    var pixelCount: Int = 0
    private var redTotal: Int = 0
    private var greenTotal: Int = 0
    private var blueTotal: Int = 0

    init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    mutating func add(pixel: Pixel, x: Int, y: Int) {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
        pixelCount += 1
        redTotal += Int(pixel.red)
        greenTotal += Int(pixel.green)
        blueTotal += Int(pixel.blue)
    }

    var averageColor: AverageColor {
        guard pixelCount > 0 else {
            return AverageColor(red: 0, green: 0, blue: 0)
        }
        return AverageColor(
            red: Double(redTotal) / Double(pixelCount),
            green: Double(greenTotal) / Double(pixelCount),
            blue: Double(blueTotal) / Double(pixelCount)
        )
    }
}
