import DonkeyContracts
import Foundation

public enum ManualTargetContextCaptureError: Error, Equatable, Sendable {
    case targetResolutionFailed(String)
    case unsafeTarget(windowID: UInt32, status: WindowTargetSafetyStatus)
    case policyDenied(capability: ToolCallCapability, reason: String)
    case screenshotFailed(String)
    case accessibilityFailed(String)
}

public enum ManualAccessibilityCaptureOutcome: Equatable, Sendable {
    case captured(MacAccessibilitySnapshotCaptureResult)
    case permissionDenied
    case skipped(reason: String)
}

public struct ManualTargetContextCaptureResult: Equatable, Sendable {
    public var session: RunSession
    public var traceSummary: RunTraceSummary
    public var target: MacWindowTargetCandidate
    public var screenshot: WindowScreenshotCaptureResult
    public var accessibility: ManualAccessibilityCaptureOutcome

    public init(
        session: RunSession,
        traceSummary: RunTraceSummary,
        target: MacWindowTargetCandidate,
        screenshot: WindowScreenshotCaptureResult,
        accessibility: ManualAccessibilityCaptureOutcome
    ) {
        self.session = session
        self.traceSummary = traceSummary
        self.target = target
        self.screenshot = screenshot
        self.accessibility = accessibility
    }
}

protocol WindowScreenshotCaptureServicing {
    func captureScreenshot(
        runID: String,
        selection: MacWindowSelectionRequest,
        artifactID: String
    ) async throws -> WindowScreenshotCaptureResult
}

extension WindowScreenshotCaptureService: WindowScreenshotCaptureServicing {}

protocol MacAccessibilitySnapshotCaptureServicing {
    func captureSnapshot(
        runID: String,
        selection: MacWindowSelectionRequest,
        limits: MacAccessibilitySnapshotLimits,
        artifactID: String,
        recordsPermissionDeniedEvent: Bool
    ) async throws -> MacAccessibilitySnapshotCaptureOutcome
}

extension MacAccessibilitySnapshotCaptureService: MacAccessibilitySnapshotCaptureServicing {}

public final class ManualTargetContextCaptureService {
    private let coordinator: RunCoordinator
    private let artifactStore: LocalRunArtifactStore
    private let windowResolver: MacWindowResolver
    private let screenshotService: any WindowScreenshotCaptureServicing
    private let accessibilityService: any MacAccessibilitySnapshotCaptureServicing

    public convenience init(
        coordinator: RunCoordinator = RunCoordinator(),
        artifactStore: LocalRunArtifactStore
    ) {
        let windowResolver = MacWindowResolver()
        self.init(
            coordinator: coordinator,
            artifactStore: artifactStore,
            windowResolver: windowResolver,
            screenshotService: WindowScreenshotCaptureService(artifactStore: artifactStore),
            accessibilityService: MacAccessibilitySnapshotCaptureService(artifactStore: artifactStore)
        )
    }

    init(
        coordinator: RunCoordinator,
        artifactStore: LocalRunArtifactStore,
        windowResolver: MacWindowResolver,
        screenshotService: any WindowScreenshotCaptureServicing,
        accessibilityService: any MacAccessibilitySnapshotCaptureServicing
    ) {
        self.coordinator = coordinator
        self.artifactStore = artifactStore
        self.windowResolver = windowResolver
        self.screenshotService = screenshotService
        self.accessibilityService = accessibilityService
    }

    public func capture(
        session: RunSession,
        selection: MacWindowSelectionRequest = MacWindowSelectionRequest(),
        traceID: String = UUID().uuidString,
        screenshotArtifactID: String = "screenshot-\(UUID().uuidString)",
        accessibilityArtifactID: String = "accessibility-\(UUID().uuidString)",
        accessibilityLimits: MacAccessibilitySnapshotLimits = .default
    ) async throws -> ManualTargetContextCaptureResult {
        var lastPersistedSequence = await coordinator.events().last?.sequence ?? 0
        let traceSummary = try await artifactStore.prepareRun(
            session: session,
            traceID: traceID
        )
        await coordinator.setTraceID(traceSummary.traceID)
        _ = await coordinator.start(session)
        try await persistNewCoordinatorEvents(
            runID: session.id,
            lastPersistedSequence: &lastPersistedSequence
        )

        let target: MacWindowTargetCandidate
        do {
            target = try windowResolver.selectTarget(selection)
        } catch {
            await recordTargetResolutionFailure(error, traceID: traceSummary.traceID)
            try await failRun(
                runID: session.id,
                reason: "Manual capture failed during target resolution",
                lastPersistedSequence: &lastPersistedSequence
            )
            throw ManualTargetContextCaptureError.targetResolutionFailed(String(describing: error))
        }

        let targetMetadata = metadata(for: target)
        guard target.safetyAssessment.status == .allowed else {
            await coordinator.recordToolEvent(
                capability: .capture,
                decision: .deny(reason: target.safetyAssessment.summary),
                toolName: "mac-window-resolver",
                summary: "Target window refused",
                traceID: traceSummary.traceID,
                metadata: targetMetadata
            )
            try await failRun(
                runID: session.id,
                reason: "Manual capture refused unsafe target",
                lastPersistedSequence: &lastPersistedSequence
            )
            throw ManualTargetContextCaptureError.unsafeTarget(
                windowID: target.windowID,
                status: target.safetyAssessment.status
            )
        }

        let captureDecision = session.permissionPolicy.decision(for: .capture)
        guard captureDecision.isAllowed else {
            await coordinator.recordToolEvent(
                capability: .capture,
                decision: captureDecision,
                toolName: "mac-window-resolver",
                summary: "Target resolution denied by policy",
                traceID: traceSummary.traceID,
                metadata: targetMetadata
            )
            try await failRun(
                runID: session.id,
                reason: "Manual capture denied by capture policy",
                lastPersistedSequence: &lastPersistedSequence
            )
            throw policyDeniedError(capability: .capture, decision: captureDecision)
        }

        await coordinator.recordToolEvent(
            capability: .capture,
            decision: .allow,
            toolName: "mac-window-resolver",
            summary: "Target window resolved",
            traceID: traceSummary.traceID,
            metadata: targetMetadata
        )
        try await persistNewCoordinatorEvents(
            runID: session.id,
            lastPersistedSequence: &lastPersistedSequence
        )

        let screenshot = try await captureScreenshot(
            runID: session.id,
            selection: MacWindowSelectionRequest(windowID: target.windowID),
            artifactID: screenshotArtifactID,
            targetMetadata: targetMetadata,
            traceID: traceSummary.traceID,
            policy: session.permissionPolicy,
            lastPersistedSequence: &lastPersistedSequence
        )

        let accessibility = try await captureAccessibility(
            runID: session.id,
            selection: MacWindowSelectionRequest(windowID: target.windowID),
            artifactID: accessibilityArtifactID,
            limits: accessibilityLimits,
            targetMetadata: targetMetadata,
            traceID: traceSummary.traceID,
            policy: session.permissionPolicy,
            lastPersistedSequence: &lastPersistedSequence
        )

        let completionReason: String
        switch accessibility {
        case .captured:
            completionReason = "Manual capture completed"
        case .permissionDenied, .skipped:
            completionReason = "Manual capture completed with partial Accessibility context"
        }
        await coordinator.complete(reason: completionReason)
        try await persistNewCoordinatorEvents(
            runID: session.id,
            lastPersistedSequence: &lastPersistedSequence
        )

        let currentSummary = try await artifactStore.summary(runID: session.id)
        return ManualTargetContextCaptureResult(
            session: session,
            traceSummary: currentSummary,
            target: target,
            screenshot: screenshot,
            accessibility: accessibility
        )
    }

    private func captureScreenshot(
        runID: String,
        selection: MacWindowSelectionRequest,
        artifactID: String,
        targetMetadata: [String: String],
        traceID: String,
        policy: ToolCallPolicy,
        lastPersistedSequence: inout Int
    ) async throws -> WindowScreenshotCaptureResult {
        await coordinator.recordToolEvent(
            capability: .capture,
            decision: .allow,
            toolName: "window-screenshot-capture",
            summary: "Screenshot capture started",
            traceID: traceID,
            metadata: targetMetadata
        )
        try await persistNewCoordinatorEvents(
            runID: runID,
            lastPersistedSequence: &lastPersistedSequence
        )

        let persistenceDecision = policy.decision(for: .persistence)
        guard persistenceDecision.isAllowed else {
            await coordinator.recordToolEvent(
                capability: .persistence,
                decision: persistenceDecision,
                toolName: "local-run-artifact-store",
                summary: "Screenshot artifact persistence denied by policy",
                traceID: traceID,
                metadata: targetMetadata
            )
            try await failRun(
                runID: runID,
                reason: "Manual capture denied by persistence policy",
                lastPersistedSequence: &lastPersistedSequence
            )
            throw policyDeniedError(capability: .persistence, decision: persistenceDecision)
        }

        do {
            let result = try await screenshotService.captureScreenshot(
                runID: runID,
                selection: selection,
                artifactID: artifactID
            )
            await coordinator.recordToolEvent(
                capability: .persistence,
                decision: .allow,
                toolName: "local-run-artifact-store",
                summary: "Screenshot artifact persisted",
                traceID: traceID,
                metadata: targetMetadata.merging(
                    artifactMetadata(result.artifact)
                ) { current, _ in current }
            )
            try await persistNewCoordinatorEvents(
                runID: runID,
                lastPersistedSequence: &lastPersistedSequence
            )
            return result
        } catch {
            await coordinator.recordToolEvent(
                capability: .capture,
                decision: .deny(reason: String(describing: error)),
                toolName: "window-screenshot-capture",
                summary: "Screenshot capture failed",
                traceID: traceID,
                metadata: targetMetadata
            )
            try await failRun(
                runID: runID,
                reason: "Manual capture failed during screenshot capture",
                lastPersistedSequence: &lastPersistedSequence
            )
            throw ManualTargetContextCaptureError.screenshotFailed(String(describing: error))
        }
    }

    private func captureAccessibility(
        runID: String,
        selection: MacWindowSelectionRequest,
        artifactID: String,
        limits: MacAccessibilitySnapshotLimits,
        targetMetadata: [String: String],
        traceID: String,
        policy: ToolCallPolicy,
        lastPersistedSequence: inout Int
    ) async throws -> ManualAccessibilityCaptureOutcome {
        let accessibilityDecision = policy.decision(for: .accessibility)
        guard accessibilityDecision.isAllowed else {
            await coordinator.recordToolEvent(
                capability: .accessibility,
                decision: accessibilityDecision,
                toolName: "mac-accessibility-snapshot",
                summary: "Accessibility snapshot denied by policy",
                traceID: traceID,
                metadata: targetMetadata
            )
            try await persistNewCoordinatorEvents(
                runID: runID,
                lastPersistedSequence: &lastPersistedSequence
            )
            return .skipped(reason: "Accessibility snapshot denied by policy")
        }

        let persistenceDecision = policy.decision(for: .persistence)
        guard persistenceDecision.isAllowed else {
            await coordinator.recordToolEvent(
                capability: .persistence,
                decision: persistenceDecision,
                toolName: "local-run-artifact-store",
                summary: "Accessibility artifact persistence denied by policy",
                traceID: traceID,
                metadata: targetMetadata
            )
            try await persistNewCoordinatorEvents(
                runID: runID,
                lastPersistedSequence: &lastPersistedSequence
            )
            return .skipped(reason: "Accessibility artifact persistence denied by policy")
        }

        do {
            let outcome = try await accessibilityService.captureSnapshot(
                runID: runID,
                selection: selection,
                limits: limits,
                artifactID: artifactID,
                recordsPermissionDeniedEvent: false
            )
            switch outcome {
            case .captured(let result):
                await coordinator.recordToolEvent(
                    capability: .accessibility,
                    decision: .allow,
                    toolName: "mac-accessibility-snapshot",
                    summary: "Accessibility snapshot captured",
                    traceID: traceID,
                    metadata: targetMetadata
                )
                await coordinator.recordToolEvent(
                    capability: .persistence,
                    decision: .allow,
                    toolName: "local-run-artifact-store",
                    summary: "Accessibility artifact persisted",
                    traceID: traceID,
                    metadata: targetMetadata.merging(
                        artifactMetadata(result.artifact)
                    ) { current, _ in current }
                )
                try await persistNewCoordinatorEvents(
                    runID: runID,
                    lastPersistedSequence: &lastPersistedSequence
                )
                return .captured(result)
            case .permissionDenied:
                try await recordAccessibilityPermissionDenied(
                    runID: runID,
                    traceID: traceID,
                    targetMetadata: targetMetadata,
                    lastPersistedSequence: &lastPersistedSequence
                )
                return .permissionDenied
            }
        } catch MacAccessibilitySnapshotCaptureError.accessibilityNotTrusted {
            try await recordAccessibilityPermissionDenied(
                runID: runID,
                traceID: traceID,
                targetMetadata: targetMetadata,
                lastPersistedSequence: &lastPersistedSequence
            )
            return .permissionDenied
        } catch {
            await coordinator.recordToolEvent(
                capability: .accessibility,
                decision: .deny(reason: String(describing: error)),
                toolName: "mac-accessibility-snapshot",
                summary: "Accessibility snapshot failed",
                traceID: traceID,
                metadata: targetMetadata
            )
            try await failRun(
                runID: runID,
                reason: "Manual capture failed during Accessibility snapshot",
                lastPersistedSequence: &lastPersistedSequence
            )
            throw ManualTargetContextCaptureError.accessibilityFailed(String(describing: error))
        }
    }

    private func recordAccessibilityPermissionDenied(
        runID: String,
        traceID: String,
        targetMetadata: [String: String],
        lastPersistedSequence: inout Int
    ) async throws {
        await coordinator.recordToolEvent(
            capability: .accessibility,
            decision: .deny(reason: "Accessibility permission is not granted"),
            toolName: "mac-accessibility-snapshot",
            summary: "Accessibility permission is not granted",
            traceID: traceID,
            metadata: targetMetadata.merging(
                ["accessibility.trustStatus": MacAccessibilityTrustStatus.notTrusted.rawValue]
            ) { current, _ in current }
        )
        try await persistNewCoordinatorEvents(
            runID: runID,
            lastPersistedSequence: &lastPersistedSequence
        )
    }

    private func recordTargetResolutionFailure(
        _ error: Error,
        traceID: String
    ) async {
        await coordinator.recordToolEvent(
            capability: .capture,
            decision: .deny(reason: String(describing: error)),
            toolName: "mac-window-resolver",
            summary: "Target window resolution failed",
            traceID: traceID,
            metadata: ["error": String(describing: error)]
        )
    }

    private func failRun(
        runID: String,
        reason: String,
        lastPersistedSequence: inout Int
    ) async throws {
        try await persistNewCoordinatorEvents(
            runID: runID,
            lastPersistedSequence: &lastPersistedSequence
        )
        await coordinator.fail(reason: reason)
        try await persistNewCoordinatorEvents(
            runID: runID,
            lastPersistedSequence: &lastPersistedSequence
        )
    }

    private func persistNewCoordinatorEvents(
        runID: String,
        lastPersistedSequence: inout Int
    ) async throws {
        let events = await coordinator.events()
            .filter { $0.sequence > lastPersistedSequence }
            .sorted { $0.sequence < $1.sequence }

        for event in events {
            _ = try await artifactStore.appendEvent(event, runID: runID)
            lastPersistedSequence = event.sequence
        }
    }

    private func policyDeniedError(
        capability: ToolCallCapability,
        decision: ToolCallDecision
    ) -> ManualTargetContextCaptureError {
        switch decision {
        case .allow:
            return .policyDenied(
                capability: capability,
                reason: "\(capability.rawValue) policy unexpectedly allowed"
            )
        case .deny(let reason), .ask(let reason):
            return .policyDenied(capability: capability, reason: reason)
        }
    }

    private func metadata(
        for target: MacWindowTargetCandidate
    ) -> [String: String] {
        var metadata = [
            "target.windowID": String(target.windowID),
            "target.processID": String(target.processID),
            "target.bounds.x": String(target.bounds.x),
            "target.bounds.y": String(target.bounds.y),
            "target.bounds.width": String(target.bounds.width),
            "target.bounds.height": String(target.bounds.height),
            "target.isVisible": String(target.isVisible),
            "target.isOnScreen": String(target.isOnScreen),
            "target.isFrontmost": String(target.isFrontmost),
            "target.isFocused": String(target.isFocused),
            "target.isIPhoneMirroring": String(target.isIPhoneMirroring),
            "target.safety.status": target.safetyAssessment.status.rawValue,
            "target.safety.reasons": target.safetyAssessment.reasons.map(\.rawValue).joined(separator: ",")
        ]

        if let appName = target.appName {
            metadata["target.appName"] = appName
        }

        if let bundleIdentifier = target.bundleIdentifier {
            metadata["target.bundleIdentifier"] = bundleIdentifier
        }

        if let title = target.title {
            metadata["target.title"] = title
        }

        return metadata
    }

    private func artifactMetadata(_ artifact: RunArtifactRecord) -> [String: String] {
        [
            "artifact.id": artifact.artifactID,
            "artifact.kind": artifact.kind.rawValue,
            "artifact.relativePath": artifact.relativePath,
            "artifact.contentType": artifact.contentType,
            "artifact.byteCount": String(artifact.byteCount)
        ]
    }
}
