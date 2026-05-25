import AppKit
import DonkeyAI
import DonkeyContracts
import DonkeyRuntime
import Foundation

@MainActor
final class DebugUIInspectionCoordinator {
    private let overlayController = DebugUIInspectionOverlayController()
    private let captureService = DebugUIScreenCaptureService()
    private let configURL: URL?
    private var analyzer: (any DebugUIInspectionAnalyzing)?
    private var trackers: [UInt32: DebugUIElementTracker] = [:]
    private var lastFingerprints: [UInt32: String] = [:]
    private var timer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    private var currentConfig: DebugUIOverlayConfiguration = .disabled
    private var isAnalyzing = false

    init(configURL: URL? = DebugUIOverlayConfiguration.defaultConfigURL()) {
        self.configURL = configURL
    }

    func start() {
        stop()
        installNotificationObservers()
        reloadConfigAndReschedule(force: true)
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll()
        overlayController.close()
        trackers.removeAll()
        lastFingerprints.removeAll()
        isAnalyzing = false
        currentConfig = .disabled
    }

    private func installNotificationObservers() {
        let appNotificationNames: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didChangeScreenParametersNotification
        ]
        notificationObservers = appNotificationNames.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh(force: true)
                }
            }
        }
        let workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(force: true)
            }
        }
        notificationObservers.append(workspaceObserver)
    }

    private func reloadConfigAndReschedule(force: Bool = false) {
        let newConfig = DebugUIOverlayConfiguration.load(fileURL: configURL)
        let cadenceChanged = newConfig.cadenceSeconds != currentConfig.cadenceSeconds
        let enablementChanged = newConfig.enabled != currentConfig.enabled
        let scopeChanged = newConfig.screenScope != currentConfig.screenScope
        let providerChanged = newConfig.provider != currentConfig.provider
        let confidenceChanged = newConfig.minConfidence != currentConfig.minConfidence
        currentConfig = newConfig

        if cadenceChanged || timer == nil || force {
            timer?.invalidate()
            let newTimer = Timer(timeInterval: newConfig.cadenceSeconds, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            timer = newTimer
            RunLoop.main.add(newTimer, forMode: .common)
        }

        if enablementChanged || scopeChanged || providerChanged || confidenceChanged {
            lastFingerprints.removeAll()
            trackers.removeAll()
            if !newConfig.enabled {
                overlayController.close()
            }
        }
    }

    private func refresh(force: Bool = false) {
        reloadConfigAndReschedule()
        guard currentConfig.enabled else { return }
        guard !isAnalyzing else { return }

        isAnalyzing = true
        Task { @MainActor in
            defer { isAnalyzing = false }
            do {
                try await analyzeVisibleScreens(force: force)
            } catch {
                overlayController.close()
                lastFingerprints.removeAll()
                trackers.removeAll()
            }
        }
    }

    private func analyzeVisibleScreens(force: Bool) async throws {
        let snapshots = try captureService.captureScreens(scope: currentConfig.screenScope)
        overlayController.closeScreens(except: Set(snapshots.map(\.screenID)))
        let analyzer = try analyzerInstance()

        for snapshot in snapshots {
            guard force || lastFingerprints[snapshot.screenID] != snapshot.fingerprint else {
                continue
            }
            lastFingerprints[snapshot.screenID] = snapshot.fingerprint

            let frame = try await analyzer.inspect(
                DebugUIInspectionRequest(
                    provider: currentConfig.provider,
                    screenshotBase64: snapshot.base64PNG,
                    pixelSize: snapshot.pixelSize,
                    minConfidence: currentConfig.minConfidence,
                    metadata: [
                        "screen.id": String(snapshot.screenID),
                        "screen.scope": currentConfig.screenScope.rawValue
                    ]
                )
            )
            var tracker = trackers[snapshot.screenID] ?? DebugUIElementTracker()
            let trackedFrame = tracker.update(with: frame)
            trackers[snapshot.screenID] = tracker
            overlayController.render(frame: trackedFrame, snapshot: snapshot)
        }
    }

    private func analyzerInstance() throws -> any DebugUIInspectionAnalyzing {
        if let analyzer {
            return analyzer
        }

        let configuration = try DonkeyBackendInferenceConfiguration.fromEnvironment()
        let created = HostedDebugUIInspectionAnalyzer(
            backend: DonkeyBackendInferenceClient(configuration: configuration)
        )
        analyzer = created
        return created
    }
}
