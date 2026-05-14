import AppKit
import DonkeyContracts
import SwiftUI

@MainActor
final class PointerPromptOverlayController {
    static let contentSize = PointerPromptLayout.contentSize

    private let model: PointerPromptOverlayModel
    private let screenPadding: CGFloat = 8
    private let routeStepInterval: TimeInterval = 0.15
    private let followSmoothing: CGFloat = 0.34
    private let flipSmoothing: CGFloat = 0.22

    private var panel: NSPanel?
    private var timer: Timer?
    private var globalCommandClickMonitor: Any?
    private var localCommandClickMonitor: Any?
    private var currentFrame: CGRect?
    private var displayPlacement: PointerPromptPlacement = .bottomRight
    private var finalPlacement: PointerPromptPlacement = .bottomRight
    private var pendingPlacements: [PointerPromptPlacement] = []
    private var lastRouteStepAt = Date.distantPast

    init(model: PointerPromptOverlayModel) {
        self.model = model
    }

    func show() {
        let rootView = PointerPromptOverlayRootView(model: model)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: Self.contentSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = PointerPromptPanel(
            contentRect: CGRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Donkey"
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.dragRegionProvider = { [weak self] in
            self?.composerDragRegions() ?? []
        }
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]

        self.panel = panel
        startCommandClickMonitoring()
        positionAtCurrentMouseLocation()
        panel.orderFrontRegardless()
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopCommandClickMonitoring()
        panel?.close()
        panel = nil
    }

    private func startCommandClickMonitoring() {
        stopCommandClickMonitoring()

        globalCommandClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }

            Task { @MainActor in
                self?.activateAtCurrentMouseLocation()
            }
        }

        localCommandClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            if event.modifierFlags.contains(.command) {
                Task { @MainActor in
                    self?.activateAtCurrentMouseLocation()
                }
            }

            return event
        }
    }

    private func stopCommandClickMonitoring() {
        if let globalCommandClickMonitor {
            NSEvent.removeMonitor(globalCommandClickMonitor)
            self.globalCommandClickMonitor = nil
        }

        if let localCommandClickMonitor {
            NSEvent.removeMonitor(localCommandClickMonitor)
            self.localCommandClickMonitor = nil
        }
    }

    private func activateAtCurrentMouseLocation() {
        activate(at: NSEvent.mouseLocation)
    }

    private func positionAtCurrentMouseLocation() {
        currentFrame = nil
        displayPlacement = .bottomRight
        finalPlacement = .bottomRight
        pendingPlacements = []
        tick(mouseLocation: NSEvent.mouseLocation)
    }

    private func activate(at mouseLocation: CGPoint) {
        guard let panel else { return }

        model.activate()
        currentFrame = nil
        displayPlacement = .bottomRight
        finalPlacement = .bottomRight
        pendingPlacements = []
        tick(mouseLocation: mouseLocation)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick(mouseLocation explicitMouseLocation: CGPoint? = nil) {
        guard let panel else { return }

        updateMouseEventPassthrough(for: panel)
        if model.promptState.isActive, explicitMouseLocation == nil {
            currentFrame = panel.frame
            return
        }

        let mouseLocation = explicitMouseLocation ?? NSEvent.mouseLocation
        guard let screen = screen(containing: mouseLocation) else { return }

        let now = Date()
        let targetPlacement = preferredPlacement(
            for: mouseLocation,
            visibleFrame: screen.visibleFrame
        )
        if explicitMouseLocation == nil {
            updateRoute(to: targetPlacement, now: now)
            advanceRoute(now: now)
        } else {
            displayPlacement = targetPlacement
            finalPlacement = targetPlacement
            pendingPlacements = []
        }

        let targetFrame = clampedFrame(
            frame(for: displayPlacement, mouseLocation: mouseLocation),
            placement: displayPlacement,
            in: screen.visibleFrame
        )
        let nextFrame = smoothedFrame(
            toward: targetFrame,
            placement: displayPlacement,
            in: screen.visibleFrame
        )
        currentFrame = nextFrame
        panel.setFrame(nextFrame, display: true)
        updateMouseEventPassthrough(for: panel)

        if model.placement != displayPlacement {
            model.placement = displayPlacement
        }
    }

    private func updateRoute(to targetPlacement: PointerPromptPlacement, now: Date) {
        guard targetPlacement != finalPlacement else { return }

        finalPlacement = targetPlacement
        pendingPlacements = route(from: displayPlacement, to: targetPlacement)
        lastRouteStepAt = now.addingTimeInterval(-routeStepInterval)
    }

    private func advanceRoute(now: Date) {
        guard !pendingPlacements.isEmpty else { return }
        guard now.timeIntervalSince(lastRouteStepAt) >= routeStepInterval else { return }

        displayPlacement = pendingPlacements.removeFirst()
        lastRouteStepAt = now
    }

    private func route(
        from currentPlacement: PointerPromptPlacement,
        to targetPlacement: PointerPromptPlacement
    ) -> [PointerPromptPlacement] {
        guard currentPlacement != targetPlacement else { return [] }

        if currentPlacement.placesContentOnLeft != targetPlacement.placesContentOnLeft,
           currentPlacement.placesContentAbovePointer != targetPlacement.placesContentAbovePointer {
            let horizontalFirst = placement(
                left: targetPlacement.placesContentOnLeft,
                above: currentPlacement.placesContentAbovePointer
            )
            return [horizontalFirst, targetPlacement]
        }

        return [targetPlacement]
    }

    private func preferredPlacement(
        for mouseLocation: CGPoint,
        visibleFrame: CGRect
    ) -> PointerPromptPlacement {
        let preferredFrame = frame(for: .bottomRight, mouseLocation: mouseLocation)
        let preferredContentFrame = screenContentFrame(
            for: preferredFrame,
            placement: .bottomRight
        )
        let overflowsRight = preferredContentFrame.maxX > visibleFrame.maxX - screenPadding
        let overflowsBottom = preferredContentFrame.minY < visibleFrame.minY + screenPadding

        let preferredPlacement = placement(left: overflowsRight, above: overflowsBottom)
        let candidates = [
            preferredPlacement,
            PointerPromptPlacement.bottomRight,
            .bottomLeft,
            .topRight,
            .topLeft
        ]

        for candidate in candidates where fits(
            frame(for: candidate, mouseLocation: mouseLocation),
            placement: candidate,
            in: visibleFrame
        ) {
            return candidate
        }

        return preferredPlacement
    }

    private func placement(left: Bool, above: Bool) -> PointerPromptPlacement {
        switch (left, above) {
        case (false, false):
            .bottomRight
        case (true, false):
            .bottomLeft
        case (true, true):
            .topLeft
        case (false, true):
            .topRight
        }
    }

    private func frame(
        for placement: PointerPromptPlacement,
        mouseLocation: CGPoint
    ) -> CGRect {
        let size = Self.contentSize
        let anchor = agentPointerTipAnchor(for: placement)
        let agentPointerTipLocation = agentPointerTipLocation(
            for: placement,
            mouseLocation: mouseLocation
        )

        return CGRect(
            x: agentPointerTipLocation.x - anchor.x,
            y: agentPointerTipLocation.y - anchor.y,
            width: size.width,
            height: size.height
        )
    }

    private func agentPointerTipLocation(
        for placement: PointerPromptPlacement,
        mouseLocation: CGPoint
    ) -> CGPoint {
        let xDirection: CGFloat = placement.placesContentOnLeft ? -1 : 1
        let yDirection: CGFloat = placement.placesContentAbovePointer ? 1 : -1

        return CGPoint(
            x: mouseLocation.x + PointerPromptLayout.pointerDiagonalComponent * xDirection,
            y: mouseLocation.y + PointerPromptLayout.pointerDiagonalComponent * yDirection
        )
    }

    private func agentPointerTipAnchor(for placement: PointerPromptPlacement) -> CGPoint {
        let pointerSlotX: CGFloat
        if placement.placesContentOnLeft {
            pointerSlotX = stageHorizontalInset +
                PointerPromptLayout.stageHorizontalPadding +
                PointerPromptLayout.composerSize.width +
                PointerPromptLayout.pointerComposerSpacing
        } else {
            pointerSlotX = stageHorizontalInset + PointerPromptLayout.stageHorizontalPadding
        }
        let pointerVisualX = pointerSlotX + pointerVisualInsetX(for: placement)
        let pointerTipX = pointerVisualX +
            PointerPromptLayout.pointerVisualSize.width *
            PointerPromptLayout.pointerTipUnitPoint.x

        return CGPoint(
            x: pointerTipX,
            y: Self.contentSize.height - pointerTipYFromTop
        )
    }

    private func pointerVisualInsetX(for placement: PointerPromptPlacement) -> CGFloat {
        placement.placesContentOnLeft ? 0 :
            PointerPromptLayout.pointerSlotSize.width - PointerPromptLayout.pointerVisualSize.width
    }

    private func pointerVisualFrame(for placement: PointerPromptPlacement) -> CGRect {
        let pointerSlotX: CGFloat
        if placement.placesContentOnLeft {
            pointerSlotX = stageHorizontalInset +
                PointerPromptLayout.stageHorizontalPadding +
                PointerPromptLayout.composerSize.width +
                PointerPromptLayout.pointerComposerSpacing
        } else {
            pointerSlotX = stageHorizontalInset + PointerPromptLayout.stageHorizontalPadding
        }

        return CGRect(
            x: pointerSlotX + pointerVisualInsetX(for: placement),
            y: Self.contentSize.height - pointerVisualTopFromPanelTop - PointerPromptLayout.pointerVisualSize.height,
            width: PointerPromptLayout.pointerVisualSize.width,
            height: PointerPromptLayout.pointerVisualSize.height
        ).insetBy(
            dx: -PointerPromptLayout.pointerStrokeWidth,
            dy: -PointerPromptLayout.pointerStrokeWidth
        )
    }

    private var stageHorizontalInset: CGFloat {
        (Self.contentSize.width - stageContentWidth) / 2
    }

    private var stageVerticalInset: CGFloat {
        (Self.contentSize.height - stageContentHeight) / 2
    }

    private var stageContentWidth: CGFloat {
        PointerPromptLayout.stageHorizontalPadding * 2 +
            PointerPromptLayout.pointerSlotSize.width +
            PointerPromptLayout.pointerComposerSpacing +
            PointerPromptLayout.composerSize.width
    }

    private var stageContentHeight: CGFloat {
        PointerPromptLayout.stageVerticalPadding * 2 +
            PointerPromptLayout.composerSize.height
    }

    private var pointerCenterYFromTop: CGFloat {
        stageVerticalInset +
            PointerPromptLayout.stageVerticalPadding +
            PointerPromptLayout.composerSize.height / 2
    }

    private var pointerTipYFromTop: CGFloat {
        pointerCenterYFromTop -
            PointerPromptLayout.pointerVisualSize.height / 2 +
            PointerPromptLayout.pointerVisualSize.height *
            PointerPromptLayout.pointerTipUnitPoint.y
    }

    private var pointerVisualTopFromPanelTop: CGFloat {
        pointerCenterYFromTop - PointerPromptLayout.pointerVisualSize.height / 2
    }

    private func composerDragRegions() -> [CGRect] {
        guard model.promptState.isActive else { return [] }

        let composerFrame = composerFrame(for: displayPlacement)
        let dragThickness = PointerPromptLayout.composerDragBorderThickness
        let closeButtonClearance = PointerPromptLayout.closeButtonInset * 2 +
            PointerPromptLayout.closeButtonSize

        return [
            CGRect(
                x: composerFrame.minX + closeButtonClearance,
                y: composerFrame.maxY - dragThickness,
                width: composerFrame.width - closeButtonClearance,
                height: dragThickness
            ),
            CGRect(
                x: composerFrame.minX,
                y: composerFrame.minY,
                width: composerFrame.width,
                height: dragThickness
            ),
            CGRect(
                x: composerFrame.minX,
                y: composerFrame.minY + dragThickness,
                width: dragThickness,
                height: composerFrame.height - dragThickness - closeButtonClearance
            ),
            CGRect(
                x: composerFrame.maxX - dragThickness,
                y: composerFrame.minY + dragThickness,
                width: dragThickness,
                height: composerFrame.height - dragThickness * 2
            )
        ]
    }

    private func composerFrame(for placement: PointerPromptPlacement) -> CGRect {
        let x: CGFloat
        if placement.placesContentOnLeft {
            x = stageHorizontalInset + PointerPromptLayout.stageHorizontalPadding
        } else {
            x = stageHorizontalInset +
                PointerPromptLayout.stageHorizontalPadding +
                PointerPromptLayout.pointerSlotSize.width +
                PointerPromptLayout.pointerComposerSpacing
        }

        return CGRect(
            x: x,
            y: Self.contentSize.height - composerTopFromPanelTop - PointerPromptLayout.composerSize.height,
            width: PointerPromptLayout.composerSize.width,
            height: PointerPromptLayout.composerSize.height
        )
    }

    private var composerTopFromPanelTop: CGFloat {
        stageVerticalInset + PointerPromptLayout.stageVerticalPadding
    }

    private func visibleContentBounds(for placement: PointerPromptPlacement) -> CGRect {
        let pointerFrame = pointerVisualFrame(for: placement)
        guard model.promptState.isActive else {
            return pointerFrame
        }

        return pointerFrame.union(composerFrame(for: placement))
    }

    private func screenContentFrame(
        for panelFrame: CGRect,
        placement: PointerPromptPlacement
    ) -> CGRect {
        visibleContentBounds(for: placement).offsetBy(
            dx: panelFrame.minX,
            dy: panelFrame.minY
        )
    }

    private func updateMouseEventPassthrough(for panel: NSPanel) {
        guard model.promptState.isActive else {
            panel.ignoresMouseEvents = true
            return
        }

        let mouseLocationInPanel = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !composerFrame(for: displayPlacement).contains(mouseLocationInPanel)
    }

    private func fits(
        _ frame: CGRect,
        placement: PointerPromptPlacement,
        in visibleFrame: CGRect
    ) -> Bool {
        let contentFrame = screenContentFrame(for: frame, placement: placement)
        return contentFrame.minX >= visibleFrame.minX + screenPadding &&
            contentFrame.maxX <= visibleFrame.maxX - screenPadding &&
            contentFrame.minY >= visibleFrame.minY + screenPadding &&
            contentFrame.maxY <= visibleFrame.maxY - screenPadding
    }

    private func clampedFrame(
        _ frame: CGRect,
        placement: PointerPromptPlacement,
        in visibleFrame: CGRect
    ) -> CGRect {
        var origin = frame.origin
        let size = frame.size
        let contentBounds = visibleContentBounds(for: placement)

        let minX = visibleFrame.minX + screenPadding - contentBounds.minX
        let maxX = visibleFrame.maxX - screenPadding - contentBounds.maxX
        let minY = visibleFrame.minY + screenPadding - contentBounds.minY
        let maxY = visibleFrame.maxY - screenPadding - contentBounds.maxY

        if minX <= maxX {
            origin.x = min(max(origin.x, minX), maxX)
        } else {
            origin.x = visibleFrame.midX - contentBounds.midX
        }

        if minY <= maxY {
            origin.y = min(max(origin.y, minY), maxY)
        } else {
            origin.y = visibleFrame.midY - contentBounds.midY
        }

        return CGRect(origin: origin, size: size)
    }

    private func smoothedFrame(
        toward targetFrame: CGRect,
        placement: PointerPromptPlacement,
        in visibleFrame: CGRect
    ) -> CGRect {
        guard let currentFrame else { return targetFrame }

        let smoothing = pendingPlacements.isEmpty ? followSmoothing : flipSmoothing
        let origin = CGPoint(
            x: currentFrame.origin.x + (targetFrame.origin.x - currentFrame.origin.x) * smoothing,
            y: currentFrame.origin.y + (targetFrame.origin.y - currentFrame.origin.y) * smoothing
        )
        return clampedFrame(
            CGRect(origin: origin, size: targetFrame.size),
            placement: placement,
            in: visibleFrame
        )
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

private final class PointerPromptPanel: NSPanel {
    var dragRegionProvider: (() -> [CGRect])?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           dragRegionProvider?().contains(where: { $0.contains(event.locationInWindow) }) == true {
            performDrag(with: event)
            return
        }

        super.sendEvent(event)
    }
}
