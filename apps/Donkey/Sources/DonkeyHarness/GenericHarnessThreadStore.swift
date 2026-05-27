import DonkeyContracts
import Foundation

public enum HarnessThreadEventRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
    case tool
    case lifecycle
    case summary
}

public struct HarnessThread: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: HarnessTaskStatus
    public var activeTaskIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        title: String,
        status: HarnessTaskStatus = .running,
        activeTaskIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.activeTaskIDs = activeTaskIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

public struct HarnessThreadEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var threadID: String
    public var taskID: String?
    public var role: HarnessThreadEventRole
    public var text: String
    public var sequence: Int
    public var isPinned: Bool
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        threadID: String,
        taskID: String? = nil,
        role: HarnessThreadEventRole,
        text: String,
        sequence: Int,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.threadID = threadID
        self.taskID = taskID
        self.role = role
        self.text = text
        self.sequence = sequence
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct HarnessThreadAsset: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var threadID: String
    public var taskID: String?
    public var eventID: String?
    public var displayName: String
    public var contentType: String
    public var urlString: String
    public var byteCount: Int64?
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        threadID: String,
        taskID: String? = nil,
        eventID: String? = nil,
        displayName: String,
        contentType: String,
        urlString: String,
        byteCount: Int64? = nil,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.threadID = threadID
        self.taskID = taskID
        self.eventID = eventID
        self.displayName = displayName
        self.contentType = contentType
        self.urlString = urlString
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public protocol HarnessThreadStoring: Sendable {
    func upsertThread(_ thread: HarnessThread) async
    func thread(id: String) async -> HarnessThread?
    func recentThreads(limit: Int) async -> [HarnessThread]
    func appendEvent(_ event: HarnessThreadEvent) async
    func events(threadID: String) async -> [HarnessThreadEvent]
    func appendAsset(_ asset: HarnessThreadAsset) async
    func assets(threadID: String) async -> [HarnessThreadAsset]
}

public actor InMemoryHarnessThreadStore: HarnessThreadStoring {
    private var threadsByID: [String: HarnessThread] = [:]
    private var eventsByThreadID: [String: [HarnessThreadEvent]] = [:]
    private var assetsByThreadID: [String: [HarnessThreadAsset]] = [:]

    public init() {}

    public func upsertThread(_ thread: HarnessThread) {
        threadsByID[thread.id] = thread
    }

    public func thread(id: String) -> HarnessThread? {
        threadsByID[id]
    }

    public func recentThreads(limit: Int) -> [HarnessThread] {
        threadsByID.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public func appendEvent(_ event: HarnessThreadEvent) {
        var events = eventsByThreadID[event.threadID] ?? []
        events.append(event)
        events.sort {
            if $0.sequence == $1.sequence {
                return $0.createdAt < $1.createdAt
            }
            return $0.sequence < $1.sequence
        }
        eventsByThreadID[event.threadID] = events
    }

    public func events(threadID: String) -> [HarnessThreadEvent] {
        eventsByThreadID[threadID] ?? []
    }

    public func appendAsset(_ asset: HarnessThreadAsset) {
        var assets = assetsByThreadID[asset.threadID] ?? []
        assets.append(asset)
        assets.sort { $0.createdAt < $1.createdAt }
        assetsByThreadID[asset.threadID] = assets
    }

    public func assets(threadID: String) -> [HarnessThreadAsset] {
        assetsByThreadID[threadID] ?? []
    }
}

public struct HarnessCompactionPolicy: Codable, Equatable, Sendable {
    public var maxEvents: Int
    public var maxPinnedEvents: Int
    public var maxToolEvents: Int
    public var maxAssets: Int
    public var maxEventCharacters: Int
    public var maxPromptCharacters: Int
    public var preserveWaitingState: Bool

    public init(
        maxEvents: Int = 12,
        maxPinnedEvents: Int = 6,
        maxToolEvents: Int = 4,
        maxAssets: Int = 6,
        maxEventCharacters: Int = 1_000,
        maxPromptCharacters: Int = 8_000,
        preserveWaitingState: Bool = true
    ) {
        self.maxEvents = max(0, maxEvents)
        self.maxPinnedEvents = max(0, maxPinnedEvents)
        self.maxToolEvents = max(0, maxToolEvents)
        self.maxAssets = max(0, maxAssets)
        self.maxEventCharacters = max(1, maxEventCharacters)
        self.maxPromptCharacters = max(1, maxPromptCharacters)
        self.preserveWaitingState = preserveWaitingState
    }
}

public struct HarnessCompactedThreadContext: Codable, Equatable, Sendable {
    public var thread: HarnessThread
    public var currentTurn: AppHarnessTurn?
    public var events: [HarnessThreadEvent]
    public var assets: [HarnessThreadAsset]
    public var activeTasks: [HarnessTaskState]
    public var promptText: String
    public var compactionRecords: [AppHarnessContextCompactionRecord]
    public var metadata: [String: String]

    public init(
        thread: HarnessThread,
        currentTurn: AppHarnessTurn? = nil,
        events: [HarnessThreadEvent],
        assets: [HarnessThreadAsset],
        activeTasks: [HarnessTaskState],
        promptText: String,
        compactionRecords: [AppHarnessContextCompactionRecord],
        metadata: [String: String] = [:]
    ) {
        self.thread = thread
        self.currentTurn = currentTurn
        self.events = events
        self.assets = assets
        self.activeTasks = activeTasks
        self.promptText = promptText
        self.compactionRecords = compactionRecords
        self.metadata = metadata
    }
}

public struct HarnessThreadCompactor: Sendable {
    public var policy: HarnessCompactionPolicy

    public init(policy: HarnessCompactionPolicy = HarnessCompactionPolicy()) {
        self.policy = policy
    }

    public func compact(
        thread: HarnessThread,
        currentTurn: AppHarnessTurn? = nil,
        events: [HarnessThreadEvent],
        assets: [HarnessThreadAsset],
        activeTasks: [HarnessTaskState]
    ) -> HarnessCompactedThreadContext {
        var records: [AppHarnessContextCompactionRecord] = []
        let selectedEvents = compactEvents(events, records: &records)
        let selectedAssets = Array(assets.sorted { $0.createdAt > $1.createdAt }.prefix(policy.maxAssets))
            .sorted { $0.createdAt < $1.createdAt }
        records.append(
            AppHarnessContextCompactionRecord(
                itemKind: .asset,
                originalCount: assets.count,
                includedCount: selectedAssets.count,
                droppedCount: max(0, assets.count - selectedAssets.count)
            )
        )

        let selectedTasks = compactTasks(activeTasks, records: &records)
        let unboundedPrompt = promptText(
            thread: thread,
            currentTurn: currentTurn,
            events: selectedEvents,
            assets: selectedAssets,
            activeTasks: selectedTasks
        )
        let boundedPrompt = bounded(unboundedPrompt, maxCharacters: policy.maxPromptCharacters)
        records.append(
            AppHarnessContextCompactionRecord(
                itemKind: .currentTurn,
                originalCount: unboundedPrompt.count,
                includedCount: boundedPrompt.count,
                truncatedCount: unboundedPrompt.count > boundedPrompt.count ? 1 : 0,
                metadata: ["unit": "characters"]
            )
        )

        return HarnessCompactedThreadContext(
            thread: thread,
            currentTurn: currentTurn,
            events: selectedEvents,
            assets: selectedAssets,
            activeTasks: selectedTasks,
            promptText: boundedPrompt,
            compactionRecords: records,
            metadata: [
                "threadStore": "generic-harness",
                "compactor": "smart-priority-v1",
                "promptTruncated": String(unboundedPrompt.count > boundedPrompt.count),
                "eventCount": String(selectedEvents.count),
                "assetCount": String(selectedAssets.count),
                "activeTaskCount": String(selectedTasks.count)
            ]
        )
    }

    private func compactEvents(
        _ events: [HarnessThreadEvent],
        records: inout [AppHarnessContextCompactionRecord]
    ) -> [HarnessThreadEvent] {
        let sorted = events.sorted {
            if $0.sequence == $1.sequence {
                return $0.createdAt < $1.createdAt
            }
            return $0.sequence < $1.sequence
        }
        let pinned = sorted.filter(\.isPinned).suffix(policy.maxPinnedEvents)
        let summaries = sorted.filter { $0.role == .summary }.suffix(2)
        let toolEvents = sorted.filter { $0.role == .tool }.suffix(policy.maxToolEvents)
        let recent = sorted.suffix(policy.maxEvents)
        let selectedIDs = Set((pinned + summaries + toolEvents + recent).map(\.id))
        let selected = sorted
            .filter { selectedIDs.contains($0.id) }
            .map { event in
                var event = event
                event.text = bounded(event.text, maxCharacters: policy.maxEventCharacters)
                return event
            }
        records.append(
            AppHarnessContextCompactionRecord(
                itemKind: .recentEvent,
                originalCount: events.count,
                includedCount: selected.count,
                droppedCount: max(0, events.count - selected.count),
                truncatedCount: selected.filter { selectedEvent in
                    events.first(where: { $0.id == selectedEvent.id })?.text.count ?? 0 > selectedEvent.text.count
                }.count,
                metadata: [
                    "strategy": "pinned+summary+tool+recent",
                    "maxEvents": String(policy.maxEvents),
                    "maxPinnedEvents": String(policy.maxPinnedEvents),
                    "maxToolEvents": String(policy.maxToolEvents)
                ]
            )
        )
        return selected
    }

    private func compactTasks(
        _ tasks: [HarnessTaskState],
        records: inout [AppHarnessContextCompactionRecord]
    ) -> [HarnessTaskState] {
        let selected = tasks.filter { task in
            guard policy.preserveWaitingState else { return true }
            return [.running, .paused, .waitingForUser, .waitingForPermission, .interrupted, .resuming].contains(task.status)
        }
        records.append(
            AppHarnessContextCompactionRecord(
                itemKind: .targetState,
                originalCount: tasks.count,
                includedCount: selected.count,
                droppedCount: max(0, tasks.count - selected.count),
                metadata: ["strategy": "preserveActiveAndWaitingTasks"]
            )
        )
        return selected
    }

    private func promptText(
        thread: HarnessThread,
        currentTurn: AppHarnessTurn?,
        events: [HarnessThreadEvent],
        assets: [HarnessThreadAsset],
        activeTasks: [HarnessTaskState]
    ) -> String {
        var lines: [String] = [
            "Thread: \(thread.title)",
            "Thread status: \(thread.status.rawValue)"
        ]
        if let currentTurn {
            lines.append("Current turn: \(currentTurn.text)")
        }
        if !activeTasks.isEmpty {
            lines.append("Active tasks:")
            for task in activeTasks {
                lines.append("- \(task.id) status=\(task.status.rawValue) goal=\(task.goal)")
                if let continuation = task.pendingContinuation {
                    lines.append("  pending=\(continuation.stage.rawValue) reason=\(continuation.reason)")
                    if let question = continuation.question {
                        lines.append("  question=\(question)")
                    }
                    if !continuation.missingPermissions.isEmpty {
                        lines.append("  missingPermissions=\(continuation.missingPermissions.map(\.rawValue).joined(separator: ","))")
                    }
                }
            }
        }
        if !events.isEmpty {
            lines.append("Thread events:")
            for event in events {
                lines.append("- [\(event.sequence)] \(event.role.rawValue): \(event.text)")
            }
        }
        if !assets.isEmpty {
            lines.append("Assets:")
            for asset in assets {
                lines.append("- \(asset.displayName) \(asset.contentType) \(asset.urlString)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func bounded(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        return String(value.prefix(maxCharacters))
    }
}

