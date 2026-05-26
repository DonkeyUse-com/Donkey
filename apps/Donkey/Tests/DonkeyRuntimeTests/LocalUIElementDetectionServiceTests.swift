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
}
