import DonkeyContracts
import Foundation

public struct LocalUIElementDetectionService: LocalUIElementDetecting {
    public var nativeVisualDetector: LocalUIElementNativeVisualDetector

    public init(
        nativeVisualDetector: LocalUIElementNativeVisualDetector = LocalUIElementNativeVisualDetector()
    ) {
        self.nativeVisualDetector = nativeVisualDetector
    }

    public func detect(_ request: LocalUIElementDetectionRequest) -> LocalUIElementDetectionTrace {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let nativeResult = nativeVisualDetector.candidates(
            fromPNGData: request.screenshotPNGData,
            imagePath: request.screenshotImagePath,
            pixelSize: request.pixelSize
        )
        let candidates = request.accessibilityCandidates
            + request.hoverProbeCandidates
            + nativeResult.candidates

        let mergeStartedAt = ProcessInfo.processInfo.systemUptime
        let merged = merge(
            candidates: candidates.filter { $0.bounds.hasPositiveArea },
            minConfidence: request.minConfidence
        )
        let mergeMS = (ProcessInfo.processInfo.systemUptime - mergeStartedAt) * 1_000
        let totalMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        var latency = nativeResult.latencyMS
        latency["mergeClassifyLabel"] = mergeMS
        latency["total"] = totalMS

        let metrics = metrics(
            candidates: candidates,
            elements: merged.elements,
            suppressed: merged.suppressed,
            minConfidence: request.minConfidence,
            latencyMS: latency
        )

        return LocalUIElementDetectionTrace(
            traceID: request.traceID,
            candidates: candidates,
            elements: merged.elements,
            suppressedCandidates: merged.suppressed,
            metrics: metrics,
            metadata: request.metadata.merging(nativeResult.metadata) { current, _ in current }.merging([
                "service": "local-ui-element-detection",
                "rawPixelsPersisted": "false",
                "visibleSystemA11yToggled": "false"
            ]) { current, _ in current }
        )
    }

    public func debugInspectionFrame(
        from trace: LocalUIElementDetectionTrace
    ) -> DebugUIInspectionFrame {
        DebugUIInspectionFrame(
            elements: trace.elements
                .filter(Self.shouldRenderInDebugOverlay)
                .map(Self.debugElement)
        )
    }

    private static func shouldRenderInDebugOverlay(_ element: LocalUIElement) -> Bool {
        if isDebugOverlayFeedbackLabel(element.label) {
            return false
        }
        if element.type == .draggable {
            return false
        }

        if let role = debugOverlayRole(for: element) {
            if isStaticDebugOverlayLabel(element.label, role: role) {
                return false
            }
            return true
        }
        if element.sources.contains(.accessibility) {
            return isInspectableAccessibilityElement(element)
        }
        if element.sources.contains(.hoverProbe) {
            return true
        }
        return false
    }

    private static func debugOverlayRole(for element: LocalUIElement) -> String? {
        element.metadata.first { key, _ in
            key == "debug.overlayRole" || key.hasSuffix(".debug.overlayRole")
        }?.value
    }

    private static func isDebugOverlayFeedbackLabel(_ value: String) -> Bool {
        let normalized = value.uppercased()
        let tokens = normalized
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        if tokens.first == "LAYOUT"
            || tokens.first == "AX" {
            return true
        }
        return normalized.contains("LAYOUT+")
            || normalized.contains("+LAYOUT")
            || normalized.contains("AX]")
    }

    private static func isStaticDebugOverlayLabel(_ value: String, role: String) -> Bool {
        let normalized = cleanDebugOverlayLabel(value)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        if role == "sidebarRow" {
            return ["pinned", "projects", "chats"].contains(normalized)
        }
        if role == "panelRow" {
            return ["environment", "sources", "no sources yet"].contains(normalized)
        }
        return false
    }

    private static func isInspectableAccessibilityElement(_ element: LocalUIElement) -> Bool {
        let width = element.bounds.size.width
        let height = element.bounds.size.height

        switch element.type {
        case .draggable, .other:
            return false
        case .checkbox, .toggle, .toolbarIcon, .windowControl:
            return width <= 160 && height <= 96
        case .menuItem, .tab, .dropdown, .slider:
            return width <= 260 && height <= 80
        case .button, .link:
            return width <= 420 && height <= 100
        case .sidebarItem, .listItem:
            return width <= 460 && height <= 120
        case .input:
            return width <= 920 && height <= 180
        }
    }

    public func localUIUnderstandingResult(
        from trace: LocalUIElementDetectionTrace
    ) -> LocalUIUnderstandingResult {
        var visibleText: [String: String] = [:]
        var controls: [LocalUIUnderstandingControl] = []

        for element in trace.elements {
            let normalizedControlID = Self.controlID(for: element)
            if !element.label.isEmpty {
                visibleText[element.id] = element.label
            }
            controls.append(
                LocalUIUnderstandingControl(
                    id: element.id,
                    label: element.label,
                    kind: Self.localAppKind(for: element),
                    frame: element.bounds,
                    confidence: element.confidence,
                    metadata: element.metadata.merging([
                        "controlID": normalizedControlID,
                        "localUIElement.type": element.type.rawValue,
                        "localUIElement.sources": element.sources.map(\.rawValue).joined(separator: ","),
                        "localUIElement.reasonCodes": element.reasonCodes.joined(separator: ","),
                        "localUIElement.actionEligibility": element.actionEligibility.rawValue,
                        "directInputActionsAllowed": String(element.isGuardedActionEligible)
                    ]) { current, _ in current }
                )
            )
        }

        return LocalUIUnderstandingResult(
            visibleText: visibleText,
            controls: controls,
            formFields: [],
            confidence: trace.elements.map(\.confidence).max() ?? 0,
            metadata: trace.metadata.merging(Self.metricsMetadata(trace.metrics)) { current, _ in current }
                .merging([
                    "understander": "local-ui-element-detection-service",
                    "directInputActionsAllowed": "false"
                ]) { current, _ in current }
        )
    }

    public static func debugElement(from element: LocalUIElement) -> DebugUIElement {
        DebugUIElement(
            id: element.id,
            type: element.type,
            label: debugOverlayLabel(for: element),
            description: [
                element.type.rawValue,
                element.sources.map(\.rawValue).joined(separator: "+"),
                element.actionEligibility.rawValue
            ].filter { !$0.isEmpty }.joined(separator: " "),
            bbox: DebugUIBoundingBox(
                x: element.bounds.origin.x,
                y: element.bounds.origin.y,
                width: element.bounds.size.width,
                height: element.bounds.size.height
            ),
            confidence: element.confidence,
            visualStyle: debugOverlayStyle(for: element),
            metadata: element.metadata.merging([
                "localUIElement.sources": element.sources.map(\.rawValue).joined(separator: ","),
                "localUIElement.reasonCodes": element.reasonCodes.joined(separator: ","),
                "localUIElement.actionEligibility": element.actionEligibility.rawValue
            ]) { current, _ in current }
        )
    }

    private static func debugOverlayLabel(for element: LocalUIElement) -> String {
        let role = debugOverlayRole(for: element)
        let label = cleanDebugOverlayLabel(element.label)
        let lowercasedLabel = label.lowercased()

        switch role {
        case "panel":
            return "environment panel"
        case "bottomInput", "messageInput":
            return "message input"
        case "bottomInputAccessory":
            if lowercasedLabel.contains("auto-review") {
                return "auto-review selector"
            }
            if lowercasedLabel.contains("5.5") || lowercasedLabel.contains("high") {
                return "model selector"
            }
            if lowercasedLabel.contains("submit") {
                return "send button"
            }
            if lowercasedLabel.contains("add") {
                return "add button"
            }
            if lowercasedLabel.contains("voice") {
                return "voice input button"
            }
            return "composer control"
        case "actionButton":
            if lowercasedLabel.contains("review") {
                return "review changes button"
            }
            return label.isEmpty ? "action button" : label
        case "chatTitle":
            return "chat title"
        case "fileLink":
            return "file link"
        case "userBubble":
            return "user bubble"
        case "commandRow":
            return "run command row"
        case "panelRow", "sidebarRow", "menuBarItem":
            break
        default:
            break
        }

        if !label.isEmpty,
           !isGenericLabel(label, type: element.type),
           label != "panel row",
           label != "sidebar item",
           label != "menu item" {
            return label
        }

        switch element.type {
        case .input:
            return "text input"
        case .button:
            return "button"
        case .toolbarIcon:
            return "toolbar icon"
        case .windowControl:
            return "window control"
        case .menuItem:
            return "menu item"
        case .sidebarItem:
            return "sidebar item"
        case .listItem:
            return "clickable row"
        case .dropdown:
            return "selector"
        case .checkbox:
            return "checkbox"
        case .toggle:
            return "toggle"
        case .link:
            return "link"
        case .tab:
            return "tab"
        case .slider:
            return "slider"
        case .draggable, .other:
            return ""
        }
    }

    private static func cleanDebugOverlayLabel(_ value: String) -> String {
        var label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        label = stripLeadingNoise(from: label)
        let noisyPrefixes = ["O ", "Q ", "00 ", "0 "]
        var changed = true
        while changed {
            changed = false
            for prefix in noisyPrefixes where label.hasPrefix(prefix) {
                label.removeFirst(prefix.count)
                label = label.trimmingCharacters(in: .whitespacesAndNewlines)
                label = stripLeadingNoise(from: label)
                changed = true
            }
        }
        return label
    }

    private static func stripLeadingNoise(from value: String) -> String {
        var label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = label.first,
              !first.isLetter,
              !first.isNumber {
            label.removeFirst()
            label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return label
    }

    private static func debugOverlayStyle(for element: LocalUIElement) -> DebugUIOverlayStyle {
        switch debugOverlayRole(for: element) {
        case "menuBarItem":
            return DebugUIOverlayStyle(overlayColor: "#06B6D4", borderColor: "#22D3EE")
        case "sidebarRow":
            return DebugUIOverlayStyle(overlayColor: "#0EA5E9", borderColor: "#38BDF8")
        case "panel", "panelRow":
            return DebugUIOverlayStyle(overlayColor: "#D946EF", borderColor: "#F0ABFC")
        case "bottomInput", "messageInput", "bottomInputAccessory":
            return DebugUIOverlayStyle(overlayColor: "#22C55E", borderColor: "#86EFAC")
        case "actionButton", "chatTitle":
            return DebugUIOverlayStyle(overlayColor: "#EAB308", borderColor: "#FDE047")
        case "fileLink", "userBubble", "commandRow":
            return DebugUIOverlayStyle(overlayColor: "#A855F7", borderColor: "#D8B4FE")
        default:
            return DebugUIOverlayStyle.style(for: element.type)
        }
    }

    private func merge(
        candidates: [LocalUIElementCandidate],
        minConfidence: Double
    ) -> (elements: [LocalUIElement], suppressed: [LocalUIElementSuppressedCandidate]) {
        var groups: [[LocalUIElementCandidate]] = []
        var suppressed: [LocalUIElementSuppressedCandidate] = []

        for candidate in candidates.sorted(by: Self.candidateSort) {
            guard candidate.confidence >= minConfidence else {
                suppressed.append(LocalUIElementSuppressedCandidate(candidate: candidate, reason: "lowConfidence"))
                continue
            }

            if let index = groups.firstIndex(where: { group in
                group.contains { Self.shouldMerge(candidate, $0) }
            }) {
                groups[index].append(candidate)
            } else {
                groups.append([candidate])
            }
        }

        let elements = groups.enumerated().compactMap { index, group -> LocalUIElement? in
            guard let element = element(from: group, index: index) else {
                for candidate in group {
                    suppressed.append(LocalUIElementSuppressedCandidate(candidate: candidate, reason: "unclassifiable"))
                }
                return nil
            }
            for candidate in group.dropFirst() {
                suppressed.append(
                    LocalUIElementSuppressedCandidate(
                        candidate: candidate,
                        reason: "mergedDuplicate",
                        mergedIntoElementID: element.id
                    )
                )
            }
            return element
        }

        return (
            elements.sorted { lhs, rhs in
                if lhs.bounds.origin.y != rhs.bounds.origin.y { return lhs.bounds.origin.y < rhs.bounds.origin.y }
                if lhs.bounds.origin.x != rhs.bounds.origin.x { return lhs.bounds.origin.x < rhs.bounds.origin.x }
                return lhs.id < rhs.id
            },
            suppressed
        )
    }

    private func element(
        from group: [LocalUIElementCandidate],
        index: Int
    ) -> LocalUIElement? {
        guard let primary = group.sorted(by: Self.candidateSort).first else { return nil }
        let type = classify(group: group)
        let label = label(group: group, type: type)
        let bounds = bestBounds(group: group)
        let sources = group.map(\.source)
        let confidence = min(1, group.map(\.confidence).max() ?? primary.confidence)
        let eligibility = actionEligibility(for: group, type: type)
        let reasonCodes = reasonCodes(for: group, type: type, label: label, eligibility: eligibility)
        let id = stableElementID(primary: primary, type: type, label: label, index: index)

        return LocalUIElement(
            id: id,
            type: type,
            label: label,
            bounds: bounds,
            confidence: confidence,
            sources: sources,
            reasonCodes: reasonCodes,
            actionEligibility: eligibility,
            sourceCandidateIDs: group.map(\.id),
            metadata: group.reduce(into: [:]) { result, candidate in
                for (key, value) in candidate.metadata {
                    result["candidate.\(candidate.id).\(key)"] = value
                }
            }.merging([
                "primaryCandidateID": primary.id,
                "source.count": String(Set(sources).count)
            ]) { current, _ in current }
        )
    }

    private func classify(group: [LocalUIElementCandidate]) -> DebugUIElementType {
        if let ax = group.first(where: { $0.source == .accessibility }),
           let typeHint = ax.typeHint {
            return typeHint
        }
        if let explicit = group.first(where: { $0.typeHint != nil })?.typeHint {
            return explicit
        }
        return .other
    }

    private func label(
        group: [LocalUIElementCandidate],
        type: DebugUIElementType
    ) -> String {
        let axLabel = bestLabel(group: group.filter { $0.source == .accessibility })
        if let axLabel,
           !Self.isGenericLabel(axLabel, type: type) {
            return axLabel
        }
        if let layoutLabel = bestLabel(group: group.filter({ candidate in
            candidate.source == .layout && Self.debugOverlayRole(for: candidate) != nil
        })),
           !Self.isGenericLabel(layoutLabel, type: type) {
            return layoutLabel
        }
        if let axLabel {
            return axLabel
        }
        if let hinted = bestLabel(group: group) {
            return hinted
        }
        return type.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private func bestLabel(group: [LocalUIElementCandidate]) -> String? {
        group
            .compactMap { $0.label?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func bestBounds(group: [LocalUIElementCandidate]) -> HotLoopRect {
        if let accessibility = group.first(where: { $0.source == .accessibility }) {
            return accessibility.bounds
        }
        if let layout = group.first(where: { candidate in
            candidate.source == .layout && Self.debugOverlayRole(for: candidate) != nil
        }) {
            return layout.bounds
        }
        return group.sorted(by: Self.candidateSort).first?.bounds
            ?? HotLoopRect(x: 0, y: 0, width: 1, height: 1, space: .screen)
    }

    private func actionEligibility(
        for group: [LocalUIElementCandidate],
        type: DebugUIElementType
    ) -> LocalUIElementActionEligibility {
        if group.contains(where: { candidate in
            candidate.source == .accessibility
                && candidate.actions.contains { action in action == "AXPress" || action == "AXSetValue" }
        }) {
            return .guardedAction
        }
        if [.button, .input, .link, .checkbox, .toggle, .dropdown, .menuItem, .toolbarIcon, .sidebarItem, .listItem].contains(type) {
            return .cursorVisualization
        }
        return .readOnlyEvidence
    }

    private func reasonCodes(
        for group: [LocalUIElementCandidate],
        type: DebugUIElementType,
        label: String,
        eligibility: LocalUIElementActionEligibility
    ) -> [String] {
        var reasons = Set(group.map { "\($0.source.rawValue).\($0.signalKind.rawValue)" })
        if group.contains(where: { $0.source == .accessibility }) {
            reasons.insert("axWinsSemantics")
        }
        if group.count > 1 {
            reasons.insert("mergedOverlappingCandidates")
        }
        reasons.insert("classifiedAs.\(type.rawValue)")
        reasons.insert("eligibility.\(eligibility.rawValue)")
        return Array(reasons).sorted()
    }

    private func stableElementID(
        primary: LocalUIElementCandidate,
        type: DebugUIElementType,
        label: String,
        index: Int
    ) -> String {
        if primary.source == .accessibility {
            return primary.id
        }
        let labelSlug = Self.slug(label.isEmpty ? type.rawValue : label)
        return "local-ui-\(type.rawValue)-\(labelSlug)-\(index)"
    }

    private func metrics(
        candidates: [LocalUIElementCandidate],
        elements: [LocalUIElement],
        suppressed: [LocalUIElementSuppressedCandidate],
        minConfidence: Double,
        latencyMS: [String: Double]
    ) -> LocalUIElementDetectionMetrics {
        let sourceCounts = Dictionary(
            grouping: candidates,
            by: { $0.source.rawValue }
        ).mapValues(\.count)
        let nonAccessibilityCount = elements.filter { element in
            !element.sources.contains(.accessibility)
        }.count
        return LocalUIElementDetectionMetrics(
            sourceCounts: sourceCounts,
            candidateCount: candidates.count,
            elementCount: elements.count,
            suppressedCount: suppressed.count,
            duplicateCount: suppressed.filter { $0.reason == "mergedDuplicate" }.count,
            nonAccessibilityElementCount: nonAccessibilityCount,
            minConfidence: minConfidence,
            latencyMS: latencyMS
        )
    }

    private static func shouldMerge(
        _ lhs: LocalUIElementCandidate,
        _ rhs: LocalUIElementCandidate
    ) -> Bool {
        if isBottomInputSurface(lhs), isBottomInputAccessory(rhs) {
            return false
        }
        if isBottomInputSurface(rhs), isBottomInputAccessory(lhs) {
            return false
        }
        if isBottomInputAccessory(lhs), isBottomInputAccessory(rhs),
           lhs.source == .layout, rhs.source == .layout {
            return false
        }
        if isBottomInputAccessory(lhs),
           let role = debugOverlayRole(for: rhs),
           role != "bottomInputAccessory" {
            return false
        }
        if isBottomInputAccessory(rhs),
           let role = debugOverlayRole(for: lhs),
           role != "bottomInputAccessory" {
            return false
        }

        if isStructuralContainer(lhs) != isStructuralContainer(rhs) {
            return false
        }

        let iou = intersectionOverUnion(lhs.bounds, rhs.bounds)
        if iou >= 0.30 { return true }
        if contains(lhs.bounds, rhs.bounds) || contains(rhs.bounds, lhs.bounds) {
            return true
        }
        return false
    }

    private static func debugOverlayRole(for candidate: LocalUIElementCandidate) -> String? {
        candidate.metadata.first { key, _ in
            key == "debug.overlayRole" || key.hasSuffix(".debug.overlayRole")
        }?.value
    }

    private static func isBottomInputSurface(_ candidate: LocalUIElementCandidate) -> Bool {
        let role = debugOverlayRole(for: candidate)
        return role == "bottomInput" || role == "messageInput"
    }

    private static func isBottomInputAccessory(_ candidate: LocalUIElementCandidate) -> Bool {
        debugOverlayRole(for: candidate) == "bottomInputAccessory"
    }

    private static func isStructuralContainer(_ candidate: LocalUIElementCandidate) -> Bool {
        candidate.typeHint == .draggable
            || candidate.role == "AXWindow"
            || candidate.role == "AXSheet"
            || candidate.metadata["element.kind"] == "window"
    }

    private static func candidateSort(_ lhs: LocalUIElementCandidate, _ rhs: LocalUIElementCandidate) -> Bool {
        if sourcePriority(lhs.source) != sourcePriority(rhs.source) {
            return sourcePriority(lhs.source) < sourcePriority(rhs.source)
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        return lhs.id < rhs.id
    }

    private static func sourcePriority(_ source: LocalUIElementCandidateSource) -> Int {
        switch source {
        case .accessibility: return 0
        case .hoverProbe: return 1
        case .template: return 2
        case .layout: return 3
        case .shape: return 4
        case .ocr: return 5
        case .color: return 6
        case .connectedComponent: return 7
        }
    }

    private static func intersectionOverUnion(_ lhs: HotLoopRect, _ rhs: HotLoopRect) -> Double {
        let overlap = intersectionArea(lhs, rhs)
        let union = lhs.size.width * lhs.size.height + rhs.size.width * rhs.size.height - overlap
        return union > 0 ? overlap / union : 0
    }

    private static func intersectionArea(_ lhs: HotLoopRect, _ rhs: HotLoopRect) -> Double {
        let minX = max(lhs.origin.x, rhs.origin.x)
        let minY = max(lhs.origin.y, rhs.origin.y)
        let maxX = min(lhs.origin.x + lhs.size.width, rhs.origin.x + rhs.size.width)
        let maxY = min(lhs.origin.y + lhs.size.height, rhs.origin.y + rhs.size.height)
        return max(0, maxX - minX) * max(0, maxY - minY)
    }

    private static func contains(_ outer: HotLoopRect, _ inner: HotLoopRect) -> Bool {
        guard outer.space == inner.space else { return false }
        let innerArea = inner.size.width * inner.size.height
        guard innerArea > 0 else { return false }
        return intersectionArea(outer, inner) / innerArea >= 0.78
    }

    private static func controlID(for element: LocalUIElement) -> String {
        slug(element.label.isEmpty ? element.id : element.label)
    }

    private static func localAppKind(for element: LocalUIElement) -> LocalAppControlKind {
        switch element.type {
        case .button, .toolbarIcon, .tab, .toggle, .dropdown, .windowControl:
            return .button
        case .input:
            return .textField
        case .checkbox:
            return .checkbox
        case .link:
            return .link
        case .menuItem, .sidebarItem:
            return .menuItem
        case .listItem:
            return .listItem
        case .slider, .draggable, .other:
            return .unknown
        }
    }

    public static func metricsMetadata(_ metrics: LocalUIElementDetectionMetrics) -> [String: String] {
        var metadata: [String: String] = [
            "localUIElement.candidateCount": String(metrics.candidateCount),
            "localUIElement.elementCount": String(metrics.elementCount),
            "localUIElement.suppressedCount": String(metrics.suppressedCount),
            "localUIElement.duplicateCount": String(metrics.duplicateCount),
            "localUIElement.nonAccessibilityElementCount": String(metrics.nonAccessibilityElementCount),
            "localUIElement.minConfidence": String(metrics.minConfidence)
        ]
        for (source, count) in metrics.sourceCounts {
            metadata["localUIElement.source.\(source).count"] = String(count)
        }
        for (name, latency) in metrics.latencyMS {
            metadata["latency.localUIElement.\(name)MS"] = String(format: "%.3f", latency)
        }
        return metadata
    }

    private static func slug(_ value: String) -> String {
        let normalized = value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(6)
            .joined(separator: "-")
        return normalized.isEmpty ? "element" : normalized
    }

    private static func isGenericLabel(_ label: String, type: DebugUIElementType) -> Bool {
        let normalized = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
        return normalized.isEmpty
            || normalized == type.rawValue.replacingOccurrences(of: "_", with: " ")
            || normalized == "list item"
            || normalized == "button"
            || normalized == "checkbox"
            || normalized == "input"
            || normalized == "link"
            || normalized == "other"
    }
}
