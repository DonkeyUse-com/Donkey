import DonkeyAI
import DonkeyContracts
import DonkeyRuntime
import CoreGraphics
import Foundation
import Testing

@Suite
struct DebugUIInspectionTests {
    @Test
    func missingConfigDisablesOverlay() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("missing-dev-overlay.json", isDirectory: false)

        let config = DebugUIOverlayConfiguration.load(fileURL: url)

        #expect(config.enabled == false)
        #expect(config.provider == .openai)
        #expect(config.screenScope == .main)
    }

    @Test
    func invalidConfigDisablesOverlay() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("invalid-dev-overlay.json", isDirectory: false)
        try Data("{".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = DebugUIOverlayConfiguration.load(fileURL: url)

        #expect(config.enabled == false)
    }

    @Test
    func enabledConfigUsesSafeDefaults() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("enabled-dev-overlay.json", isDirectory: false)
        try Data(#"{"enabled":true}"#.utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = DebugUIOverlayConfiguration.load(fileURL: url)

        #expect(config.enabled == true)
        #expect(config.provider == .openai)
        #expect(config.cadenceSeconds == 1.0)
        #expect(config.screenScope == .main)
        #expect(config.minConfidence == 0.25)
    }

    @Test
    func disabledRepoStyleConfigKeepsOverlayOff() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("disabled-dev-overlay.json", isDirectory: false)
        try Data(
            """
            {
              "enabled": false,
              "provider": "gemini",
              "cadenceSeconds": 0.05,
              "screenScope": "all",
              "minConfidence": 2
            }
            """.utf8
        ).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = DebugUIOverlayConfiguration.load(fileURL: url)

        #expect(config.enabled == false)
        #expect(config.provider == .gemini)
        #expect(config.cadenceSeconds == 0.25)
        #expect(config.screenScope == .all)
        #expect(config.minConfidence == 1)
    }

    @Test
    func debugCandidateConfigURLsIncludeEnvironmentOverride() {
        let path = temporaryDirectory()
            .appendingPathComponent("custom-dev-overlay.json", isDirectory: false)
            .path

        let urls = DebugUIOverlayConfiguration.candidateConfigURLs(
            environment: ["DONKEY_DEV_OVERLAY_CONFIG": path]
        )

        #expect(urls.map(\.path).contains(path))
    }

    @Test
    func inspectionResponseDecodesAndFiltersElements() throws {
        let response = RemoteInferenceJSONValue.object([
            "output_text": .string(
                """
                {"elements":[
                  {"id":"save","type":"button","label":"Save","description":"Saves","bbox":{"x":10,"y":20,"width":80,"height":30},"confidence":1.5,"visual_style":{"overlay_color":"#3B82F6","border_color":"#60A5FA","label_color":"#FFFFFF"}},
                  {"id":"low","type":"link","label":"Low","description":"","bbox":{"x":0,"y":0,"width":10,"height":10},"confidence":0.1,"visual_style":{"overlay_color":"#06B6D4","border_color":"#67E8F9","label_color":"#FFFFFF"}}
                ]}
                """
            )
        ])

        let frame = try DebugUIInspectionResponseDecoder.decode(response, minConfidence: 0.25)

        #expect(frame.elements.map(\.id) == ["save"])
        #expect(frame.elements.first?.confidence == 1.0)
        #expect(frame.elements.first?.visualStyle == DebugUIOverlayStyle.style(for: .button))
    }

    @Test
    func inspectionResponseRejectsProviderActions() {
        let response = RemoteInferenceJSONValue.object([
            "output": .array([
                .object([
                    "type": .string("function_call"),
                    "name": .string("click_at")
                ])
            ])
        ])

        #expect(throws: DebugUIInspectionHostedAdapterError.providerReturnedAction) {
            _ = try DebugUIInspectionResponseDecoder.decode(response)
        }
    }

    @Test
    func trackerPreservesStableIDForMovedSemanticMatch() {
        var tracker = DebugUIElementTracker()
        _ = tracker.update(with: DebugUIInspectionFrame(elements: [
            element(id: "button-1", label: "Save", x: 10, y: 20)
        ]))

        let updated = tracker.update(with: DebugUIInspectionFrame(elements: [
            element(id: "provider-new-id", label: "Save", x: 36, y: 24)
        ]))

        #expect(updated.elements.first?.id == "button-1")
    }

    @Test
    func geometryConvertsScreenshotPixelsToAppKitPoints() {
        let frame = DebugUIOverlayGeometry.appKitFrame(
            for: DebugUIBoundingBox(x: 200, y: 100, width: 400, height: 200),
            screenshotPixelSize: HotLoopSize(width: 2000, height: 1000, space: .screen),
            screenFrame: HotLoopRect(x: 0, y: 0, width: 1000, height: 500, space: .screen)
        )

        #expect(frame == CGRect(x: 100, y: 350, width: 200, height: 100))
    }

    private func element(
        id: String,
        label: String,
        x: Double,
        y: Double
    ) -> DebugUIElement {
        DebugUIElement(
            id: id,
            type: .button,
            label: label,
            bbox: DebugUIBoundingBox(x: x, y: y, width: 80, height: 30),
            confidence: 0.9
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("donkey-debug-ui-tests", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
