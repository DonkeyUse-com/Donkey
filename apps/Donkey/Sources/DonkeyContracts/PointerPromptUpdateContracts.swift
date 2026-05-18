import Foundation

public enum PointerPromptUpdateStatus: String, Equatable, Sendable {
    case notChecked
    case checking
    case upToDate
    case available
    case unavailable
    case failed
}

public struct PointerPromptUpdateState: Equatable, Sendable {
    public var status: PointerPromptUpdateStatus
    public var currentVersion: String
    public var latestVersion: String?
    public var message: String?

    public init(
        status: PointerPromptUpdateStatus = .notChecked,
        currentVersion: String,
        latestVersion: String? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.message = message
    }

    public var isActionable: Bool {
        status == .available
    }

    public var headerButtonTitle: String? {
        guard isActionable else { return nil }

        if let latestVersion, !latestVersion.isEmpty {
            return "Update \(latestVersion)"
        }

        return "Update"
    }
}
