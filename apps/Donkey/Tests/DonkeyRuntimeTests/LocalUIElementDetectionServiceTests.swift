import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct LocalUIElementDetectionServiceTests {
    @Test
    func accessibilityCandidateWinsSemanticsAndAllowsGuardedActionEvidence() throws {
        let trace = LocalUIElementDetectionService().detect(
            LocalUIElementDetectionRequest(
                traceID: "trace-ax-wins",
                pixelSize: HotLoopSize(width: 400, height: 300, space: .screen),
                accessibilityCandidates: [
                    LocalUIElementCandidate(
                        id: "ax-save",
                        source: .accessibility,
                        signalKind: .accessibilityRole,
                        typeHint: .button,
                        label: "Save",
                        role: "AXButton",
                        bounds: HotLoopRect(x: 20, y: 40, width: 96, height: 32, space: .screen),
                        confidence: 1,
                        actions: ["AXPress"]
                    )
                ],
                hoverProbeCandidates: [
                    LocalUIElementCandidate(
                        id: "hover-save",
                        source: .hoverProbe,
                        signalKind: .hoverHighlight,
                        typeHint: .listItem,
                        label: "Wrong hover label",
                        bounds: HotLoopRect(x: 12, y: 34, width: 160, height: 44, space: .screen),
                        confidence: 0.92
                    )
                ],
                minConfidence: 0.25
            )
        )

        let element = try #require(trace.elements.first)
        #expect(trace.elements.count == 1)
        #expect(element.id == "ax-save")
        #expect(element.type == .button)
        #expect(element.label == "Save")
        #expect(element.sources.contains(.accessibility))
        #expect(element.sources.contains(.hoverProbe))
        #expect(element.actionEligibility == .guardedAction)
        #expect(element.reasonCodes.contains("axWinsSemantics"))
    }

    @Test
    func visualOnlyCandidatesRemainReadOnlyForInputEvenWhenTheyLookClickable() throws {
        let trace = LocalUIElementDetectionService().detect(
            LocalUIElementDetectionRequest(
                traceID: "trace-visual-only",
                pixelSize: HotLoopSize(width: 700, height: 900, space: .screen),
                hoverProbeCandidates: [
                    LocalUIElementCandidate(
                        id: "hover-row",
                        source: .hoverProbe,
                        signalKind: .hoverHighlight,
                        typeHint: .listItem,
                        label: "Improve UI element detection",
                        bounds: HotLoopRect(x: 16, y: 480, width: 660, height: 48, space: .screen),
                        confidence: 0.88
                    )
                ],
                minConfidence: 0.25
            )
        )

        let element = try #require(trace.elements.first)
        let result = LocalUIElementDetectionService().localUIUnderstandingResult(from: trace)
        let control = try #require(result.controls.first)

        #expect(element.type == .listItem)
        #expect(element.actionEligibility == .cursorVisualization)
        #expect(control.metadata["directInputActionsAllowed"] == "false")
        #expect(result.metadata["directInputActionsAllowed"] == "false")
    }

    @Test
    func lowConfidenceCandidatesAreSuppressedWithReasonCodes() {
        let trace = LocalUIElementDetectionService().detect(
            LocalUIElementDetectionRequest(
                traceID: "trace-low-confidence",
                pixelSize: HotLoopSize(width: 400, height: 300, space: .screen),
                hoverProbeCandidates: [
                    LocalUIElementCandidate(
                        id: "hover-noise",
                        source: .hoverProbe,
                        signalKind: .hoverHighlight,
                        typeHint: .button,
                        label: "Noise",
                        bounds: HotLoopRect(x: 10, y: 10, width: 80, height: 22, space: .screen),
                        confidence: 0.12
                    )
                ],
                minConfidence: 0.25
            )
        )

        #expect(trace.elements.isEmpty)
        #expect(trace.suppressedCandidates.map(\.reason) == ["lowConfidence"])
        #expect(trace.metrics.suppressedCount == 1)
    }

    @Test
    func nativeVisualDetectorIsStubbedUntilReplacementImplementationExists() {
        let trace = LocalUIElementDetectionService().detect(
            LocalUIElementDetectionRequest(
                traceID: "trace-native-visual-stub",
                screenshotPNGData: Data([0x89, 0x50, 0x4E, 0x47]),
                pixelSize: HotLoopSize(width: 400, height: 300, space: .screen),
                minConfidence: 0.25
            )
        )

        #expect(trace.candidates.isEmpty)
        #expect(trace.elements.isEmpty)
        #expect(trace.metadata["nativeVisual.status"] == "stubbed")
        #expect(trace.metadata["nativeVisual.reason"] == "cvPipelineRemovedPendingReplacement")
    }

    @Test
    func debugInspectionFrameSuppressesLegacyVisualAndLayoutOnlyFragments() {
        let trace = LocalUIElementDetectionTrace(
            traceID: "trace-debug-frame-filter",
            candidates: [],
            elements: [
                LocalUIElement(
                    id: "legacy-visual-copy",
                    type: .other,
                    label: "Body copy",
                    bounds: HotLoopRect(x: 20, y: 40, width: 180, height: 22, space: .screen),
                    confidence: 0.9,
                    sources: [.ocr],
                    reasonCodes: [],
                    actionEligibility: .readOnlyEvidence,
                    sourceCandidateIDs: ["legacy-visual-copy"]
                ),
                LocalUIElement(
                    id: "layout-only-row",
                    type: .listItem,
                    label: "Improve UI element detection",
                    bounds: HotLoopRect(x: 10, y: 80, width: 240, height: 34, space: .screen),
                    confidence: 0.72,
                    sources: [.layout],
                    reasonCodes: [],
                    actionEligibility: .cursorVisualization,
                    sourceCandidateIDs: ["layout-only-row"]
                ),
                LocalUIElement(
                    id: "sidebar-row",
                    type: .sidebarItem,
                    label: "Stabilize dev layout UI",
                    bounds: HotLoopRect(x: 10, y: 120, width: 240, height: 34, space: .screen),
                    confidence: 0.72,
                    sources: [.layout],
                    reasonCodes: [],
                    actionEligibility: .cursorVisualization,
                    sourceCandidateIDs: ["sidebar-row"],
                    metadata: ["candidate.sidebar-row.debug.overlayRole": "sidebarRow"]
                )
            ],
            suppressedCandidates: [],
            metrics: LocalUIElementDetectionMetrics()
        )

        let frame = LocalUIElementDetectionService().debugInspectionFrame(from: trace)

        #expect(frame.elements.map(\.id) == ["sidebar-row"])
    }

    @Test
    func debugInspectionFrameSuppressesLegacyVisionWithoutPromotingAtomicControls() {
        let trace = LocalUIElementDetectionTrace(
            traceID: "trace-debug-large-panel-filter",
            candidates: [],
            elements: [
                LocalUIElement(
                    id: "legacy-small-checkbox",
                    type: .checkbox,
                    label: "Auto-review",
                    bounds: HotLoopRect(x: 600, y: 1210, width: 34, height: 34, space: .screen),
                    confidence: 0.72,
                    sources: [.shape],
                    reasonCodes: [],
                    actionEligibility: .cursorVisualization,
                    sourceCandidateIDs: ["legacy-shape-checkbox"]
                ),
                LocalUIElement(
                    id: "hover-row",
                    type: .listItem,
                    label: "Hover-highlighted row",
                    bounds: HotLoopRect(x: 120, y: 80, width: 180, height: 36, space: .screen),
                    confidence: 0.74,
                    sources: [.hoverProbe],
                    reasonCodes: [],
                    actionEligibility: .cursorVisualization,
                    sourceCandidateIDs: ["hover-row"]
                )
            ],
            suppressedCandidates: [],
            metrics: LocalUIElementDetectionMetrics()
        )

        let frame = LocalUIElementDetectionService().debugInspectionFrame(from: trace)

        #expect(frame.elements.map(\.id) == ["hover-row"])
    }

    @Test
    func bottomComposerAccessoriesDoNotMergeIntoInputSurface() throws {
        let input = LocalUIElementCandidate(
            id: "layout-bottom-input",
            source: .layout,
            signalKind: .rowGrouping,
            typeHint: .input,
            label: "Ask for follow-up changes",
            bounds: HotLoopRect(x: 988, y: 1981, width: 1278, height: 150, space: .screen),
            confidence: 0.70,
            metadata: ["debug.overlayRole": "bottomInput"]
        )
        let accessory = LocalUIElementCandidate(
            id: "layout-bottom-input-plus",
            source: .layout,
            signalKind: .rowGrouping,
            typeHint: .toolbarIcon,
            label: "composer add button",
            bounds: HotLoopRect(x: 1016, y: 2083, width: 38, height: 38, space: .screen),
            confidence: 0.66,
            metadata: ["debug.overlayRole": "bottomInputAccessory"]
        )

        let trace = LocalUIElementDetectionService().detect(
            LocalUIElementDetectionRequest(
                traceID: "trace-bottom-composer-accessory",
                pixelSize: HotLoopSize(width: 2880, height: 2304, space: .screen),
                hoverProbeCandidates: [input, accessory],
                minConfidence: 0.25
            )
        )

        let elements = trace.elements.sorted { $0.bounds.origin.x < $1.bounds.origin.x }
        #expect(elements.count == 2)
        #expect(elements.map(\.type) == [.input, .toolbarIcon])

        let frame = LocalUIElementDetectionService().debugInspectionFrame(from: trace)
        #expect(frame.elements.count == 2)
    }

    @Test
    func structuralWindowDoesNotSwallowChildControls() throws {
        let trace = LocalUIElementDetectionService().detect(
            LocalUIElementDetectionRequest(
                traceID: "trace-window-child",
                pixelSize: HotLoopSize(width: 800, height: 600, space: .screen),
                accessibilityCandidates: [
                    LocalUIElementCandidate(
                        id: "ax-window",
                        source: .accessibility,
                        signalKind: .accessibilityRole,
                        typeHint: .draggable,
                        label: "Music",
                        role: "AXWindow",
                        bounds: HotLoopRect(x: 0, y: 0, width: 800, height: 600, space: .screen),
                        confidence: 0.65,
                        metadata: ["element.kind": "window"]
                    ),
                    LocalUIElementCandidate(
                        id: "ax-search",
                        source: .accessibility,
                        signalKind: .accessibilityRole,
                        typeHint: .input,
                        label: "Search",
                        role: "AXTextField",
                        bounds: HotLoopRect(x: 32, y: 92, width: 240, height: 36, space: .screen),
                        confidence: 1,
                        actions: ["AXSetValue"]
                    )
                ],
                minConfidence: 0.25
            )
        )

        #expect(trace.elements.map(\.id).sorted() == ["ax-search", "ax-window"])
        let search = try #require(trace.elements.first { $0.id == "ax-search" })
        #expect(search.type == .input)
        #expect(search.actionEligibility == .guardedAction)
        #expect(search.sourceCandidateIDs == ["ax-search"])
    }

    @Test
    func debugInspectionFrameSuppressesWindowFrames() {
        let trace = LocalUIElementDetectionTrace(
            traceID: "trace-debug-window-frame-filter",
            candidates: [],
            elements: [
                LocalUIElement(
                    id: "window-1",
                    type: .draggable,
                    label: "Codex",
                    bounds: HotLoopRect(x: 0, y: 0, width: 1600, height: 1000, space: .screen),
                    confidence: 1,
                    sources: [.accessibility],
                    reasonCodes: [],
                    actionEligibility: .readOnlyEvidence,
                    sourceCandidateIDs: ["window-1"]
                )
            ],
            suppressedCandidates: [],
            metrics: LocalUIElementDetectionMetrics()
        )

        let frame = LocalUIElementDetectionService().debugInspectionFrame(from: trace)

        #expect(frame.elements.isEmpty)
    }

}
