import DonkeyContracts
import Foundation

public enum LocalRunArtifactStoreError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case missingSummary(String)
    case unsafeRelativePath(String)
}

public struct LocalRunArtifactPath: Equatable, Sendable {
    public var artifactID: String
    public var relativePath: String
    public var fileURL: URL

    public init(artifactID: String, relativePath: String, fileURL: URL) {
        self.artifactID = artifactID
        self.relativePath = relativePath
        self.fileURL = fileURL
    }
}

public actor LocalRunArtifactStore {
    private let baseDirectory: URL
    private let fileManager: FileManager

    public init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.baseDirectory = try baseDirectory ?? Self.defaultBaseDirectory(fileManager: fileManager)
    }

    public static func defaultBaseDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        return applicationSupport
            .appendingPathComponent("Donkey", isDirectory: true)
            .appendingPathComponent("Runs", isDirectory: true)
    }

    @discardableResult
    public func prepareRun(
        session: RunSession,
        traceID: String = UUID().uuidString
    ) throws -> RunTraceSummary {
        try validateIdentifier(session.id)
        try validateIdentifier(traceID)

        let runDirectory = try runDirectory(for: session.id)
        try fileManager.createDirectory(
            at: runDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: runDirectory.appendingPathComponent("screenshots", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: runDirectory.appendingPathComponent("accessibility", isDirectory: true),
            withIntermediateDirectories: true
        )

        let eventsURL = eventsURL(forRunDirectory: runDirectory)
        if !fileManager.fileExists(atPath: eventsURL.path) {
            try Data().write(to: eventsURL, options: .atomic)
        }

        let now = makeTimestamp()
        let summary = RunTraceSummary(
            runID: session.id,
            traceID: traceID,
            session: session,
            startedAt: now,
            updatedAt: now
        )

        try writeSummary(summary)
        return summary
    }

    @discardableResult
    public func appendEvent(
        _ event: RunEvent,
        runID: String
    ) throws -> RunTraceEventRecord {
        var summary = try summary(runID: runID)
        let record = RunTraceEventRecord(
            runID: summary.runID,
            traceID: summary.traceID,
            recordedAt: makeTimestamp(),
            event: event
        )
        var line = try Self.encoder().encode(record)
        line.append(0x0A)

        let eventsURL = try runDirectory(for: runID).appendingPathComponent(
            "events.jsonl",
            isDirectory: false
        )
        let handle = try FileHandle(forWritingTo: eventsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)

        summary.eventCount += 1
        summary.updatedAt = record.recordedAt
        try writeSummary(summary)

        return record
    }

    public func reserveArtifactPath(
        runID: String,
        artifactID: String,
        kind: RunArtifactKind,
        fileExtension: String
    ) throws -> LocalRunArtifactPath {
        try validateIdentifier(runID)
        try validateIdentifier(artifactID)

        let sanitizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        try validateIdentifier(sanitizedExtension)

        let relativePath = "\(kind.directoryName)/\(artifactID).\(sanitizedExtension)"
        try validateRelativePath(relativePath, expectedDirectory: kind.directoryName)

        let fileURL = try runDirectory(for: runID).appendingPathComponent(
            relativePath,
            isDirectory: false
        )
        return LocalRunArtifactPath(
            artifactID: artifactID,
            relativePath: relativePath,
            fileURL: fileURL
        )
    }

    @discardableResult
    public func recordArtifact(
        runID: String,
        artifactID: String,
        kind: RunArtifactKind,
        relativePath: String,
        contentType: String,
        byteCount: Int64,
        metadata: [String: String] = [:]
    ) throws -> RunArtifactRecord {
        try validateIdentifier(artifactID)
        try validateRelativePath(relativePath, expectedDirectory: kind.directoryName)

        var summary = try summary(runID: runID)
        let record = RunArtifactRecord(
            artifactID: artifactID,
            kind: kind,
            relativePath: relativePath,
            contentType: contentType,
            byteCount: byteCount,
            createdAt: makeTimestamp(),
            metadata: metadata
        )

        summary.artifacts.append(record)
        summary.updatedAt = record.createdAt
        try writeSummary(summary)

        return record
    }

    public func summary(runID: String) throws -> RunTraceSummary {
        try validateIdentifier(runID)

        let url = try summaryURL(for: runID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw LocalRunArtifactStoreError.missingSummary(runID)
        }

        let data = try Data(contentsOf: url)
        return try Self.decoder().decode(RunTraceSummary.self, from: data)
    }

    public func runDirectory(for runID: String) throws -> URL {
        try validateIdentifier(runID)
        return baseDirectory.appendingPathComponent(runID, isDirectory: true)
    }

    private func writeSummary(_ summary: RunTraceSummary) throws {
        let data = try Self.encoder().encode(summary)
        try data.write(to: try summaryURL(for: summary.runID), options: .atomic)
    }

    private func summaryURL(for runID: String) throws -> URL {
        try runDirectory(for: runID).appendingPathComponent("summary.json", isDirectory: false)
    }

    private func eventsURL(forRunDirectory runDirectory: URL) -> URL {
        runDirectory.appendingPathComponent("events.jsonl", isDirectory: false)
    }

    private func validateIdentifier(_ value: String) throws {
        let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let isSafe = !value.isEmpty
            && value.count <= 128
            && value != "."
            && value != ".."
            && value.unicodeScalars.allSatisfy { allowedScalars.contains($0) }

        guard isSafe else {
            throw LocalRunArtifactStoreError.invalidIdentifier(value)
        }
    }

    private func validateRelativePath(
        _ relativePath: String,
        expectedDirectory: String
    ) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        let isSafe = !relativePath.isEmpty
            && !relativePath.hasPrefix("/")
            && !relativePath.contains("\\")
            && components.count == 2
            && components.first.map(String.init) == expectedDirectory
            && components.allSatisfy { component in
                !component.isEmpty && component != "." && component != ".."
            }

        guard isSafe else {
            throw LocalRunArtifactStoreError.unsafeRelativePath(relativePath)
        }
    }

    private func makeTimestamp() -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(),
            monotonicUptimeNanoseconds: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        )
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
