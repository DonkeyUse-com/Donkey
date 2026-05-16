import DonkeyContracts
import Foundation

public struct LocalNavigationMetadataFrameRequest: Equatable, Sendable {
    public var targetID: String
    public var traceID: String
    public var frameIDPrefix: String
    public var maxFrameCount: Int
    public var requestedBundleIdentifier: String?
    public var requestedTitleContains: String?
    public var browserTabs: [LocalNavigationBrowserTabMetadata]

    public init(
        targetID: String = "local-navigation",
        traceID: String,
        frameIDPrefix: String = "local-navigation-frame",
        maxFrameCount: Int = 1,
        requestedBundleIdentifier: String? = nil,
        requestedTitleContains: String? = nil,
        browserTabs: [LocalNavigationBrowserTabMetadata] = []
    ) {
        self.targetID = targetID
        self.traceID = traceID
        self.frameIDPrefix = frameIDPrefix
        self.maxFrameCount = max(0, maxFrameCount)
        self.requestedBundleIdentifier = requestedBundleIdentifier
        self.requestedTitleContains = requestedTitleContains
        self.browserTabs = browserTabs
    }
}

public struct LocalNavigationMetadataFrameSource: DryRunFrameSource {
    private let windowResolver: MacWindowResolver
    private let timestampProvider: any RunTraceTimestampProviding
    private let request: LocalNavigationMetadataFrameRequest

    public init(request: LocalNavigationMetadataFrameRequest) {
        self.init(
            windowResolver: MacWindowResolver(),
            timestampProvider: SystemLocalNavigationTimestampProvider(),
            request: request
        )
    }

    init(
        windowResolver: MacWindowResolver,
        timestampProvider: any RunTraceTimestampProviding = SystemLocalNavigationTimestampProvider(),
        request: LocalNavigationMetadataFrameRequest
    ) {
        self.windowResolver = windowResolver
        self.timestampProvider = timestampProvider
        self.request = request
    }

    public func frameBatches() async -> [[HotLoopFrame]] {
        let frameCount = max(0, request.maxFrameCount)
        guard frameCount > 0 else { return [] }

        return (0..<frameCount).map { index in
            [frame(index: index)]
        }
    }

    private func frame(index: Int) -> HotLoopFrame {
        let metadataStart = timestampProvider.now()
        let snapshot = windowResolver.enumerateCandidateList()
        let capturedAt = timestampProvider.now()
        var metadata = LocalNavigationFrameMetadataCodec.encode(
            snapshot: snapshot,
            browserTabs: request.browserTabs,
            requestedBundleIdentifier: request.requestedBundleIdentifier,
            requestedTitleContains: request.requestedTitleContains
        )
        metadata["latency.metadataReadMS"] = String(metadataStart.milliseconds(until: capturedAt) ?? 0)
        metadata["capture.latencyMS"] = "0"
        metadata["capture.encoded"] = "false"
        metadata["capture.artifactWritten"] = "false"
        metadata["localNavigation.frameSource"] = "metadata"

        let bounds = snapshot.candidates.first(where: \.candidate.isFocused)?.candidate.bounds
            ?? snapshot.candidates.first(where: \.candidate.isFrontmost)?.candidate.bounds
            ?? snapshot.candidates.first?.candidate.bounds
            ?? WindowTargetBounds(x: 0, y: 0, width: 1, height: 1)

        return HotLoopFrame(
            id: "\(request.frameIDPrefix)-\(index + 1)",
            traceID: request.traceID,
            targetID: request.targetID,
            capturedAt: capturedAt,
            sourceKind: .localNavigationMetadata,
            windowBounds: HotLoopRect(
                x: bounds.x,
                y: bounds.y,
                width: bounds.width,
                height: bounds.height,
                space: .screen
            ),
            pixelSize: HotLoopSize(
                width: max(1, bounds.width),
                height: max(1, bounds.height),
                space: .window
            ),
            metadata: metadata
        )
    }
}

public struct LocalNavigationDryRunPerceptionAdapter: DryRunPerceptionAdapting {
    public var adapterName: String
    public var observationDelayMS: Double

    public init(
        adapterName: String = "local-navigation-metadata-perception",
        observationDelayMS: Double = 1
    ) {
        self.adapterName = adapterName
        self.observationDelayMS = observationDelayMS
    }

    public func perceive(frame: HotLoopFrame) async -> [HotLoopPerceptionSignal] {
        let metadataReadMS = Double(frame.metadata["latency.metadataReadMS"] ?? "") ?? observationDelayMS
        let observedAt = frame.capturedAt.addingMilliseconds(max(metadataReadMS, observationDelayMS))
        let candidateCount = Int(frame.metadata["localNavigation.window.count"] ?? "") ?? 0
        let browserTabCount = Int(frame.metadata["localNavigation.browserTab.count"] ?? "") ?? 0

        return [
            HotLoopPerceptionSignal(
                id: "signal-\(frame.id)",
                traceID: frame.traceID,
                frameID: frame.id,
                kind: "localNavigationMetadata",
                capturedAt: frame.capturedAt,
                observedAt: observedAt,
                confidence: candidateCount + browserTabCount > 0 ? 1 : 0,
                plannerHintID: frame.plannerHintID,
                metadata: [
                    "adapter": adapterName,
                    "rawPixelsExposed": "false",
                    "latency.metadataReadMS": String(metadataReadMS),
                    "latency.preprocessMS": frame.metadata["latency.preprocessMS"] ?? "0",
                    "latency.modelInferenceMS": frame.metadata["latency.modelInferenceMS"] ?? "0",
                    "localNavigation.windowCandidateCount": String(candidateCount),
                    "localNavigation.browserTabCandidateCount": String(browserTabCount)
                ]
            )
        ]
    }
}

public struct LocalNavigationDryRunWorldStateProjector: DryRunWorldStateProjecting {
    public var projector: LocalNavigationMetadataProjector

    public init(projector: LocalNavigationMetadataProjector = LocalNavigationMetadataProjector()) {
        self.projector = projector
    }

    public func project(
        frame: HotLoopFrame,
        signals: [HotLoopPerceptionSignal],
        observedAt: RunTraceTimestamp
    ) async -> HotLoopWorldState {
        let navigationState = projector.project(
            snapshot: LocalNavigationFrameMetadataCodec.decodeWindowSnapshot(from: frame.metadata),
            traceID: frame.traceID,
            targetID: frame.targetID,
            observedAt: observedAt,
            sourceCapturedAt: frame.capturedAt,
            requestedBundleIdentifier: nonEmpty(frame.metadata["localNavigation.requestedBundleIdentifier"]),
            requestedTitleContains: nonEmpty(frame.metadata["localNavigation.requestedTitleContains"]),
            browserTabs: LocalNavigationFrameMetadataCodec.decodeBrowserTabs(from: frame.metadata)
        )
        var state = navigationState.hotLoopWorldState()
        state.metadata.merge([
            "projector": "local-navigation-dry-run-world-state-projector",
            "perceptionSignalIDs": signals.map(\.id).joined(separator: ",")
        ]) { current, _ in current }
        return state
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public struct LocalNavigationDryRunControllerPolicy: DryRunControllerPolicy {
    public var name: String { policy.name }
    public var policy: LocalNavigationControllerPolicy

    public init(policy: LocalNavigationControllerPolicy = LocalNavigationControllerPolicy()) {
        self.policy = policy
    }

    public func decide(state: HotLoopWorldState) async -> HotLoopControllerAction {
        policy.decide(state: localNavigationState(from: state))
    }

    private func localNavigationState(from state: HotLoopWorldState) -> LocalNavigationWorldState {
        let candidates = state.actionAffordances.map { affordance in
            LocalNavigationCandidate(
                id: value("localNavigation.candidateID", in: affordance) ?? affordance.id,
                kind: LocalNavigationCandidateKind(rawValue: value("localNavigation.candidateKind", in: affordance) ?? "")
                    ?? .window,
                appName: nonEmpty(value("localNavigation.appName", in: affordance)),
                bundleIdentifier: nonEmpty(value("localNavigation.bundleIdentifier", in: affordance)),
                title: nonEmpty(value("localNavigation.title", in: affordance)),
                bounds: affordance.targetBounds,
                isFrontmost: boolValue("localNavigation.isFrontmost", in: affordance),
                isFocused: boolValue("localNavigation.isFocused", in: affordance),
                safetyStatus: WindowTargetSafetyStatus(rawValue: value("localNavigation.safetyStatus", in: affordance) ?? "")
                    ?? .reviewRequired,
                confidence: affordance.confidence,
                sourceAgeMS: state.signalSummaries.first?.sourceAgeMS,
                metadata: affordance.metadata
            )
        }

        return LocalNavigationWorldState(
            id: state.id,
            traceID: state.traceID,
            frameID: state.frameID,
            targetID: state.targetID,
            observedAt: state.observedAt,
            candidates: candidates,
            focusedCandidateID: nonEmpty(state.metadata["localNavigation.focusedCandidateID"]),
            frontmostCandidateID: nonEmpty(state.metadata["localNavigation.frontmostCandidateID"]),
            requestedBundleIdentifier: nonEmpty(state.metadata["localNavigation.requestedBundleIdentifier"]),
            requestedTitleContains: nonEmpty(state.metadata["localNavigation.requestedTitleContains"]),
            confidence: state.confidence,
            metadata: state.metadata
        )
    }

    private func value(_ key: String, in affordance: HotLoopActionAffordance) -> String? {
        affordance.metadata[key]
    }

    private func boolValue(_ key: String, in affordance: HotLoopActionAffordance) -> Bool {
        value(key, in: affordance) == "true"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

enum LocalNavigationFrameMetadataCodec {
    static func encode(
        snapshot: MacWindowCandidateListSnapshot,
        browserTabs: [LocalNavigationBrowserTabMetadata],
        requestedBundleIdentifier: String?,
        requestedTitleContains: String?
    ) -> [String: String] {
        var metadata = [
            "localNavigation.metadataEncoded": "true",
            "localNavigation.rawPixelsExposed": "false",
            "localNavigation.window.count": String(snapshot.candidates.count),
            "localNavigation.browserTab.count": String(browserTabs.count),
            "localNavigation.requestedBundleIdentifier": requestedBundleIdentifier ?? "",
            "localNavigation.requestedTitleContains": requestedTitleContains ?? ""
        ]

        for (index, labeled) in snapshot.candidates.enumerated() {
            let prefix = "localNavigation.window.\(index)."
            let candidate = labeled.candidate
            metadata[prefix + "label"] = labeled.label
            metadata[prefix + "windowID"] = String(candidate.windowID)
            metadata[prefix + "processID"] = String(candidate.processID)
            metadata[prefix + "appName"] = candidate.appName ?? ""
            metadata[prefix + "bundleIdentifier"] = candidate.bundleIdentifier ?? ""
            metadata[prefix + "title"] = candidate.title ?? ""
            metadata[prefix + "bounds.x"] = String(candidate.bounds.x)
            metadata[prefix + "bounds.y"] = String(candidate.bounds.y)
            metadata[prefix + "bounds.width"] = String(candidate.bounds.width)
            metadata[prefix + "bounds.height"] = String(candidate.bounds.height)
            metadata[prefix + "isVisible"] = String(candidate.isVisible)
            metadata[prefix + "isOnScreen"] = String(candidate.isOnScreen)
            metadata[prefix + "isFrontmost"] = String(candidate.isFrontmost)
            metadata[prefix + "isFocused"] = String(candidate.isFocused)
            metadata[prefix + "isIPhoneMirroring"] = String(candidate.isIPhoneMirroring)
            metadata[prefix + "safetyStatus"] = candidate.safetyAssessment.status.rawValue
            metadata[prefix + "safetySummary"] = candidate.safetyAssessment.summary
            metadata[prefix + "safetyReasons"] = candidate.safetyAssessment.reasons.map(\.rawValue).joined(separator: ",")
        }

        for (index, tab) in browserTabs.enumerated() {
            let prefix = "localNavigation.browserTab.\(index)."
            metadata[prefix + "id"] = tab.id
            metadata[prefix + "appName"] = tab.appName ?? ""
            metadata[prefix + "bundleIdentifier"] = tab.bundleIdentifier ?? ""
            metadata[prefix + "title"] = tab.title ?? ""
            metadata[prefix + "url"] = tab.url ?? ""
            metadata[prefix + "windowID"] = tab.windowID.map(String.init) ?? ""
            metadata[prefix + "isActive"] = String(tab.isActive)
            metadata[prefix + "isFrontmost"] = String(tab.isFrontmost)
            metadata[prefix + "isFocused"] = String(tab.isFocused)
            metadata[prefix + "safetyStatus"] = tab.safetyStatus.rawValue
            metadata[prefix + "confidence"] = String(tab.confidence)
            if let bounds = tab.bounds {
                metadata[prefix + "bounds.x"] = String(bounds.origin.x)
                metadata[prefix + "bounds.y"] = String(bounds.origin.y)
                metadata[prefix + "bounds.width"] = String(bounds.size.width)
                metadata[prefix + "bounds.height"] = String(bounds.size.height)
                metadata[prefix + "bounds.space"] = bounds.space.rawValue
            }
        }

        return metadata
    }

    static func decodeWindowSnapshot(from metadata: [String: String]) -> MacWindowCandidateListSnapshot {
        let count = Int(metadata["localNavigation.window.count"] ?? "") ?? 0
        let candidates = (0..<count).compactMap { index -> LabeledMacWindowTargetCandidate? in
            let prefix = "localNavigation.window.\(index)."
            guard let windowID = UInt32(metadata[prefix + "windowID"] ?? ""),
                  let processID = Int32(metadata[prefix + "processID"] ?? ""),
                  let x = Double(metadata[prefix + "bounds.x"] ?? ""),
                  let y = Double(metadata[prefix + "bounds.y"] ?? ""),
                  let width = Double(metadata[prefix + "bounds.width"] ?? ""),
                  let height = Double(metadata[prefix + "bounds.height"] ?? "")
            else {
                return nil
            }

            return LabeledMacWindowTargetCandidate(
                label: metadata[prefix + "label"] ?? "window \(index + 1)",
                candidate: MacWindowTargetCandidate(
                    windowID: windowID,
                    processID: processID,
                    appName: nonEmpty(metadata[prefix + "appName"]),
                    bundleIdentifier: nonEmpty(metadata[prefix + "bundleIdentifier"]),
                    title: nonEmpty(metadata[prefix + "title"]),
                    bounds: WindowTargetBounds(x: x, y: y, width: width, height: height),
                    isVisible: bool(metadata[prefix + "isVisible"], defaultValue: true),
                    isOnScreen: bool(metadata[prefix + "isOnScreen"], defaultValue: true),
                    isFrontmost: bool(metadata[prefix + "isFrontmost"], defaultValue: false),
                    isFocused: bool(metadata[prefix + "isFocused"], defaultValue: false),
                    isIPhoneMirroring: bool(metadata[prefix + "isIPhoneMirroring"], defaultValue: false),
                    safetyAssessment: WindowTargetSafetyAssessment(
                        status: WindowTargetSafetyStatus(rawValue: metadata[prefix + "safetyStatus"] ?? "")
                            ?? .reviewRequired,
                        reasons: safetyReasons(metadata[prefix + "safetyReasons"]),
                        summary: metadata[prefix + "safetySummary"] ?? "Decoded from local-navigation frame metadata"
                    )
                )
            )
        }

        return MacWindowCandidateListSnapshot(labeledCandidates: candidates)
    }

    static func decodeBrowserTabs(from metadata: [String: String]) -> [LocalNavigationBrowserTabMetadata] {
        let count = Int(metadata["localNavigation.browserTab.count"] ?? "") ?? 0
        return (0..<count).compactMap { index in
            let prefix = "localNavigation.browserTab.\(index)."
            guard let id = nonEmpty(metadata[prefix + "id"]) else { return nil }

            return LocalNavigationBrowserTabMetadata(
                id: id,
                appName: nonEmpty(metadata[prefix + "appName"]),
                bundleIdentifier: nonEmpty(metadata[prefix + "bundleIdentifier"]),
                title: nonEmpty(metadata[prefix + "title"]),
                url: nonEmpty(metadata[prefix + "url"]),
                windowID: UInt32(metadata[prefix + "windowID"] ?? ""),
                bounds: bounds(prefix: prefix, metadata: metadata),
                isActive: bool(metadata[prefix + "isActive"], defaultValue: false),
                isFrontmost: bool(metadata[prefix + "isFrontmost"], defaultValue: false),
                isFocused: bool(metadata[prefix + "isFocused"], defaultValue: false),
                safetyStatus: WindowTargetSafetyStatus(rawValue: metadata[prefix + "safetyStatus"] ?? "")
                    ?? .reviewRequired,
                confidence: Double(metadata[prefix + "confidence"] ?? "") ?? 0.8
            )
        }
    }

    private static func bounds(
        prefix: String,
        metadata: [String: String]
    ) -> HotLoopRect? {
        guard let x = Double(metadata[prefix + "bounds.x"] ?? ""),
              let y = Double(metadata[prefix + "bounds.y"] ?? ""),
              let width = Double(metadata[prefix + "bounds.width"] ?? ""),
              let height = Double(metadata[prefix + "bounds.height"] ?? "")
        else {
            return nil
        }

        return HotLoopRect(
            x: x,
            y: y,
            width: width,
            height: height,
            space: HotLoopCoordinateSpace(rawValue: metadata[prefix + "bounds.space"] ?? "") ?? .screen
        )
    }

    private static func safetyReasons(_ value: String?) -> [WindowTargetSafetyReason] {
        value?
            .split(separator: ",")
            .compactMap { WindowTargetSafetyReason(rawValue: String($0)) }
            ?? []
    }

    private static func bool(_ value: String?, defaultValue: Bool) -> Bool {
        guard let value else { return defaultValue }
        return value == "true"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private struct SystemLocalNavigationTimestampProvider: RunTraceTimestampProviding {
    func now() -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: Date(),
            monotonicUptimeNanoseconds: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        )
    }
}

private extension RunTraceTimestamp {
    func addingMilliseconds(_ milliseconds: Double) -> RunTraceTimestamp {
        RunTraceTimestamp(
            wallClock: wallClock.addingTimeInterval(milliseconds / 1_000),
            monotonicUptimeNanoseconds: UInt64(
                max(
                    0,
                    Double(monotonicUptimeNanoseconds) + milliseconds * 1_000_000
                )
            )
        )
    }
}
