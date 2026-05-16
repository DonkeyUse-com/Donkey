@preconcurrency import AppKit
import CoreGraphics
import DonkeyContracts
import Foundation

public enum MacWindowResolverError: Error, Equatable, Sendable {
    case noVisibleWindows
    case noFocusedWindow
    case windowNotFound(windowID: UInt32)
}

struct MacWindowProviderWindow: Equatable, Sendable {
    var windowID: UInt32
    var processID: Int32
    var appName: String?
    var bundleIdentifier: String?
    var title: String?
    var bounds: WindowTargetBounds
    var alpha: Double
    var layer: Int
    var isOnScreen: Bool

    init(
        windowID: UInt32,
        processID: Int32,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        title: String? = nil,
        bounds: WindowTargetBounds,
        alpha: Double = 1,
        layer: Int = 0,
        isOnScreen: Bool = true
    ) {
        self.windowID = windowID
        self.processID = processID
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.bounds = bounds
        self.alpha = alpha
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}

protocol MacWindowMetadataProviding {
    func windows() -> [MacWindowProviderWindow]
    func frontmostProcessIdentifier() -> Int32?
    func focusedWindowIdentifier() -> UInt32?
}

public final class MacWindowResolver {
    private let provider: any MacWindowMetadataProviding

    public convenience init() {
        self.init(provider: CoreGraphicsMacWindowMetadataProvider())
    }

    init(provider: any MacWindowMetadataProviding) {
        self.provider = provider
    }

    public func enumerateCandidates() -> [MacWindowTargetCandidate] {
        let frontmostProcessID = provider.frontmostProcessIdentifier()
        let focusedWindowID = provider.focusedWindowIdentifier()
        var assignedFocusedFallback = false

        return provider.windows()
            .filter(Self.isVisibleWindow)
            .map { window in
                let isFrontmost = window.processID == frontmostProcessID
                let isFocused: Bool

                if let focusedWindowID {
                    isFocused = window.windowID == focusedWindowID
                } else if isFrontmost && !assignedFocusedFallback {
                    isFocused = true
                    assignedFocusedFallback = true
                } else {
                    isFocused = false
                }

                return MacWindowTargetCandidate(
                    windowID: window.windowID,
                    processID: window.processID,
                    appName: Self.normalizedOptional(window.appName),
                    bundleIdentifier: Self.normalizedOptional(window.bundleIdentifier),
                    title: Self.normalizedOptional(window.title),
                    bounds: window.bounds,
                    isVisible: true,
                    isOnScreen: window.isOnScreen,
                    isFrontmost: isFrontmost,
                    isFocused: isFocused,
                    isIPhoneMirroring: Self.isIPhoneMirroring(window),
                    safetyAssessment: Self.safetyAssessment(for: window)
                )
            }
    }

    public func selectTarget(
        _ request: MacWindowSelectionRequest = MacWindowSelectionRequest()
    ) throws -> MacWindowTargetCandidate {
        let candidates = enumerateCandidates()
        guard !candidates.isEmpty else {
            throw MacWindowResolverError.noVisibleWindows
        }

        if let windowID = request.windowID {
            guard let match = candidates.first(where: { $0.windowID == windowID }) else {
                throw MacWindowResolverError.windowNotFound(windowID: windowID)
            }

            return match
        }

        if let focused = candidates.first(where: \.isFocused) {
            return focused
        }

        if let frontmost = candidates.first(where: \.isFrontmost) {
            return frontmost
        }

        throw MacWindowResolverError.noFocusedWindow
    }

    private static func isVisibleWindow(_ window: MacWindowProviderWindow) -> Bool {
        window.isOnScreen
            && window.alpha > 0
            && window.layer == 0
            && window.bounds.hasPositiveArea
    }

    private static func isIPhoneMirroring(_ window: MacWindowProviderWindow) -> Bool {
        let haystack = searchableText(for: window)
        return haystack.contains("iphone mirroring")
            || haystack.contains("iphone")
                && haystack.contains("mirroring")
            || haystack.contains("screencontinuity")
    }

    private static func safetyAssessment(
        for window: MacWindowProviderWindow
    ) -> WindowTargetSafetyAssessment {
        var reasons: [WindowTargetSafetyReason] = []
        let haystack = searchableText(for: window)

        if haystack.contains("loginwindow")
            || haystack.contains("sign in")
            || haystack.contains("signin")
            || haystack.contains("sign-in")
            || haystack.contains("log in")
            || haystack.contains("unlock")
            || haystack.contains("authentication") {
            reasons.append(.loginSurface)
        }

        if haystack.contains("password")
            || haystack.contains("passcode")
            || haystack.contains("credential")
            || haystack.contains("keychain") {
            reasons.append(.passwordSurface)
        }

        if haystack.contains("payment")
            || haystack.contains("checkout")
            || haystack.contains("billing")
            || haystack.contains("credit card")
            || haystack.contains("card number")
            || haystack.contains("apple pay")
            || haystack.contains("paypal")
            || haystack.contains("purchase") {
            reasons.append(.paymentSurface)
        }

        if haystack.contains("permission")
            || haystack.contains("privacy & security")
            || haystack.contains("screen recording")
            || haystack.contains("accessibility") {
            reasons.append(.permissionSurface)
        }

        if haystack.contains("system settings")
            || haystack.contains("system preferences")
            || haystack.contains("securityagent")
            || haystack.contains("coreautha")
            || haystack.contains("systemuiserver")
            || haystack.contains("installer")
            || haystack.contains("software update") {
            reasons.append(.systemSurface)
        }

        if isUnderDescribed(window) {
            reasons.append(.unknownSurface)
        }

        let uniqueReasons = reasons.uniqued()
        if uniqueReasons.isEmpty {
            return WindowTargetSafetyAssessment(
                status: .allowed,
                summary: "No sensitive surface indicators detected"
            )
        }

        if uniqueReasons == [.unknownSurface] {
            return WindowTargetSafetyAssessment(
                status: .reviewRequired,
                reasons: uniqueReasons,
                summary: "Window metadata is too sparse for automatic capture"
            )
        }

        return WindowTargetSafetyAssessment(
            status: .blocked,
            reasons: uniqueReasons,
            summary: "Sensitive or system surface indicators detected"
        )
    }

    private static func isUnderDescribed(_ window: MacWindowProviderWindow) -> Bool {
        normalizedOptional(window.appName) == nil
            && normalizedOptional(window.bundleIdentifier) == nil
            && normalizedOptional(window.title) == nil
    }

    private static func searchableText(for window: MacWindowProviderWindow) -> String {
        [
            window.appName,
            window.bundleIdentifier,
            window.title
        ]
        .compactMap(normalizedOptional)
        .joined(separator: " ")
        .lowercased()
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }

        return trimmed
    }
}

private struct CoreGraphicsMacWindowMetadataProvider: MacWindowMetadataProviding {
    func windows() -> [MacWindowProviderWindow] {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap { rawWindow in
            guard let windowID = rawWindow.uint32Value(for: kCGWindowNumber),
                  let processID = rawWindow.int32Value(for: kCGWindowOwnerPID),
                  let bounds = rawWindow.boundsValue(for: kCGWindowBounds)
            else {
                return nil
            }

            let bundleIdentifier = NSRunningApplication(
                processIdentifier: processID
            )?.bundleIdentifier

            return MacWindowProviderWindow(
                windowID: windowID,
                processID: processID,
                appName: rawWindow.stringValue(for: kCGWindowOwnerName),
                bundleIdentifier: bundleIdentifier,
                title: rawWindow.stringValue(for: kCGWindowName),
                bounds: bounds,
                alpha: rawWindow.doubleValue(for: kCGWindowAlpha) ?? 1,
                layer: rawWindow.intValue(for: kCGWindowLayer) ?? 0,
                isOnScreen: rawWindow.boolValue(for: kCGWindowIsOnscreen) ?? true
            )
        }
    }

    func frontmostProcessIdentifier() -> Int32? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func focusedWindowIdentifier() -> UInt32? {
        nil
    }
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(for key: CFString) -> String? {
        self[key as String] as? String
    }

    func boolValue(for key: CFString) -> Bool? {
        if let value = self[key as String] as? Bool {
            return value
        }

        return (self[key as String] as? NSNumber)?.boolValue
    }

    func intValue(for key: CFString) -> Int? {
        (self[key as String] as? NSNumber)?.intValue
    }

    func int32Value(for key: CFString) -> Int32? {
        (self[key as String] as? NSNumber)?.int32Value
    }

    func uint32Value(for key: CFString) -> UInt32? {
        (self[key as String] as? NSNumber)?.uint32Value
    }

    func doubleValue(for key: CFString) -> Double? {
        (self[key as String] as? NSNumber)?.doubleValue
    }

    func boundsValue(for key: CFString) -> WindowTargetBounds? {
        guard let rawBounds = self[key as String] as? [String: Any],
              let x = (rawBounds["X"] as? NSNumber)?.doubleValue,
              let y = (rawBounds["Y"] as? NSNumber)?.doubleValue,
              let width = (rawBounds["Width"] as? NSNumber)?.doubleValue,
              let height = (rawBounds["Height"] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        return WindowTargetBounds(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
