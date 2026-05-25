@preconcurrency import AppKit
import CoreGraphics
import CryptoKit
import DonkeyContracts
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct DebugUIOverlayConfiguration: Equatable, Sendable {
    public var enabled: Bool
    public var provider: DebugUIInspectionProvider
    public var cadenceSeconds: TimeInterval
    public var screenScope: DebugUIInspectionScreenScope
    public var minConfidence: Double

    public init(
        enabled: Bool = false,
        provider: DebugUIInspectionProvider = .openai,
        cadenceSeconds: TimeInterval = 1.0,
        screenScope: DebugUIInspectionScreenScope = .main,
        minConfidence: Double = 0.25
    ) {
        self.enabled = enabled
        self.provider = provider
        self.cadenceSeconds = min(max(cadenceSeconds, 0.25), 10.0)
        self.screenScope = screenScope
        self.minConfidence = min(max(minConfidence, 0), 1)
    }

    public static let disabled = DebugUIOverlayConfiguration(enabled: false)

    public static func defaultConfigURL(fileManager: FileManager = .default) -> URL? {
        guard let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }

        return applicationSupport
            .appendingPathComponent("Donkey", isDirectory: true)
            .appendingPathComponent("dev-overlay.json", isDirectory: false)
    }

    public static func load(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> DebugUIOverlayConfiguration {
        let urls: [URL]
        if let fileURL {
            urls = [fileURL]
        } else {
            urls = candidateConfigURLs(fileManager: fileManager)
        }

        guard let raw = urls.lazy.compactMap({ url -> RawDebugUIOverlayConfiguration? in
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url)
            else {
                return nil
            }
            return try? JSONDecoder().decode(RawDebugUIOverlayConfiguration.self, from: data)
        }).first else {
            return .disabled
        }

        return DebugUIOverlayConfiguration(
            enabled: raw.enabled ?? false,
            provider: raw.provider.flatMap(DebugUIInspectionProvider.init(rawValue:)) ?? .openai,
            cadenceSeconds: raw.cadenceSeconds ?? 1.0,
            screenScope: raw.screenScope.flatMap(DebugUIInspectionScreenScope.init(rawValue:)) ?? .main,
            minConfidence: raw.minConfidence ?? 0.25
        )
    }

    public static func candidateConfigURLs(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> [URL] {
        var urls: [URL] = []
        if let defaultConfigURL = defaultConfigURL(fileManager: fileManager) {
            urls.append(defaultConfigURL)
        }

        #if DEBUG
        if let value = environment["DONKEY_DEV_OVERLAY_CONFIG"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            urls.append(URL(fileURLWithPath: value))
        }
        if let value = bundle.object(forInfoDictionaryKey: "DonkeyDevOverlayConfigPath") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            urls.append(URL(fileURLWithPath: value))
        }
        urls.append(contentsOf: repoConfigCandidates(fileManager: fileManager))
        #endif

        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    #if DEBUG
    private static func repoConfigCandidates(fileManager: FileManager) -> [URL] {
        var candidates: [URL] = []
        var directory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            candidates.append(directory.appendingPathComponent("dev-overlay.json", isDirectory: false))
            candidates.append(
                directory
                    .appendingPathComponent("apps", isDirectory: true)
                    .appendingPathComponent("Donkey", isDirectory: true)
                    .appendingPathComponent("dev-overlay.json", isDirectory: false)
            )
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        return candidates
    }
    #endif
}

private struct RawDebugUIOverlayConfiguration: Codable {
    var enabled: Bool?
    var provider: String?
    var cadenceSeconds: TimeInterval?
    var screenScope: String?
    var minConfidence: Double?
}

public struct DebugUIElementTracker: Equatable, Sendable {
    private var previousElements: [DebugUIElement]

    public init(previousElements: [DebugUIElement] = []) {
        self.previousElements = previousElements
    }

    public mutating func update(with frame: DebugUIInspectionFrame) -> DebugUIInspectionFrame {
        var usedPreviousIDs = Set<String>()
        let tracked = frame.elements.map { incoming -> DebugUIElement in
            if previousElements.contains(where: { $0.id == incoming.id }) {
                usedPreviousIDs.insert(incoming.id)
                return incoming
            }

            guard let match = bestSemanticMatch(
                for: incoming,
                usedPreviousIDs: usedPreviousIDs
            ) else {
                return incoming
            }

            usedPreviousIDs.insert(match.id)
            return incoming.replacingID(match.id)
        }

        previousElements = tracked
        return DebugUIInspectionFrame(elements: tracked)
    }

    private func bestSemanticMatch(
        for incoming: DebugUIElement,
        usedPreviousIDs: Set<String>
    ) -> DebugUIElement? {
        previousElements
            .filter { previous in
                !usedPreviousIDs.contains(previous.id)
                    && previous.type == incoming.type
                    && normalized(previous.label) == normalized(incoming.label)
            }
            .max { left, right in
                matchScore(left.bbox, incoming.bbox) < matchScore(right.bbox, incoming.bbox)
            }
            .flatMap { candidate in
                matchScore(candidate.bbox, incoming.bbox) >= 0.25 ? candidate : nil
            }
    }

    private func matchScore(_ lhs: DebugUIBoundingBox, _ rhs: DebugUIBoundingBox) -> Double {
        let overlap = intersectionArea(lhs, rhs)
        let union = lhs.width * lhs.height + rhs.width * rhs.height - overlap
        let iou = union > 0 ? overlap / union : 0
        let centerDistance = hypot(
            (lhs.x + lhs.width / 2) - (rhs.x + rhs.width / 2),
            (lhs.y + lhs.height / 2) - (rhs.y + rhs.height / 2)
        )
        let distanceScore = max(0, 1 - centerDistance / 160)
        return max(iou, distanceScore * 0.5)
    }

    private func intersectionArea(_ lhs: DebugUIBoundingBox, _ rhs: DebugUIBoundingBox) -> Double {
        let minX = max(lhs.x, rhs.x)
        let minY = max(lhs.y, rhs.y)
        let maxX = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = min(lhs.y + lhs.height, rhs.y + rhs.height)
        return max(0, maxX - minX) * max(0, maxY - minY)
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }
}

public enum DebugUIOverlayGeometry {
    public static func appKitFrame(
        for bbox: DebugUIBoundingBox,
        screenshotPixelSize: HotLoopSize,
        screenFrame: HotLoopRect
    ) -> CGRect {
        guard screenshotPixelSize.width > 0,
              screenshotPixelSize.height > 0
        else {
            return .zero
        }

        let scaleX = screenFrame.size.width / screenshotPixelSize.width
        let scaleY = screenFrame.size.height / screenshotPixelSize.height
        return CGRect(
            x: screenFrame.origin.x + bbox.x * scaleX,
            y: screenFrame.origin.y + screenFrame.size.height - (bbox.y + bbox.height) * scaleY,
            width: bbox.width * scaleX,
            height: bbox.height * scaleY
        )
    }

    public static func localLayerFrame(
        for bbox: DebugUIBoundingBox,
        screenshotPixelSize: HotLoopSize,
        screenPointSize: HotLoopSize
    ) -> CGRect {
        guard screenshotPixelSize.width > 0,
              screenshotPixelSize.height > 0
        else {
            return .zero
        }

        let scaleX = screenPointSize.width / screenshotPixelSize.width
        let scaleY = screenPointSize.height / screenshotPixelSize.height
        return CGRect(
            x: bbox.x * scaleX,
            y: bbox.y * scaleY,
            width: bbox.width * scaleX,
            height: bbox.height * scaleY
        )
    }
}

public enum DebugUIScreenCaptureError: Error, Equatable, Sendable {
    case noScreenAvailable
    case missingDisplayIdentifier
    case captureFailed(displayID: UInt32)
    case pngEncodingFailed(displayID: UInt32)
}

public struct DebugUIScreenCaptureSnapshot: Equatable, Sendable {
    public var screenID: UInt32
    public var screenFrame: HotLoopRect
    public var pixelSize: HotLoopSize
    public var pngData: Data
    public var fingerprint: String

    public init(
        screenID: UInt32,
        screenFrame: HotLoopRect,
        pixelSize: HotLoopSize,
        pngData: Data,
        fingerprint: String
    ) {
        self.screenID = screenID
        self.screenFrame = screenFrame
        self.pixelSize = pixelSize
        self.pngData = pngData
        self.fingerprint = fingerprint
    }

    public var base64PNG: String {
        pngData.base64EncodedString()
    }
}

public struct DebugUIScreenCaptureService: Sendable {
    public init() {}

    public func captureScreens(
        scope: DebugUIInspectionScreenScope
    ) throws -> [DebugUIScreenCaptureSnapshot] {
        let screens: [NSScreen]
        switch scope {
        case .main:
            guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                throw DebugUIScreenCaptureError.noScreenAvailable
            }
            screens = [screen]
        case .all:
            screens = NSScreen.screens
        }

        return try screens.map(capture)
    }

    private func capture(screen: NSScreen) throws -> DebugUIScreenCaptureSnapshot {
        let displayID = try Self.displayID(for: screen)
        guard let image = CGDisplayCreateImage(displayID) else {
            throw DebugUIScreenCaptureError.captureFailed(displayID: displayID)
        }
        guard let pngData = Self.pngData(from: image) else {
            throw DebugUIScreenCaptureError.pngEncodingFailed(displayID: displayID)
        }

        let frame = screen.frame
        return DebugUIScreenCaptureSnapshot(
            screenID: displayID,
            screenFrame: HotLoopRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height,
                space: .screen
            ),
            pixelSize: HotLoopSize(
                width: Double(image.width),
                height: Double(image.height),
                space: .screen
            ),
            pngData: pngData,
            fingerprint: Self.fingerprint(for: pngData)
        )
    }

    private static func displayID(for screen: NSScreen) throws -> UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = screen.deviceDescription[key] as? NSNumber else {
            throw DebugUIScreenCaptureError.missingDisplayIdentifier
        }
        return value.uint32Value
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
