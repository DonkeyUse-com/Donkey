import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct LocalRunArtifactStoreTests {
    @Test
    func prepareRunCreatesTraceLayoutAndSummary() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let session = RunSession(
            id: "run-1",
            userGoal: "capture context",
            targetID: "target-1"
        )

        let summary = try await store.prepareRun(session: session, traceID: "trace-1")
        let runDirectory = root.appendingPathComponent("run-1", isDirectory: true)

        #expect(summary.runID == "run-1")
        #expect(summary.traceID == "trace-1")
        #expect(summary.eventCount == 0)
        #expect(summary.artifacts.isEmpty)
        #expect(fileExists(runDirectory.appendingPathComponent("events.jsonl")))
        #expect(fileExists(runDirectory.appendingPathComponent("summary.json")))
        #expect(directoryExists(runDirectory.appendingPathComponent("screenshots")))
        #expect(directoryExists(runDirectory.appendingPathComponent("accessibility")))

        let storedSummary = try await store.summary(runID: "run-1")
        #expect(storedSummary == summary)
    }

    @Test
    func appendEventWritesJsonlInCallOrderAndUpdatesSummary() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let session = RunSession(
            id: "run-events",
            userGoal: "record events",
            targetID: "target-1"
        )
        _ = try await store.prepareRun(session: session, traceID: "trace-events")

        let firstEvent = RunEvent(
            sequence: 1,
            stream: .tool,
            summary: "capture tool call allowed",
            payload: .tool(
                ToolRunEvent(
                    capability: .capture,
                    decision: .allow,
                    toolName: "manual-capture"
                )
            )
        )
        let secondEvent = RunEvent(
            sequence: 2,
            stream: .lifecycle,
            summary: "Run completed",
            payload: .lifecycle(
                LifecycleRunEvent(state: .completed, reason: "capture complete")
            )
        )

        _ = try await store.appendEvent(firstEvent, runID: "run-events")
        _ = try await store.appendEvent(secondEvent, runID: "run-events")

        let eventsURL = root
            .appendingPathComponent("run-events", isDirectory: true)
            .appendingPathComponent("events.jsonl")
        let records = try jsonlRecords(from: eventsURL)

        #expect(records.map(\.event.sequence) == [1, 2])
        #expect(records.map(\.event.summary) == [
            "capture tool call allowed",
            "Run completed"
        ])
        #expect(records.allSatisfy { $0.runID == "run-events" })
        #expect(records.allSatisfy { $0.traceID == "trace-events" })

        let summary = try await store.summary(runID: "run-events")
        #expect(summary.eventCount == 2)
    }

    @Test
    func recordArtifactUsesSafeRelativePathAndUpdatesSummary() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let session = RunSession(
            id: "run-artifact",
            userGoal: "record artifact",
            targetID: "target-1"
        )
        _ = try await store.prepareRun(session: session, traceID: "trace-artifact")

        let reservedPath = try await store.reserveArtifactPath(
            runID: "run-artifact",
            artifactID: "screenshot-1",
            kind: .screenshot,
            fileExtension: "png"
        )
        let record = try await store.recordArtifact(
            runID: "run-artifact",
            artifactID: reservedPath.artifactID,
            kind: .screenshot,
            relativePath: reservedPath.relativePath,
            contentType: "image/png",
            byteCount: 42,
            metadata: ["target": "target-1"]
        )

        #expect(reservedPath.relativePath == "screenshots/screenshot-1.png")
        #expect(reservedPath.fileURL == root
            .appendingPathComponent("run-artifact", isDirectory: true)
            .appendingPathComponent("screenshots/screenshot-1.png"))
        #expect(record.relativePath == "screenshots/screenshot-1.png")
        #expect(record.kind == .screenshot)
        #expect(record.contentType == "image/png")
        #expect(record.byteCount == 42)

        let summary = try await store.summary(runID: "run-artifact")
        #expect(summary.artifacts == [record])
    }

    @Test
    func unsafeRunIdentifiersAreRejected() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let session = RunSession(
            id: "../bad",
            userGoal: "escape",
            targetID: "target-1"
        )

        do {
            _ = try await store.prepareRun(session: session, traceID: "trace-1")
            Issue.record("Expected unsafe run id to be rejected")
        } catch LocalRunArtifactStoreError.invalidIdentifier(let value) {
            #expect(value == "../bad")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func unsafeArtifactPathsAreRejected() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LocalRunArtifactStore(baseDirectory: root)
        let session = RunSession(
            id: "run-unsafe-artifact",
            userGoal: "record artifact",
            targetID: "target-1"
        )
        _ = try await store.prepareRun(session: session, traceID: "trace-1")

        do {
            _ = try await store.recordArtifact(
                runID: "run-unsafe-artifact",
                artifactID: "artifact-1",
                kind: .screenshot,
                relativePath: "../artifact-1.png",
                contentType: "image/png",
                byteCount: 1
            )
            Issue.record("Expected unsafe artifact path to be rejected")
        } catch LocalRunArtifactStoreError.unsafeRelativePath(let value) {
            #expect(value == "../artifact-1.png")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func defaultBaseDirectoryUsesApplicationSupportDonkeyRuns() throws {
        let baseDirectory = try LocalRunArtifactStore.defaultBaseDirectory()
        let path = baseDirectory.path

        #expect(path.contains("Application Support"))
        #expect(path.hasSuffix("Donkey/Runs"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "DonkeyArtifactStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private func jsonlRecords(from url: URL) throws -> [RunTraceEventRecord] {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        return try text
            .split(separator: "\n")
            .map { line in
                try JSONDecoder().decode(
                    RunTraceEventRecord.self,
                    from: Data(line.utf8)
                )
            }
    }
}
