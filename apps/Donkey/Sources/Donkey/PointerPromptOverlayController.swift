import AppKit
import Carbon.HIToolbox
import DonkeyContracts
import DonkeyUI
import SwiftUI

@MainActor
final class PointerPromptOverlayController {
    private static let commandKHotKeySignature: OSType = 0x444B4559
    private static let commandKHotKeyID: UInt32 = 1

    private let model: PointerPromptOverlayModel
    private let fixedPlacement: PointerPromptPlacement = .bottomRight
    private let activationShortcut: PointerPromptActivationShortcut
    private let microphoneWaveformMeter = MicrophoneWaveformMeter()

    private var statusPanel: NSPanel?
    private var statusHostingView: NSHostingView<PointerPromptNotchStatusView>?
    private var inputPanel: NSPanel?
    private var timer: Timer?
    private var globalActivationMonitor: Any?
    private var localActivationMonitor: Any?
    private var commandKHotKeyRef: EventHotKeyRef?
    private var commandKEventHandlerRef: EventHandlerRef?
    private var activationTapStartedAt: Date?
    private var activationTapIsClean = false
    private var completedActivationTapCount = 0
    private var lastActivationTapCompletedAt: Date?
    private var activationHoldStartedAt: Date?
    private var isVoiceInputActive = false
    private var isStatusExpanded = false

    init(
        model: PointerPromptOverlayModel,
        activationShortcut: PointerPromptActivationShortcut = .doubleCommand
    ) {
        self.model = model
        self.activationShortcut = activationShortcut
        microphoneWaveformMeter.onLevelsChanged = { [weak model] levels in
            model?.updateVoiceWaveformLevels(levels)
        }
    }

    func show() {
        let initialInputSize = currentContentSize
        let inputHostingView = makeInputHostingView(size: initialInputSize)
        let inputPanel = makeInputPanel(size: initialInputSize, hostingView: inputHostingView)
        let statusPanel = makeStatusPanel()

        self.inputPanel = inputPanel
        self.statusPanel = statusPanel
        startActivationMonitoring()
        startCommandKHotKeyMonitoring()
        positionStatusPanel()
        centerInputPanel()
        inputPanel.orderOut(nil)
        statusPanel.orderFrontRegardless()
        startTimer()
    }

    private func makeInputHostingView(size: CGSize) -> NSHostingView<PointerPromptOverlayRootView> {
        let hostingView = NSHostingView(rootView: PointerPromptOverlayRootView(model: model))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        return hostingView
    }

    private func makeInputPanel(
        size: CGSize,
        hostingView: NSHostingView<PointerPromptOverlayRootView>
    ) -> PointerPromptPanel {
        let panel = PointerPromptPanel(
            contentRect: CGRect(origin: .zero, size: size),
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
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.dragRegionProvider = { [weak self] in
            self?.composerDragRegions() ?? []
        }
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]

        return panel
    }

    private func makeStatusPanel() -> NSPanel {
        let metrics = notchMetrics()
        let hostingView = NSHostingView(rootView: notchStatusView(metrics: metrics))
        hostingView.frame = CGRect(origin: .zero, size: metrics.surfaceSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        statusHostingView = hostingView

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: metrics.surfaceSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.title = "Donkey Status"
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]

        return panel
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopActivationMonitoring()
        stopCommandKHotKeyMonitoring()
        microphoneWaveformMeter.stop()
        inputPanel?.close()
        inputPanel = nil
        statusPanel?.close()
        statusPanel = nil
        statusHostingView = nil
    }

    private func startActivationMonitoring() {
        stopActivationMonitoring()

        let activationEventMask: NSEvent.EventTypeMask = [
            .flagsChanged,
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        globalActivationMonitor = NSEvent.addGlobalMonitorForEvents(matching: activationEventMask) { [weak self] event in
            Task { @MainActor in
                self?.handleActivationEvent(event)
            }
        }

        localActivationMonitor = NSEvent.addLocalMonitorForEvents(matching: activationEventMask) { [weak self] event in
            Task { @MainActor in
                self?.handleActivationEvent(event)
            }
            return event
        }
    }

    private func stopActivationMonitoring() {
        if let globalActivationMonitor {
            NSEvent.removeMonitor(globalActivationMonitor)
            self.globalActivationMonitor = nil
        }

        if let localActivationMonitor {
            NSEvent.removeMonitor(localActivationMonitor)
            self.localActivationMonitor = nil
        }
    }

    private func startCommandKHotKeyMonitoring() {
        stopCommandKHotKeyMonitoring()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event,
                      let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == PointerPromptOverlayController.commandKHotKeySignature,
                      hotKeyID.id == PointerPromptOverlayController.commandKHotKeyID else {
                    return noErr
                }

                let controller = Unmanaged<PointerPromptOverlayController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    controller.handleCommandKHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &commandKEventHandlerRef
        )

        let hotKeyID = EventHotKeyID(
            signature: Self.commandKHotKeySignature,
            id: Self.commandKHotKeyID
        )
        RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &commandKHotKeyRef
        )
    }

    private func stopCommandKHotKeyMonitoring() {
        if let commandKHotKeyRef {
            UnregisterEventHotKey(commandKHotKeyRef)
            self.commandKHotKeyRef = nil
        }

        if let commandKEventHandlerRef {
            RemoveEventHandler(commandKEventHandlerRef)
            self.commandKEventHandlerRef = nil
        }
    }

    private func handleCommandKHotKey() {
        resetActivationTapSequence()
        activateInputAtScreenCenter()
    }

    private func handleActivationEvent(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            handleModifierFlagsChanged(event.modifierFlags)
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if event.type == .keyDown, activateFromCommandKIfNeeded(event) {
                resetActivationTapSequence()
                return
            }

            if event.type != .keyDown, dismissActivePromptIfClickIsOutside() {
                resetActivationTapSequence()
                return
            }

            resetActivationTapSequence()
        default:
            break
        }
    }

    private func activateFromCommandKIfNeeded(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        guard flags == .command,
              event.charactersIgnoringModifiers?.lowercased() == "k" else {
            return false
        }

        activateInputAtScreenCenter()
        return true
    }

    private func handleModifierFlagsChanged(_ modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        let activationModifierFlag = activationShortcut.modifier.eventModifierFlag
        let isActivationModifierDown = flags.contains(activationModifierFlag)
        let isCleanActivationModifierOnly = flags == activationModifierFlag

        if isVoiceInputActive, !isActivationModifierDown {
            finishVoiceInput()
            resetActivationTapSequence()
            return
        }

        if isCleanActivationModifierOnly {
            if activationTapStartedAt == nil {
                let now = Date()
                activationTapStartedAt = now
                activationTapIsClean = true
                if shouldStartVoiceHoldCandidate(at: now) {
                    activationHoldStartedAt = now
                }
            }
            return
        }

        if isActivationModifierDown {
            if activationTapStartedAt == nil {
                activationTapStartedAt = Date()
            }
            activationTapIsClean = false
            completedActivationTapCount = 0
            lastActivationTapCompletedAt = nil
            activationHoldStartedAt = nil
            return
        }

        guard flags.isEmpty else {
            resetActivationTapSequence()
            return
        }

        guard let activationTapStartedAt else { return }

        let now = Date()
        let tapDuration = now.timeIntervalSince(activationTapStartedAt)
        let completedCleanTap = activationTapIsClean &&
            tapDuration <= activationShortcut.maximumTapDuration
        self.activationTapStartedAt = nil
        activationTapIsClean = false

        guard completedCleanTap else {
            resetActivationTapSequence()
            return
        }

        registerCompletedActivationTap(at: now)
    }

    private func registerCompletedActivationTap(at now: Date) {
        if let lastActivationTapCompletedAt,
           now.timeIntervalSince(lastActivationTapCompletedAt) <= activationShortcut.maximumTapInterval {
            completedActivationTapCount += 1
        } else {
            completedActivationTapCount = 1
        }

        lastActivationTapCompletedAt = now
        activationHoldStartedAt = nil

        guard completedActivationTapCount >= activationShortcut.tapCount else {
            return
        }

        resetActivationTapSequence()
        activateInputAtScreenCenter()
    }

    private func resetActivationTapSequence() {
        activationTapStartedAt = nil
        activationTapIsClean = false
        completedActivationTapCount = 0
        lastActivationTapCompletedAt = nil
        activationHoldStartedAt = nil
    }

    private func shouldStartVoiceHoldCandidate(at now: Date) -> Bool {
        guard activationShortcut.holdToVoiceInputDuration != nil,
              completedActivationTapCount == activationShortcut.tapCount - 1,
              let lastActivationTapCompletedAt else {
            return false
        }

        return now.timeIntervalSince(lastActivationTapCompletedAt) <=
            activationShortcut.maximumTapInterval
    }

    private func activateVoiceInputIfNeeded() {
        guard let holdToVoiceInputDuration = activationShortcut.holdToVoiceInputDuration,
              let activationHoldStartedAt,
              activationTapIsClean,
              Date().timeIntervalSince(activationHoldStartedAt) >= holdToVoiceInputDuration else {
            return
        }

        resetActivationTapSequence()
        activateVoiceInputAtScreenCenter()
    }

    private func activateInputAtScreenCenter() {
        guard !model.promptState.isActive else {
            if let inputPanel {
                centerInputPanel()
                activateForKeyboardInput(inputPanel)
            }
            focusComposerTextInput()
            microphoneWaveformMeter.start()
            return
        }

        activateInput()
    }

    private func activateVoiceInputAtScreenCenter() {
        activateInputAtScreenCenter()
        isVoiceInputActive = true
        microphoneWaveformMeter.startAudioCapture()
        model.handle(.voiceInputRequested)
    }

    private func finishVoiceInput() {
        guard isVoiceInputActive else { return }

        isVoiceInputActive = false
        let audio = microphoneWaveformMeter.finishAudioCapture()
        model.submitVoiceAudio(audio)
    }

    private func activateInput() {
        guard let inputPanel else { return }

        model.activate()
        microphoneWaveformMeter.start()
        centerInputPanel()

        activateForKeyboardInput(inputPanel)
        focusComposerTextInput()
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

    private func tick() {
        guard let inputPanel else { return }

        if !model.promptState.isActive {
            microphoneWaveformMeter.stop()
            inputPanel.orderOut(nil)
        }

        activateVoiceInputIfNeeded()
        positionStatusPanel()
        updateStatusPanelView()
        resizeActivePanelIfNeeded(inputPanel)
        updateMouseEventPassthrough(for: inputPanel)

        if model.placement != fixedPlacement {
            model.placement = fixedPlacement
        }
    }

    private func centerInputPanel() {
        guard let inputPanel,
              let screen = activeScreen() else {
            return
        }

        let size = currentContentSize
        inputPanel.setFrame(
            CGRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private func positionStatusPanel() {
        guard let statusPanel,
              let screen = activeScreen() else {
            return
        }

        let metrics = notchMetrics(for: screen)
        if statusPanel.frame.size != metrics.surfaceSize {
            statusHostingView?.frame = CGRect(origin: .zero, size: metrics.surfaceSize)
        }

        statusPanel.setFrame(
            CGRect(
                x: screen.frame.midX - metrics.surfaceSize.width / 2,
                y: screen.frame.maxY - metrics.surfaceSize.height,
                width: metrics.surfaceSize.width,
                height: metrics.surfaceSize.height
            ),
            display: true
        )
    }

    private func updateStatusPanelView() {
        let metrics = notchMetrics()
        statusHostingView?.rootView = notchStatusView(metrics: metrics)
    }

    private func notchStatusView(metrics: NotchMetrics) -> PointerPromptNotchStatusView {
        PointerPromptNotchStatusView(
            state: model.promptState,
            updateState: model.updateState,
            layout: metrics.layout,
            surfaceWidth: metrics.surfaceSize.width,
            surfaceHeight: metrics.surfaceSize.height,
            isExpanded: isStatusExpanded,
            hoverChanged: { [weak self] isHovering in
                self?.setStatusExpanded(isHovering)
            },
            commandRequested: { [weak self] in
                self?.handleCommandKHotKey()
            },
            updateRequested: { [weak self] in
                self?.openAvailableUpdate()
            }
        )
    }

    private func openAvailableUpdate() {
        model.showUpdateUI()
    }

    private func setStatusExpanded(_ isExpanded: Bool) {
        guard isStatusExpanded != isExpanded else { return }

        isStatusExpanded = isExpanded
        positionStatusPanel()
        updateStatusPanelView()
    }

    private func activeScreen() -> NSScreen? {
        inputPanel?.screen ?? statusPanel?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func notchMetrics(for screen: NSScreen? = nil) -> NotchMetrics {
        let screen = screen ?? activeScreen()
        guard let screen else {
            return NotchMetrics(
                voidWidth: NotchMetrics.fallbackVoidWidth,
                voidHeight: NotchMetrics.fallbackVoidHeight,
                isExpanded: isStatusExpanded,
                screenWidth: NotchMetrics.defaultScreenWidth
            )
        }

        let safeTop = max(0, screen.safeAreaInsets.top)
        let measuredVoidWidth: CGFloat
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            measuredVoidWidth = max(
                0,
                screen.frame.width - leftArea.width - rightArea.width
            )
        } else {
            measuredVoidWidth = 0
        }
        let hasNotch = safeTop > 0 || measuredVoidWidth > 0
        let voidHeight = hasNotch ? max(safeTop, NotchMetrics.fallbackVoidHeight) : 0
        let voidWidth = hasNotch ? max(measuredVoidWidth, inferredVoidWidth(for: screen, safeTop: safeTop)) : 0

        return NotchMetrics(
            voidWidth: voidWidth,
            voidHeight: voidHeight,
            isExpanded: isStatusExpanded,
            screenWidth: screen.frame.width
        )
    }

    private func inferredVoidWidth(for screen: NSScreen, safeTop: CGFloat) -> CGFloat {
        guard safeTop > 0 else { return 0 }

        return min(
            max(NotchMetrics.fallbackVoidWidth, screen.frame.width * 0.095),
            NotchMetrics.maximumInferredVoidWidth
        )
    }

    private var stageHorizontalInset: CGFloat {
        (currentContentSize.width - stageContentWidth) / 2
    }

    private var stageVerticalInset: CGFloat {
        (currentContentSize.height - stageContentHeight) / 2
    }

    private var stageContentWidth: CGFloat {
        PointerPromptLayout.stageHorizontalPadding * 2 +
            PointerPromptLayout.composerWidth
    }

    private var stageContentHeight: CGFloat {
        PointerPromptLayout.stageVerticalPadding * 2 +
            currentComposerHeight
    }

    private func composerDragRegions() -> [CGRect] {
        guard model.promptState.isActive else { return [] }

        let composerFrame = composerFrame(for: fixedPlacement)
        let inputSurfaceFrame = composerInputSurfaceFrame(in: composerFrame)
        let closeButtonFrame = composerCloseButtonFrame(in: composerFrame).insetBy(dx: -3, dy: -3)
        var regions = [
            inputSurfaceFrame,
            CGRect(
                x: composerFrame.minX,
                y: inputSurfaceFrame.maxY,
                width: max(0, closeButtonFrame.minX - composerFrame.minX),
                height: max(0, composerFrame.maxY - inputSurfaceFrame.maxY)
            )
        ]

        regions.removeAll { $0.width <= 0 || $0.height <= 0 }
        return regions
    }

    private func composerFrame(for placement: PointerPromptPlacement) -> CGRect {
        let x = stageHorizontalInset + PointerPromptLayout.stageHorizontalPadding

        return CGRect(
            x: x,
            y: currentContentSize.height -
                composerTopFromPanelTop -
                PointerPromptLayout.externalCloseButtonOutsideMargin -
                currentComposerHeight,
            width: PointerPromptLayout.composerWidth,
            height: currentComposerHeight + PointerPromptLayout.externalCloseButtonOutsideMargin
        )
    }

    private var composerTopFromPanelTop: CGFloat {
        stageVerticalInset + PointerPromptLayout.stageVerticalPadding
    }

    private func composerInputSurfaceFrame(in composerFrame: CGRect) -> CGRect {
        return CGRect(
            x: composerFrame.minX,
            y: composerFrame.minY,
            width: PointerPromptLayout.composerInputSurfaceWidth,
            height: PointerPromptLayout.composerInputHeight(
                inputTextHeight: model.inputTextHeight,
                isExpanded: model.isInputExpanded
            )
        )
    }

    private func composerCloseButtonFrame(in composerFrame: CGRect) -> CGRect {
        CGRect(
            x: composerFrame.maxX - PointerPromptLayout.externalCloseButtonSize,
            y: composerFrame.maxY - PointerPromptLayout.externalCloseButtonSize,
            width: PointerPromptLayout.externalCloseButtonSize,
            height: PointerPromptLayout.externalCloseButtonSize
        )
    }

    private func composerTextInputFrame(in inputSurfaceFrame: CGRect) -> CGRect {
        if model.isInputExpanded {
            return CGRect(
                x: inputSurfaceFrame.minX +
                    PointerPromptLayout.composerExpandedTextHorizontalPadding,
                y: inputSurfaceFrame.maxY -
                    PointerPromptLayout.composerExpandedTextTopPadding -
                    model.inputTextHeight,
                width: PointerPromptLayout.composerExpandedTextWidth,
                height: model.inputTextHeight
            )
        }

        let x = inputSurfaceFrame.minX + PointerPromptLayout.composerInputLeadingContentPadding
        let width = PointerPromptLayout.composerWrappingTextWidth
        let height = model.inputTextHeight

        return CGRect(
            x: x,
            y: inputSurfaceFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func updateMouseEventPassthrough(for panel: NSPanel) {
        guard model.promptState.isActive else {
            panel.ignoresMouseEvents = true
            isVoiceInputActive = false
            return
        }

        if isComposerTextInputFocused(in: panel) {
            panel.ignoresMouseEvents = false
            return
        }

        let mouseLocationInPanel = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !composerFrame(for: fixedPlacement).contains(mouseLocationInPanel)
    }

    private func dismissActivePromptIfClickIsOutside() -> Bool {
        guard model.promptState.isActive,
              let inputPanel else {
            return false
        }

        let mouseLocationInPanel = inputPanel.convertPoint(fromScreen: NSEvent.mouseLocation)
        guard !composerFrame(for: fixedPlacement).contains(mouseLocationInPanel) else {
            return false
        }

        model.handle(.dismissed)
        isVoiceInputActive = false
        microphoneWaveformMeter.stop()
        return true
    }

    private var currentContentSize: CGSize {
        PointerPromptLayout.contentSize(
            inputTextHeight: model.inputTextHeight,
            isExpanded: model.isInputExpanded
        )
    }

    private var currentComposerHeight: CGFloat {
        PointerPromptLayout.composerHeight(
            inputTextHeight: model.inputTextHeight,
            isExpanded: model.isInputExpanded
        )
    }

    private func resizeActivePanelIfNeeded(_ panel: NSPanel) {
        let size = currentContentSize
        let frame = panel.frame
        guard abs(frame.width - size.width) > 0.5 ||
            abs(frame.height - size.height) > 0.5 else {
            return
        }

        panel.setFrame(
            CGRect(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private func focusComposerTextInput(attempt: Int = 0) {
        guard let panel = inputPanel else { return }

        activateForKeyboardInput(panel)

        guard let textView = firstComposerTextView(in: panel.contentView) else {
            guard attempt < 8 else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                self.focusComposerTextInput(attempt: attempt + 1)
            }
            return
        }

        panel.makeFirstResponder(textView)
        textView.window?.makeFirstResponder(textView)

        guard attempt < 8,
              (!NSApp.isActive ||
               !panel.isKeyWindow ||
               !isComposerTextInputFocused(in: panel)) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
            self.focusComposerTextInput(attempt: attempt + 1)
        }
    }

    private func activateForKeyboardInput(_ panel: NSPanel) {
        panel.ignoresMouseEvents = false
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    private func firstComposerTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }

        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = firstComposerTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    private func isComposerTextInputFocused(in panel: NSPanel) -> Bool {
        guard let textView = firstComposerTextView(in: panel.contentView) else {
            return false
        }

        return panel.firstResponder === textView ||
            textView.window?.firstResponder === textView
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

private struct NotchMetrics {
    static let fallbackVoidWidth: CGFloat = 180
    static let fallbackVoidHeight: CGFloat = 32
    static let maximumInferredVoidWidth: CGFloat = 220
    static let defaultScreenWidth: CGFloat = 1512

    var voidWidth: CGFloat
    var voidHeight: CGFloat
    var isExpanded: Bool
    var screenWidth: CGFloat

    var surfaceSize: CGSize {
        return CGSize(
            width: surfaceWidth,
            height: max(layout.visibleHeight, voidHeight + layout.visibleHeight)
        )
    }

    var layout: PointerPromptNotchLayout {
        PointerPromptNotchLayout(
            voidHeight: voidHeight,
            contentHorizontalInset: max(12, surfaceWidth * 0.035),
            visibleHeight: visibleHeight,
            cornerRadius: isExpanded ? 28 : 14
        )
    }

    private var surfaceWidth: CGFloat {
        if isExpanded {
            return min(max(360, screenWidth - 48), 690)
        }

        let contentAllowance: CGFloat = 170
        return min(max(voidWidth + contentAllowance, 300), min(420, screenWidth - 24))
    }

    private var visibleHeight: CGFloat {
        if isExpanded {
            let headerHeight: CGFloat = 52
            let rosterHeight = CGFloat(5 * 58 + 4 * 10)
            let verticalPadding: CGFloat = 12 + 10 + 52 + 12

            return headerHeight + rosterHeight + verticalPadding
        }

        return max(40, voidHeight + 14)
    }
}

private extension PointerPromptActivationModifier {
    var eventModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .command:
            .command
        }
    }
}
