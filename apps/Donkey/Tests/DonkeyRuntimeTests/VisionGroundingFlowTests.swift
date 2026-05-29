@testable import DonkeyAI
import DonkeyContracts
import Foundation
import Testing

@Suite
struct VisionGroundingFlowTests {
    private func element(
        id: String,
        type: DebugUIElementType,
        label: String,
        description: String = "",
        x: Double, y: Double, width: Double, height: Double,
        confidence: Double = 0.9
    ) -> DebugUIElement {
        DebugUIElement(
            id: id,
            type: type,
            label: label,
            description: description,
            bbox: DebugUIBoundingBox(x: x, y: y, width: width, height: height),
            confidence: confidence,
            visualStyle: DebugUIOverlayStyle(overlayColor: "#000", borderColor: "#000", labelColor: "#fff"),
            metadata: [:]
        )
    }

    @Test
    func mapsScreenshotPixelBoxToScreenWithRetinaScaling() {
        // 2x Retina screenshot (1600x1200) of a 800x600 window at screen (100, 50).
        let window = WindowTargetBounds(x: 100, y: 50, width: 800, height: 600)
        let bbox = DebugUIBoundingBox(x: 700, y: 100, width: 200, height: 60) // center (800, 130) in image px
        let point = VisionGroundingFlow.screenPoint(bbox: bbox, imageWidth: 1600, imageHeight: 1200, window: window)
        // scaleX=800/1600=0.5, scaleY=600/1200=0.5 → screen (100+400, 50+65) = (500, 115)
        #expect(point.x == 500)
        #expect(point.y == 115)
    }

    @Test
    func resolvesElementByLabelPreferringExactThenConfidence() {
        let elements = [
            element(id: "a", type: .button, label: "Search the web", x: 0, y: 0, width: 10, height: 10, confidence: 0.6),
            element(id: "b", type: .input, label: "Search", x: 20, y: 0, width: 10, height: 10, confidence: 0.9),
            element(id: "c", type: .button, label: "Settings", x: 40, y: 0, width: 10, height: 10)
        ]
        #expect(VisionGroundingFlow.resolveElement("Search", in: elements)?.id == "b")
    }

    @Test
    func ignoresZeroAreaAndUnrelatedElements() {
        let elements = [
            element(id: "ghost", type: .input, label: "Search", x: 0, y: 0, width: 0, height: 0),
            element(id: "other", type: .button, label: "Play", x: 10, y: 10, width: 30, height: 20)
        ]
        #expect(VisionGroundingFlow.resolveElement("Search", in: elements) == nil)
        #expect(VisionGroundingFlow.resolveElement("Play", in: elements)?.id == "other")
    }
}
