import DonkeyContracts
import Foundation

public enum DebugUIInspectionHostedAdapterError: Error, Equatable, Sendable {
    case providerReturnedAction
    case missingOutputText
    case invalidJSON(String)
}

public struct DebugUIInspectionRequest: Equatable, Sendable {
    public var provider: DebugUIInspectionProvider
    public var screenshotBase64: String
    public var pixelSize: HotLoopSize
    public var minConfidence: Double
    public var metadata: [String: String]

    public init(
        provider: DebugUIInspectionProvider,
        screenshotBase64: String,
        pixelSize: HotLoopSize,
        minConfidence: Double = 0.25,
        metadata: [String: String] = [:]
    ) {
        self.provider = provider
        self.screenshotBase64 = screenshotBase64
        self.pixelSize = pixelSize
        self.minConfidence = min(max(minConfidence, 0), 1)
        self.metadata = metadata
    }
}

public protocol DebugUIInspectionAnalyzing: Sendable {
    func inspect(_ request: DebugUIInspectionRequest) async throws -> DebugUIInspectionFrame
}

public struct HostedDebugUIInspectionAnalyzer: DebugUIInspectionAnalyzing {
    public var backend: DonkeyBackendInferenceClient
    public var decoder: JSONDecoder

    public init(
        backend: DonkeyBackendInferenceClient,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.backend = backend
        self.decoder = decoder
    }

    public func inspect(_ request: DebugUIInspectionRequest) async throws -> DebugUIInspectionFrame {
        let response = try await backend.createResponse(responseRequest(for: request))
        return try DebugUIInspectionResponseDecoder.decode(
            response,
            decoder: decoder,
            minConfidence: request.minConfidence
        )
    }

    private func responseRequest(
        for request: DebugUIInspectionRequest
    ) -> RemoteInferenceResponseCreateRequest {
        RemoteInferenceResponseCreateRequest(
            donkeyProvider: request.provider.rawValue,
            input: .array([
                .object([
                    "role": .string("user"),
                    "content": .array([
                        .object([
                            "type": .string("input_text"),
                            "text": .string(Self.prompt)
                        ]),
                        .object([
                            "type": .string("input_image"),
                            "image_url": .string("data:image/png;base64,\(request.screenshotBase64)")
                        ])
                    ])
                ])
            ]),
            store: false,
            text: Self.responseFormat,
            tools: [
                RemoteInferenceComputerUseTool(
                    type: .debugUIInspection,
                    excludedPredefinedFunctions: Self.excludedActionNames,
                    metadata: [
                        "mode": "read_only",
                        "schema": "debug_ui_inspection_v1"
                    ]
                ).jsonObject
            ],
            metadata: request.metadata.merging([
                "source": "debug-ui-inspection-overlay",
                "prompt_version": "debug-ui-inspection-v1",
                "privacy.store": "false",
                "screenshot.width": String(request.pixelSize.width),
                "screenshot.height": String(request.pixelSize.height)
            ]) { current, _ in current },
            parameters: [
                "temperature": .number(0),
                "max_output_tokens": .number(8_000)
            ]
        )
    }

    private static let prompt = """
    You are a read-only macOS UI inspection model. Analyze the screenshot and return ONLY valid JSON.

    Detect visible user-interactable UI elements. Include window controls, buttons, links, tabs, menu items, dropdowns, text inputs, search fields, checkboxes, radios, toggles, sliders, toolbar icons, sidebar items, Dock items, menu bar items, table rows, list items, tree items, clickable cards, draggable handles, resize handles, scrollbars, split panes, canvas interaction regions, floating action buttons, and icon-only controls. Prefer over-detecting interactable elements over missing them.

    Do not include static text, decorative graphics, separators, backgrounds, or non-interactable containers unless they are clearly interactive.

    Coordinates must be screenshot pixel coordinates with origin at top-left. Bounding boxes must tightly fit the clickable region. If an element is partially obscured, include it with lower confidence. Infer labels for icon-only controls when possible.

    Do not click, type, scroll, drag, navigate, call tools, or propose actions. This is visual inspection only.

    Return exactly:
    {"elements":[{"id":"stable_unique_id","type":"button","label":"Save","description":"Saves current document","bbox":{"x":120,"y":340,"width":88,"height":32},"confidence":0.98,"visual_style":{"overlay_color":"#3B82F6","border_color":"#60A5FA","label_color":"#FFFFFF"}}]}
    """

    private static let excludedActionNames = [
        "click",
        "click_at",
        "double_click",
        "drag",
        "drag_and_drop",
        "go_back",
        "go_forward",
        "hover",
        "hover_at",
        "key_combination",
        "navigate",
        "open_web_browser",
        "scroll",
        "scroll_document",
        "search",
        "type",
        "type_text",
        "type_text_at"
    ]

    private static let responseFormat: RemoteInferenceJSONObject = [
        "format": .object([
            "type": .string("json_schema"),
            "name": .string("debug_ui_inspection_v1"),
            "strict": .bool(true),
            "schema": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([.string("elements")]),
                "properties": .object([
                    "elements": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "required": .array([
                                .string("id"),
                                .string("type"),
                                .string("label"),
                                .string("description"),
                                .string("bbox"),
                                .string("confidence"),
                                .string("visual_style")
                            ]),
                            "properties": .object([
                                "id": .object(["type": .string("string")]),
                                "type": .object([
                                    "type": .string("string"),
                                    "enum": .array(DebugUIElementType.allCases.map { .string($0.rawValue) })
                                ]),
                                "label": .object(["type": .string("string")]),
                                "description": .object(["type": .string("string")]),
                                "bbox": .object([
                                    "type": .string("object"),
                                    "additionalProperties": .bool(false),
                                    "required": .array([
                                        .string("x"),
                                        .string("y"),
                                        .string("width"),
                                        .string("height")
                                    ]),
                                    "properties": .object([
                                        "x": .object(["type": .string("number")]),
                                        "y": .object(["type": .string("number")]),
                                        "width": .object(["type": .string("number")]),
                                        "height": .object(["type": .string("number")])
                                    ])
                                ]),
                                "confidence": .object([
                                    "type": .string("number"),
                                    "minimum": .number(0),
                                    "maximum": .number(1)
                                ]),
                                "visual_style": .object([
                                    "type": .string("object"),
                                    "additionalProperties": .bool(false),
                                    "required": .array([
                                        .string("overlay_color"),
                                        .string("border_color"),
                                        .string("label_color")
                                    ]),
                                    "properties": .object([
                                        "overlay_color": .object(["type": .string("string")]),
                                        "border_color": .object(["type": .string("string")]),
                                        "label_color": .object(["type": .string("string")])
                                    ])
                                ])
                            ])
                        ])
                    ])
                ])
            ])
        ])
    ]
}

public enum DebugUIInspectionResponseDecoder {
    public static func decode(
        _ response: RemoteInferenceJSONValue,
        decoder: JSONDecoder = JSONDecoder(),
        minConfidence: Double = 0.25
    ) throws -> DebugUIInspectionFrame {
        guard containsActionOutput(response) == false else {
            throw DebugUIInspectionHostedAdapterError.providerReturnedAction
        }

        let frameData: Data
        if let object = response.objectValue,
           object["elements"] != nil {
            frameData = try JSONEncoder().encode(response)
        } else {
            guard let outputText = outputText(from: response),
                  !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw DebugUIInspectionHostedAdapterError.missingOutputText
            }
            frameData = Data(outputText.utf8)
        }

        do {
            return try decoder.decode(DebugUIInspectionFrame.self, from: frameData)
                .validated(minConfidence: minConfidence)
        } catch {
            throw DebugUIInspectionHostedAdapterError.invalidJSON(String(describing: error))
        }
    }

    public static func containsActionOutput(_ value: RemoteInferenceJSONValue) -> Bool {
        switch value {
        case .string(let text):
            return actionMarkers.contains { text.contains($0) }
        case .number, .bool, .null:
            return false
        case .array(let values):
            return values.contains(where: containsActionOutput)
        case .object(let object):
            if let type = object["type"]?.stringValue,
               actionTypes.contains(type) {
                return true
            }
            if object["functionCall"] != nil ||
                object["function_call"] != nil ||
                object["computer_call"] != nil {
                return true
            }
            return object.values.contains(where: containsActionOutput)
        }
    }

    private static func outputText(from value: RemoteInferenceJSONValue) -> String? {
        guard let object = value.objectValue else {
            return nil
        }

        if let text = object["output_text"]?.stringValue {
            return text
        }

        return object["output"]?.arrayValue?
            .compactMap(messageText)
            .joined(separator: "\n")
    }

    private static func messageText(from value: RemoteInferenceJSONValue) -> String? {
        guard let object = value.objectValue else {
            return nil
        }
        if let text = object["text"]?.stringValue {
            return text
        }
        return object["content"]?.arrayValue?
            .compactMap { content in
                guard let contentObject = content.objectValue else { return nil }
                return contentObject["text"]?.stringValue
            }
            .joined(separator: "\n")
    }

    private static let actionTypes = Set([
        "computer_call",
        "computer_call_output",
        "function_call"
    ])

    private static let actionMarkers = [
        "\"type\":\"computer_call\"",
        "\"type\":\"function_call\"",
        "\"functionCall\"",
        "\"function_call\""
    ]
}
