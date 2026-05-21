import AppKit
import DonkeyContracts
import DonkeyRuntime
import DonkeyUI
import SwiftUI

@MainActor
final class PointerPromptSpawnOverlayController {
    private let store = PointerPromptSpawnOverlayStore()
    private var panel: PointerPromptSpawnPanel?
    private var hostingView: PointerPromptSpawnHostingView<PointerPromptSpawnOverlayContainerView>?
    private var viewModelsByID: [String: PointerPromptSpawnOverlayViewModel] = [:]
    private var closeWorkItem: DispatchWorkItem?
    private var windowResolver = MacWindowResolver()

    var followUpSubmitted: ((String, String, String) -> Void)? {
        didSet {
            for viewModel in viewModelsByID.values {
                viewModel.followUpSubmitted = followUpSubmitted
            }
        }
    }

    var selected: ((String) -> Void)? {
        didSet {
            for viewModel in viewModelsByID.values {
                viewModel.selected = selected
            }
        }
    }

    func update(
        spawnStates: [PointerPromptSpawnState],
        selectedSpawnID: String?,
        screen: NSScreen?,
        notchMetrics: PointerPromptNotchMetrics
    ) {
        guard !spawnStates.isEmpty else {
            fadeAndCloseAll()
            return
        }

        closeWorkItem?.cancel()
        closeWorkItem = nil

        guard let screen else { return }

        ensurePanel(on: screen)
        let visibleSpawnStates = spawnStates.filter { $0.phase != .notchCue }
        let visibleIDs = Set(visibleSpawnStates.map(\.id))

        for spawnState in visibleSpawnStates {
            updateViewModel(
                for: spawnState,
                selectedSpawnID: selectedSpawnID,
                screen: screen,
                notchMetrics: notchMetrics
            )
        }

        for staleID in viewModelsByID.keys where !visibleIDs.contains(staleID) {
            fadeAndRemove(id: staleID)
        }
    }

    func close() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
        for viewModel in viewModelsByID.values {
            viewModel.fadeOut()
        }
        panel?.close()
        panel = nil
        hostingView = nil
        store.viewModels = []
        viewModelsByID = [:]
    }

    private func ensurePanel(on screen: NSScreen) {
        if let panel {
            guard panel.frame.size != screen.frame.size || panel.frame.origin != screen.frame.origin else { return }

            panel.setFrame(screen.frame, display: true)
            hostingView?.frame = CGRect(origin: .zero, size: screen.frame.size)
            return
        }

        let hostingView = PointerPromptSpawnHostingView(rootView: PointerPromptSpawnOverlayContainerView(store: store))
        hostingView.frame = CGRect(origin: .zero, size: screen.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.hitTestRegionProvider = { [weak self] in
            guard let self else { return [] }

            return self.store.viewModels
                .map(\.hitTestFrame)
                .filter { !$0.isNull }
        }

        let panel = PointerPromptSpawnPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Donkey Spawn"
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView
    }

    private func updateViewModel(
        for spawnState: PointerPromptSpawnState,
        selectedSpawnID: String?,
        screen: NSScreen,
        notchMetrics: PointerPromptNotchMetrics
    ) {
        let viewModel = viewModel(for: spawnState)
        viewModel.setSelected(spawnState.id == selectedSpawnID)
        let destination = destinationPoint(
            for: spawnState.targetHint,
            viewModel: viewModel,
            screen: screen,
            notchMetrics: notchMetrics
        )

        if viewModel.state == nil {
            viewModel.show(
                state: spawnState,
                origin: spawnOrigin(in: screen, index: store.viewModels.firstIndex { $0.objectID == viewModel.objectID } ?? 0),
                destination: destination,
                screenSize: screen.frame.size
            )
            return
        }

        viewModel.update(
            state: spawnState,
            destination: destination,
            screenSize: screen.frame.size
        )
        if spawnState.phase == .fading {
            scheduleRemove(id: spawnState.id)
        }
    }

    private func viewModel(for spawnState: PointerPromptSpawnState) -> PointerPromptSpawnOverlayViewModel {
        if let viewModel = viewModelsByID[spawnState.id] {
            return viewModel
        }

        let viewModel = PointerPromptSpawnOverlayViewModel()
        viewModel.followUpSubmitted = followUpSubmitted
        viewModel.selected = selected
        viewModel.inputActivityChanged = { [weak self] isActive in
            self?.updateInputInteractivity(isActive: isActive)
        }
        viewModelsByID[spawnState.id] = viewModel
        store.viewModels.append(viewModel)
        return viewModel
    }

    private func updateInputInteractivity(isActive: Bool) {
        guard let panel else { return }

        if isActive {
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func beginVoiceInput(spawnID: String) -> Bool {
        guard let viewModel = viewModelsByID[spawnID] else { return false }

        viewModel.beginVoiceInput()
        return true
    }

    func completeVoiceInput(spawnID: String, text: String) {
        guard let viewModel = viewModelsByID[spawnID] else { return }

        viewModel.applyTranscribedInput(text, submit: !text.isEmpty)
    }

    func cancelVoiceInput(spawnID: String) {
        guard let viewModel = viewModelsByID[spawnID] else { return }

        viewModel.collapseInput()
    }

    func cueState(
        for spawnState: PointerPromptSpawnState?,
        screen: NSScreen?,
        notchMetrics: PointerPromptNotchMetrics
    ) -> PointerPromptSpawnState? {
        guard var spawnState,
              spawnState.phase == .notchCue,
              let screen else {
            return spawnState
        }

        let notchBottomY = max(
            notchMetrics.layout.collapsedVisibleHeight,
            notchMetrics.layout.voidHeight
        )
        let origin = CGPoint(x: screen.frame.width / 2, y: notchBottomY)
        let destination = destinationPoint(
            for: spawnState.targetHint,
            screen: screen,
            notchMetrics: notchMetrics
        )
        spawnState.notchCueAngleDegrees = PointerPromptSpawnGeometry.angleDegrees(
            from: origin,
            to: destination
        )
        return spawnState
    }

    private func fadeAndCloseAll() {
        guard panel != nil else { return }

        for viewModel in viewModelsByID.values {
            viewModel.fadeOut()
        }
        scheduleCloseAfterFade()
    }

    private func fadeAndRemove(id spawnID: String) {
        viewModelsByID[spawnID]?.fadeOut()
        scheduleRemove(id: spawnID)
    }

    private func scheduleRemove(id spawnID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self else { return }

            self.viewModelsByID[spawnID] = nil
            self.store.viewModels.removeAll { viewModel in
                viewModel.state?.id == spawnID || viewModel.state == nil
            }
            if self.store.viewModels.isEmpty {
                self.scheduleCloseAfterFade()
            }
        }
    }

    private func scheduleCloseAfterFade() {
        closeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.panel?.close()
                self?.panel = nil
                self?.hostingView = nil
                self?.store.viewModels = []
                self?.viewModelsByID = [:]
                self?.closeWorkItem = nil
            }
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: workItem)
    }

    private func spawnOrigin(in screen: NSScreen, index: Int) -> CGPoint {
        let stagger = CGFloat((index % 5) - 2) * 18
        return CGPoint(x: screen.frame.width / 2 + stagger, y: -24)
    }

    private func destinationPoint(
        for hint: PointerPromptSpawnTargetHint?,
        viewModel: PointerPromptSpawnOverlayViewModel,
        screen: NSScreen,
        notchMetrics: PointerPromptNotchMetrics
    ) -> CGPoint {
        guard !viewModel.freezesMovement else {
            return viewModel.destination
        }

        return destinationPoint(
            for: hint,
            screen: screen,
            notchMetrics: notchMetrics
        )
    }

    private func destinationPoint(
        for hint: PointerPromptSpawnTargetHint?,
        screen: NSScreen,
        notchMetrics: PointerPromptNotchMetrics
    ) -> CGPoint {
        let screenSize = screen.frame.size
        let fallback = PointerPromptSpawnGeometry.fallbackPoint(
            screenSize: screenSize,
            notchBottomY: max(
                notchMetrics.layout.collapsedVisibleHeight,
                notchMetrics.layout.voidHeight
            )
        )

        guard let hint else { return fallback }

        if let bounds = hint.bounds {
            return point(for: bounds, on: screen) ?? fallback
        }

        guard let target = resolvedWindowTarget(for: hint) else {
            return fallback
        }

        return point(for: target.bounds, on: screen) ?? fallback
    }

    private func resolvedWindowTarget(for hint: PointerPromptSpawnTargetHint) -> MacWindowTargetCandidate? {
        let candidates = windowResolver.enumerateCandidates()
            .filter {
                $0.isVisible &&
                    $0.isOnScreen &&
                    $0.safetyAssessment.status == .allowed &&
                    matches($0, hint: hint)
            }

        return candidates
            .sorted {
                if $0.isFocused != $1.isFocused {
                    return $0.isFocused && !$1.isFocused
                }
                if $0.isFrontmost != $1.isFrontmost {
                    return $0.isFrontmost && !$1.isFrontmost
                }
                return $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height
            }
            .first
    }

    private func matches(
        _ candidate: MacWindowTargetCandidate,
        hint: PointerPromptSpawnTargetHint
    ) -> Bool {
        if let bundleIdentifier = hint.bundleIdentifier,
           candidate.bundleIdentifier != bundleIdentifier {
            return false
        }

        if let titleContains = hint.titleContains,
           candidate.title?.localizedCaseInsensitiveContains(titleContains) != true {
            return false
        }

        if hint.bundleIdentifier == nil,
           hint.titleContains == nil,
           let appName = hint.appName,
           candidate.appName?.localizedCaseInsensitiveContains(appName) != true {
            return false
        }

        return true
    }

    private func point(
        for bounds: WindowTargetBounds,
        on screen: NSScreen
    ) -> CGPoint? {
        guard bounds.hasPositiveArea else { return nil }

        let localPoint = CGPoint(
            x: CGFloat(bounds.x) - screen.frame.minX + CGFloat(bounds.width) / 2,
            y: CGFloat(bounds.y) + CGFloat(bounds.height) / 2
        )
        return PointerPromptSpawnGeometry.clampedPoint(
            localPoint,
            in: screen.frame.size
        )
    }
}

private final class PointerPromptSpawnPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class PointerPromptSpawnHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRegionProvider: (() -> [CGRect])?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hitTestRegionProvider,
           !hitTestRegionProvider().contains(where: { $0.contains(point) }) {
            return nil
        }

        return super.hitTest(point)
    }
}
