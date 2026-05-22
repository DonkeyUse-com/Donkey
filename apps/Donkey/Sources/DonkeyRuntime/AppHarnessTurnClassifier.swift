import DonkeyContracts

public enum AppHarnessTurnClassificationKind: String, Equatable, Sendable {
    case unknown
}

public struct AppHarnessTurnClassification: Equatable, Sendable {
    public var kind: AppHarnessTurnClassificationKind
    public var router: String
    public var missingDetail: String?
    public var metadata: [String: String]

    public init(
        kind: AppHarnessTurnClassificationKind,
        router: String,
        missingDetail: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.kind = kind
        self.router = router
        self.missingDetail = missingDetail
        self.metadata = metadata
    }
}

public struct AppHarnessTurnClassifier: Sendable {
    public init() {}

    public func classify(
        text _: String,
        request _: AppHarnessTurnRequest,
        catalog _: LocalAppTaskCatalog
    ) -> AppHarnessTurnClassification {
        let classifierMetadata = [
            "classifier": "model-intent-required-v1"
        ]
        return AppHarnessTurnClassification(
            kind: .unknown,
            router: "modelIntentRequired",
            missingDetail: "actionable request",
            metadata: classifierMetadata
        )
    }
}
