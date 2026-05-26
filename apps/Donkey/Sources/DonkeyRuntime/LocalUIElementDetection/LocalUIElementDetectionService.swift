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
            pixelSize: request.pixelSize
        )
        let rowCandidates = rowLayoutCandidates(
            from: nativeResult.candidates,
            pixelSize: request.pixelSize
        )
        let candidates = request.accessibilityCandidates
            + request.hoverProbeCandidates
            + nativeResult.candidates
            + rowCandidates

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
            elements: trace.elements.map(Self.debugElement)
        )
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
            label: element.label,
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
            metadata: element.metadata.merging([
                "localUIElement.sources": element.sources.map(\.rawValue).joined(separator: ","),
                "localUIElement.reasonCodes": element.reasonCodes.joined(separator: ","),
                "localUIElement.actionEligibility": element.actionEligibility.rawValue
            ]) { current, _ in current }
        )
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
        if let template = group.first(where: { $0.source == .template }),
           let typeHint = template.typeHint {
            return typeHint
        }
        if let explicit = group.first(where: { $0.typeHint != nil })?.typeHint {
            return explicit
        }

        let textCandidate = group.first { $0.source == .ocr }
        let shapeCandidate = group.first { $0.source == .shape }
        if textCandidate != nil, let shapeCandidate {
            let aspect = shapeCandidate.bounds.size.width / max(1, shapeCandidate.bounds.size.height)
            return aspect > 3.6 ? .input : .button
        }
        if group.contains(where: { $0.source == .connectedComponent }) {
            return .toolbarIcon
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
        if let insideText = bestLabel(group: group.filter { $0.source == .ocr }) {
            return insideText
        }
        if let axLabel {
            return axLabel
        }
        if let templateLabel = bestLabel(group: group.filter { $0.source == .template }) {
            return templateLabel
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
        if let shape = group.first(where: { $0.source == .shape }) {
            return shape.bounds
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
        if group.contains(where: { $0.source == .ocr }), !label.isEmpty {
            reasons.insert("ocrContributesLabel")
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
        let cvOnlyCount = elements.filter { element in
            !element.sources.contains(.accessibility)
        }.count
        return LocalUIElementDetectionMetrics(
            sourceCounts: sourceCounts,
            candidateCount: candidates.count,
            elementCount: elements.count,
            suppressedCount: suppressed.count,
            duplicateCount: suppressed.filter { $0.reason == "mergedDuplicate" }.count,
            cvOnlyElementCount: cvOnlyCount,
            minConfidence: minConfidence,
            latencyMS: latencyMS
        )
    }

    private static func shouldMerge(
        _ lhs: LocalUIElementCandidate,
        _ rhs: LocalUIElementCandidate
    ) -> Bool {
        if isStructuralContainer(lhs) != isStructuralContainer(rhs) {
            return false
        }

        let iou = intersectionOverUnion(lhs.bounds, rhs.bounds)
        if iou >= 0.30 { return true }
        if contains(lhs.bounds, rhs.bounds) || contains(rhs.bounds, lhs.bounds) {
            return true
        }
        if lhs.source == .ocr || rhs.source == .ocr {
            return center(lhs.bounds, inside: rhs.bounds) || center(rhs.bounds, inside: lhs.bounds)
        }
        return false
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

    private func rowLayoutCandidates(
        from candidates: [LocalUIElementCandidate],
        pixelSize: HotLoopSize
    ) -> [LocalUIElementCandidate] {
        let textCandidates = candidates
            .filter { $0.source == .ocr && $0.bounds.size.height >= 8 }
            .sorted { lhs, rhs in
                if lhs.bounds.origin.y != rhs.bounds.origin.y {
                    return lhs.bounds.origin.y < rhs.bounds.origin.y
                }
                return lhs.bounds.origin.x < rhs.bounds.origin.x
            }
        guard textCandidates.count >= 3,
              pixelSize.width > 0,
              pixelSize.height > 0
        else {
            return []
        }

        let medianHeight = Self.median(textCandidates.map(\.bounds.size.height))
        let rowHeight = min(max(medianHeight * 2.35, 28), 58)
        let leftEdge = max(0, (textCandidates.map(\.bounds.origin.x).min() ?? 0) - 18)
        let rightTextEdge = textCandidates
            .map { $0.bounds.origin.x + $0.bounds.size.width }
            .max() ?? pixelSize.width
        let rightEdge = min(pixelSize.width, max(rightTextEdge + 28, pixelSize.width - 34))
        let width = max(1, rightEdge - leftEdge)

        var rows: [LocalUIElementCandidate] = []
        for (index, text) in textCandidates.enumerated() {
            let centerY = text.bounds.origin.y + text.bounds.size.height / 2
            if rows.contains(where: { existing in
                abs((existing.bounds.origin.y + existing.bounds.size.height / 2) - centerY) < rowHeight * 0.45
            }) {
                continue
            }

            let y = min(max(centerY - rowHeight / 2, 0), max(0, pixelSize.height - rowHeight))
            rows.append(
                LocalUIElementCandidate(
                    id: "layout-row-\(index)-\(Self.slug(text.label ?? "row"))",
                    source: .layout,
                    signalKind: .rowGrouping,
                    typeHint: .listItem,
                    label: text.label,
                    bounds: HotLoopRect(
                        x: leftEdge,
                        y: y,
                        width: width,
                        height: rowHeight,
                        space: pixelSize.space
                    ),
                    confidence: 0.58,
                    metadata: [
                        "detector": "local-row-layout",
                        "classification.reason": "ocrRepeatedVerticalListRhythm",
                        "row.height": String(format: "%.1f", rowHeight)
                    ]
                )
            )
        }
        return rows
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

    private static func center(_ rect: HotLoopRect, inside other: HotLoopRect) -> Bool {
        guard rect.space == other.space else { return false }
        let centerX = rect.origin.x + rect.size.width / 2
        let centerY = rect.origin.y + rect.size.height / 2
        return centerX >= other.origin.x
            && centerX <= other.origin.x + other.size.width
            && centerY >= other.origin.y
            && centerY <= other.origin.y + other.size.height
    }

    private static func controlID(for element: LocalUIElement) -> String {
        slug(element.label.isEmpty ? element.id : element.label)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
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
            "localUIElement.cvOnlyElementCount": String(metrics.cvOnlyElementCount),
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
