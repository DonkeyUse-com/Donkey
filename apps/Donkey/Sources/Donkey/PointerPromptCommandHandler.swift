import DonkeyAI
import DonkeyContracts
import DonkeyRuntime
import Foundation

struct PointerPromptCommandHandlingResult: Equatable, Sendable {
    var status: LocalAppTaskLiveRunStatus
    var summary: String
    var traceID: String
    var metadata: [String: String]
}

protocol PointerPromptCommandHandling: Sendable {
    func handleSubmittedCommand(_ command: String) async -> PointerPromptCommandHandlingResult
}

struct LocalAppPointerPromptCommandHandler: PointerPromptCommandHandling {
    var catalog: LocalAppTaskCatalog
    var localModelResolver: LocalModelTaskIntentResolver
    var liveRunner: LocalAppTaskLiveRunner
    var redactor: AIHarnessRedactor
    var memoryRetriever: SemanticRunMemoryRetriever

    init(
        catalog: LocalAppTaskCatalog = .defaultLocal(),
        localModelResolver: LocalModelTaskIntentResolver? = nil,
        liveRunner: LocalAppTaskLiveRunner? = nil,
        redactor: AIHarnessRedactor = AIHarnessRedactor(),
        memoryRetriever: SemanticRunMemoryRetriever = SemanticRunMemoryRetriever()
    ) {
        self.catalog = catalog
        self.localModelResolver = localModelResolver ?? LocalModelTaskIntentResolver(catalog: catalog)
        self.liveRunner = liveRunner ?? LocalAppTaskLiveRunner(catalog: catalog)
        self.redactor = redactor
        self.memoryRetriever = memoryRetriever
    }

    func handleSubmittedCommand(_ command: String) async -> PointerPromptCommandHandlingResult {
        let traceID = "pointer-prompt-\(UUID().uuidString)"
        let redaction = redactor.redact(command, surface: .modelContext)
        let semanticMemoryResults = await memoryRetriever.retrieve(
            query: RunMemorySemanticQuery(
                text: command,
                budget: RunMemoryRetrievalBudget(maxRecords: 3, maxPromptCharacters: 800)
            ),
            records: []
        )
        let memoryProposalDecisions = (try? ProviderDecodedMemoryProposalHandler.decisions(
            from: Data("[]".utf8),
            decidedAt: Self.now()
        )) ?? []
        let parseStartedAt = Self.uptimeMilliseconds()
        let localModelResult = await localModelResolver.resolve(
            command: command,
            sourceTraceID: traceID
        )
        let resolution = localModelResult.resolution
        let parseLatencyMS = Self.uptimeMilliseconds() - parseStartedAt
        let modelObservability = AIModelObservabilityReportBuilder.build(from: [localModelResult.trace])

        let result = await liveRunner.run(
            command: command,
            traceID: traceID,
            resolution: resolution,
            metadata: [
                "intentParser": "localModel",
                "latency.commandParseMS": Self.formatLatency(parseLatencyMS),
                "modelCallID": localModelResult.trace.id,
                "modelCallStatus": localModelResult.trace.status.rawValue,
                "modelValidationStatus": localModelResult.trace.validationStatus,
                "modelObservability.callCount": String(modelObservability.callCount),
                "modelObservability.acceptedCount": String(modelObservability.acceptedCount),
                "modelObservability.recoverySuccessCount": String(modelObservability.recoverySuccessCount),
                "redaction.modelContext.count": String(redaction.redactionCount),
                "semanticMemory.resultCount": String(semanticMemoryResults.count),
                "memoryProposal.decisionCount": String(memoryProposalDecisions.count)
            ]
        )

        return PointerPromptCommandHandlingResult(
            status: result.status,
            summary: summary(for: result),
            traceID: traceID,
            metadata: result.metadata
        )
    }

    private func summary(for result: LocalAppTaskLiveRunResult) -> String {
        switch result.status {
        case .completed:
            return "Done"
        case .needsUserReview:
            if let proposalCount = result.documentFormFillPlan?.proposals.count,
               proposalCount > 0 {
                return "Review \(proposalCount) fields"
            }
            return "Needs review"
        case .needsConfirmation:
            if let reason = result.resolution.metadata["reason"] {
                return "Need \(reason)"
            }
            return "Need more detail"
        case .appUnavailable:
            return "App unavailable"
        case .unsupportedCommand:
            return "Unsupported command"
        case .failedSafe:
            return "Stopped safely"
        }
    }

    private static func uptimeMilliseconds() -> Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }

    private static func formatLatency(_ milliseconds: Double) -> String {
        String(format: "%.3f", max(0, milliseconds))
    }

    private static func now() -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(),
            monotonicUptimeNanoseconds: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        )
    }
}
