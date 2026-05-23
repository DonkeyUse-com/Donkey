import DonkeyAI
import DonkeyContracts
import Foundation
import Testing

@Suite
struct DonkeyBackendInferenceClientTests {
    @Test
    func streamingChatRequestUsesBackendHeadersAndFlattensParameters() throws {
        let client = DonkeyBackendInferenceClient(
            configuration: configuration(),
            httpClient: FixtureHTTPClient(data: Data("{}".utf8), statusCode: 200)
        )
        let request = try client.makeStreamingChatRequest(
            RemoteInferenceChatCompletionRequest(
                model: "router/large",
                messages: [
                    RemoteInferenceChatMessage(role: "user", content: .string("hello"))
                ],
                parameters: [
                    "temperature": .number(0.2)
                ]
            )
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpShouldHandleCookies == true)
        #expect(request.value(forHTTPHeaderField: "x-donkey-client-id") == "client-1")
        #expect(request.url?.path == "/api/inference/chat/completions/")

        let object = try #require(request.httpBodyJSONObject)
        #expect(object["stream"] as? Bool == true)
        #expect(object["temperature"] as? Double == 0.2)
        #expect(object["model"] as? String == "router/large")
    }

    @Test
    func decodesServerSentEvents() {
        let data = Data(
            """
            id: one
            event: message
            data: {"delta":"hi"}

            data: [DONE]

            """.utf8
        )

        let events = DonkeyBackendInferenceClient.decodeServerSentEvents(data)

        #expect(events.count == 2)
        #expect(events.first?.id == "one")
        #expect(events.first?.event == "message")
        #expect(events.first?.data == #"{"delta":"hi"}"#)
        #expect(events.last?.data == "[DONE]")
    }

    @Test
    func downloadsInlineOutputsIntoGenerationDirectory() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("donkey-inference-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: baseDirectory)
        }

        let client = DonkeyBackendInferenceClient(
            configuration: configuration(),
            httpClient: FixtureHTTPClient(data: Data(), statusCode: 200)
        )
        let record = generationRecord(
            outputs: [
                RemoteInferenceOutputRef(
                    id: "audio-1",
                    kind: .audio,
                    dataBase64: Data("first".utf8).base64EncodedString(),
                    contentType: "audio/mpeg",
                    filename: "bad/name.mp3"
                ),
                RemoteInferenceOutputRef(
                    id: "audio-2",
                    kind: .audio,
                    dataBase64: Data("second".utf8).base64EncodedString(),
                    contentType: "audio/mpeg",
                    filename: "bad/name.mp3"
                )
            ]
        )

        let downloads = try await client.downloadCompletedOutputs(
            for: record,
            downloadsDirectory: baseDirectory
        )

        #expect(downloads.map { $0.fileURL.lastPathComponent } == ["bad-name.mp3", "bad-name-2.mp3"])
        #expect(try String(contentsOf: downloads[0].fileURL, encoding: .utf8) == "first")
        #expect(try String(contentsOf: downloads[1].fileURL, encoding: .utf8) == "second")
        #expect(downloads[0].fileURL.path.contains("/Donkey/generation-1/"))
        #expect(downloads[0].pointerPromptAssetDraft().source == .agentReturned)
    }

    @Test
    func backendOutputDownloadsUseDonkeyClientHeadersAndCookies() async throws {
        let httpClient = FixtureHTTPClient(
            data: Data("downloaded".utf8),
            statusCode: 200,
            headerFields: ["Content-Type": "video/mp4"]
        )
        let client = DonkeyBackendInferenceClient(
            configuration: configuration(),
            httpClient: httpClient
        )
        let record = generationRecord(
            outputs: [
                RemoteInferenceOutputRef(
                    id: "video-1",
                    kind: .video,
                    downloadUrl: "/api/inference/assets/generation-1/outputs/video-1",
                    contentType: "video/mp4",
                    filename: "video.mp4"
                )
            ]
        )
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("donkey-inference-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: baseDirectory)
        }

        let downloads = try await client.downloadCompletedOutputs(
            for: record,
            downloadsDirectory: baseDirectory
        )

        #expect(downloads.first?.contentType == "video/mp4")
        #expect(httpClient.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(httpClient.requests.first?.httpShouldHandleCookies == true)
        #expect(httpClient.requests.first?.value(forHTTPHeaderField: "x-donkey-client-id") == "client-1")
    }

    private func configuration() -> DonkeyBackendInferenceConfiguration {
        DonkeyBackendInferenceConfiguration(
            baseURL: URL(string: "https://donkey.example")!,
            clientID: "client-1"
        )
    }

    private func generationRecord(
        outputs: [RemoteInferenceOutputRef]
    ) -> RemoteInferenceGenerationRecord {
        RemoteInferenceGenerationRecord(
            id: "generation-1",
            clientId: "client-1",
            kind: "music",
            status: .completed,
            provider: "provider-data",
            model: "asset-model",
            providerJobId: nil,
            providerGenerationId: nil,
            providerPollingUrl: nil,
            promptPreview: "make audio",
            requestHash: "hash",
            outputs: outputs,
            usage: nil,
            error: nil,
            metadata: .object([:]),
            createdAt: "2026-05-22T00:00:00.000Z",
            updatedAt: "2026-05-22T00:00:00.000Z",
            completedAt: "2026-05-22T00:00:00.000Z"
        )
    }
}

private final class FixtureHTTPClient: AIHTTPClient, @unchecked Sendable {
    var data: Data
    var statusCode: Int
    var headerFields: [String: String]
    var requests: [URLRequest] = []

    init(data: Data, statusCode: Int, headerFields: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headerFields = headerFields
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headerFields
            )!
        )
    }
}

private extension URLRequest {
    var httpBodyJSONObject: [String: Any]? {
        guard let httpBody,
              let object = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        else {
            return nil
        }

        return object
    }
}
