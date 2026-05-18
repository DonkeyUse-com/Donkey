import DonkeyContracts
import Foundation
import Sparkle

@MainActor
protocol DonkeyUpdateChecking: AnyObject {
    var currentVersion: String { get }
    var updateStateChanged: ((PointerPromptUpdateState) -> Void)? { get set }

    func start()
    func checkForUpdatesInBackground()
    func showUpdateUI()
}

@MainActor
final class SparkleUpdateController: NSObject, DonkeyUpdateChecking, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController?

    var updateStateChanged: ((PointerPromptUpdateState) -> Void)?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ??
            "0.1.0"
    }

    func start() {
        guard updaterController == nil else { return }
        guard isSparkleConfigured else {
            updateStateChanged?(
                PointerPromptUpdateState(
                    status: .unavailable,
                    currentVersion: currentVersion,
                    message: "Sparkle feed not configured"
                )
            )
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdatesInBackground() {
        guard let updaterController else {
            updateStateChanged?(
                PointerPromptUpdateState(
                    status: .unavailable,
                    currentVersion: currentVersion,
                    message: "Updater unavailable"
                )
            )
            return
        }

        updateStateChanged?(
            PointerPromptUpdateState(
                status: .checking,
                currentVersion: currentVersion
            )
        )
        updaterController.updater.checkForUpdatesInBackground()
    }

    func showUpdateUI() {
        guard let updaterController else {
            checkForUpdatesInBackground()
            return
        }

        updaterController.checkForUpdates(nil)
    }

    private var isSparkleConfigured: Bool {
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

        return feedURL?.isEmpty == false && publicKey?.isEmpty == false
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateStateChanged?(
            PointerPromptUpdateState(
                status: .available,
                currentVersion: currentVersion,
                latestVersion: item.displayVersionString
            )
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        updateStateChanged?(
            PointerPromptUpdateState(
                status: .upToDate,
                currentVersion: currentVersion,
                message: error.localizedDescription
            )
        )
    }
}
