import AppKit
import DonkeyContracts
import SwiftUI

@MainActor
public final class PointerPromptSpawnOverlayViewModel: ObservableObject {
    public let objectID = UUID().uuidString
    @Published public private(set) var state: PointerPromptSpawnState?
    @Published public private(set) var position: CGPoint = .zero
    @Published public private(set) var destination: CGPoint = .zero
    @Published public private(set) var screenSize: CGSize = .zero
    @Published public private(set) var opacity: Double = 0
    @Published public private(set) var isHolding = false
    @Published public private(set) var isSelected = false
    @Published public var inputText = ""
    @Published public var inputTextHeight: CGFloat = PointerPromptSpawnOverlayViewModel.inputMinimumTextHeight
    @Published public private(set) var isInputExpanded = false

    public var inputActivityChanged: ((Bool) -> Void)?
    public var followUpSubmitted: ((String, String, String) -> Void)?
    public var selected: ((String) -> Void)?

    private var animationGeneration = 0

    public init() {}

    public var isInputActive: Bool {
        state?.inputState == .editing
    }

    public var freezesMovement: Bool {
        PointerPromptSpawnLifecycle.freezesMovement(
            inputState: state?.inputState ?? .collapsed,
            draftText: inputText
        )
    }

    public var canSubmitInput: Bool {
        guard let state else { return false }

        return PointerPromptSpawnLifecycle.followUpSubmission(
            from: state,
            text: inputText
        ) != nil
    }

    public var hitTestFrame: CGRect {
        guard state != nil, isHolding else { return .null }

        let width: CGFloat = isInputActive ? 312 : 244
        let height: CGFloat = isInputActive ? 142 : 54
        let offset = labelOffset(in: screenSize)
        let origin = CGPoint(
            x: position.x + offset.width - width / 2,
            y: position.y + offset.height - height / 2
        )
        return cursorHitTestFrame
            .union(CGRect(origin: origin, size: CGSize(width: width, height: height)))
            .insetBy(dx: -14, dy: -14)
    }

    public var cursorHitTestFrame: CGRect {
        guard state != nil else { return .null }

        return CGRect(
            x: position.x - 22,
            y: position.y - 22,
            width: 44,
            height: 44
        )
    }

    public func labelOffset(in screenSize: CGSize) -> CGSize {
        let labelSize = CGSize(
            width: isInputActive ? 292 : 220,
            height: isInputActive ? 126 : 46
        )
        let margin: CGFloat = 20
        let rightOffset = Self.preferredLabelOffset
        let leftOffset = CGSize(width: -labelSize.width / 2 - 40, height: rightOffset.height)
        let upOffset = CGSize(width: rightOffset.width, height: -labelSize.height - 28)
        let upLeftOffset = CGSize(width: leftOffset.width, height: upOffset.height)

        if point(position, offsetBy: rightOffset, labelSize: labelSize, fitsIn: screenSize, margin: margin) {
            return rightOffset
        }
        if point(position, offsetBy: leftOffset, labelSize: labelSize, fitsIn: screenSize, margin: margin) {
            return leftOffset
        }
        if point(position, offsetBy: upOffset, labelSize: labelSize, fitsIn: screenSize, margin: margin) {
            return upOffset
        }
        return upLeftOffset
    }

    public func show(
        state: PointerPromptSpawnState,
        origin: CGPoint,
        destination: CGPoint,
        screenSize: CGSize
    ) {
        animationGeneration += 1
        self.state = state
        self.position = origin
        self.destination = destination
        self.screenSize = screenSize
        self.opacity = 0
        self.isHolding = false
        self.inputText = ""
        self.inputTextHeight = Self.inputMinimumTextHeight
        self.isInputExpanded = false
        inputActivityChanged?(false)

        let generation = animationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.animationGeneration == generation else { return }

            withAnimation(Self.travelAnimation) {
                self.position = destination
                self.opacity = 1
            }
            self.finishTravelAfterDelay(generation: generation)
        }
    }

    public func update(
        state: PointerPromptSpawnState,
        destination: CGPoint,
        screenSize: CGSize
    ) {
        guard self.state?.id == state.id else {
            show(state: state, origin: position, destination: destination, screenSize: screenSize)
            return
        }

        self.state = stateWithPreservedLocalInput(state)
        self.screenSize = screenSize
        guard state.phase != .fading else {
            fadeOut()
            return
        }

        guard !freezesMovement else { return }
        guard distance(from: self.destination, to: destination) > 1 else { return }

        animationGeneration += 1
        let generation = animationGeneration
        self.destination = destination
        self.isHolding = false
        withAnimation(Self.travelAnimation) {
            self.position = destination
            self.opacity = 1
        }
        finishTravelAfterDelay(generation: generation)
    }

    public func fadeOut() {
        animationGeneration += 1
        inputActivityChanged?(false)
        withAnimation(.easeOut(duration: 0.18)) {
            opacity = 0
        }

        let generation = animationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.animationGeneration == generation else { return }

            self.state = nil
            self.isHolding = false
            self.inputText = ""
            self.inputTextHeight = Self.inputMinimumTextHeight
            self.isInputExpanded = false
        }
    }

    public func beginInput() {
        guard var state, isHolding else { return }

        selected?(state.id)
        state.inputState = .editing
        state.updatedAt = Date()
        self.state = state
        inputActivityChanged?(true)
    }

    public func beginVoiceInput() {
        guard var state else { return }

        selected?(state.id)
        state.inputState = .editing
        state.label = "Listening..."
        state.updatedAt = Date()
        self.state = state
        inputText = ""
        inputTextHeight = Self.inputMinimumTextHeight
        isInputExpanded = false
        isHolding = true
        inputActivityChanged?(true)
    }

    public func applyTranscribedInput(_ text: String, submit: Bool) {
        guard var state else { return }

        state.inputState = .editing
        state.label = text.isEmpty ? "I didn't catch that" : "Heard you"
        state.updatedAt = Date()
        self.state = state
        inputText = text
        inputActivityChanged?(true)
        if submit {
            submitInput()
        }
    }

    public func collapseInput() {
        guard var state else { return }

        inputText = ""
        inputTextHeight = Self.inputMinimumTextHeight
        isInputExpanded = false
        state.inputState = .collapsed
        state.updatedAt = Date()
        self.state = state
        inputActivityChanged?(false)
    }

    public func submitInput() {
        guard var state,
              let submission = PointerPromptSpawnLifecycle.followUpSubmission(
                from: state,
                text: inputText
              )
        else { return }

        inputText = ""
        inputTextHeight = Self.inputMinimumTextHeight
        isInputExpanded = false
        state.inputState = .collapsed
        state.updatedAt = Date()
        self.state = state
        inputActivityChanged?(false)
        followUpSubmitted?(submission.spawnID, submission.taskID, submission.text)
    }

    public func setSelected(_ isSelected: Bool) {
        guard self.isSelected != isSelected else { return }

        self.isSelected = isSelected
    }

    public func select() {
        guard let state else { return }

        selected?(state.id)
    }

    public func updateInputTextHeight(_ height: CGFloat) {
        let clamped = min(max(height, Self.inputMinimumTextHeight), Self.inputMaximumTextHeight)
        guard abs(inputTextHeight - clamped) > 0.5 else { return }

        inputTextHeight = clamped
        isInputExpanded = clamped > Self.inputMinimumTextHeight + 1 || inputText.contains("\n")
    }

    private func finishTravelAfterDelay(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.travelDuration) { [weak self] in
            guard let self, self.animationGeneration == generation else { return }

            self.isHolding = true
            if var state = self.state, state.phase == .traveling || state.phase == .notchCue {
                state.phase = .holding
                state.updatedAt = Date()
                self.state = state
            }
        }
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func stateWithPreservedLocalInput(
        _ incomingState: PointerPromptSpawnState
    ) -> PointerPromptSpawnState {
        guard let currentState = state,
              currentState.id == incomingState.id,
              currentState.inputState == .editing
        else {
            return incomingState
        }

        var mergedState = incomingState
        mergedState.inputState = .editing
        return mergedState
    }

    private func point(
        _ point: CGPoint,
        offsetBy offset: CGSize,
        labelSize: CGSize,
        fitsIn screenSize: CGSize,
        margin: CGFloat
    ) -> Bool {
        let rect = CGRect(
            x: point.x + offset.width - labelSize.width / 2,
            y: point.y + offset.height - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        return rect.minX >= margin &&
            rect.minY >= margin &&
            rect.maxX <= screenSize.width - margin &&
            rect.maxY <= screenSize.height - margin
    }

    public static let travelDuration: TimeInterval = 0.82
    public static let inputMinimumTextHeight: CGFloat = 16
    public static let inputMaximumTextHeight: CGFloat = 76
    private static let preferredLabelOffset = CGSize(width: 138, height: 48)
    private static let travelAnimation = Animation.timingCurve(0.45, 0.05, 0.3, 1, duration: travelDuration)
}

@MainActor
public final class PointerPromptSpawnOverlayStore: ObservableObject {
    @Published public var viewModels: [PointerPromptSpawnOverlayViewModel] = []

    public init() {}
}

public struct PointerPromptSpawnOverlayContainerView: View {
    @ObservedObject private var store: PointerPromptSpawnOverlayStore

    public init(store: PointerPromptSpawnOverlayStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)

            ForEach(store.viewModels, id: \.objectID) { viewModel in
                PointerPromptSpawnOverlayView(viewModel: viewModel)
            }
        }
        .ignoresSafeArea()
    }
}

public struct PointerPromptSpawnOverlayView: View {
    @ObservedObject private var viewModel: PointerPromptSpawnOverlayViewModel
    @FocusState private var labelIsFocused: Bool

    public init(viewModel: PointerPromptSpawnOverlayViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)

                if let state = viewModel.state {
                    spawnSurface(state: state, screenSize: proxy.size)
                        .position(viewModel.position)
                        .opacity(viewModel.opacity)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func spawnSurface(
        state: PointerPromptSpawnState,
        screenSize: CGSize
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if viewModel.isHolding {
                Circle()
                    .stroke(accentColor(for: state.accentIndex).opacity(0.68), lineWidth: 1.4)
                    .frame(width: 36, height: 36)
                    .scaleEffect(holdingPulseScale)
                    .opacity(holdingPulseOpacity)
                    .position(.zero)
            }

            if viewModel.isSelected {
                Circle()
                    .stroke(Color.white.opacity(0.52), lineWidth: 1.2)
                    .frame(width: 42, height: 42)
                    .position(.zero)
            }

            cursor(state: state)
                .position(.zero)

            if viewModel.isHolding {
                stationaryLabel(state: state)
                    .offset(
                        x: viewModel.labelOffset(in: screenSize).width,
                        y: viewModel.labelOffset(in: screenSize).height
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.select()
        }
    }

    private func cursor(state: PointerPromptSpawnState) -> some View {
        SpawnPointerShape()
            .fill(accentColor(for: state.accentIndex))
            .overlay {
                SpawnPointerShape()
                    .stroke(Color.white.opacity(0.92), lineWidth: 1.5)
            }
            .shadow(color: Color.black.opacity(0.34), radius: 4, x: 0, y: 2)
            .frame(width: 28, height: 28)
            .rotationEffect(.degrees(cursorAngleDegrees + 50))
            .scaleEffect(viewModel.isHolding ? holdingCursorScale : 1)
    }

    private func stationaryLabel(state: PointerPromptSpawnState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TypewriterText(
                text: state.label,
                identity: PointerPromptSpawnGeometry.labelTypingIdentity(
                    spawnID: state.id,
                    label: state.label
                )
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

            if viewModel.isInputActive {
                compactInput
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: viewModel.isInputActive ? 292 : 220, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.82))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(viewModel.isInputActive ? 0.26 : 0.16), lineWidth: 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(viewModel.isSelected ? 0.34 : 0), lineWidth: 1.4)
                }
        }
        .shadow(color: Color.black.opacity(0.32), radius: 10, x: 0, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            viewModel.select()
            viewModel.beginInput()
        }
        .focusable(true)
        .focused($labelIsFocused)
        .onChange(of: labelIsFocused) {
            if labelIsFocused {
                viewModel.beginInput()
            }
        }
    }

    private var compactInput: some View {
        HStack(alignment: .bottom, spacing: 8) {
            SpawnLabelTextInput(
                text: $viewModel.inputText,
                isActive: viewModel.isInputActive,
                textHeightChanged: viewModel.updateInputTextHeight,
                submit: viewModel.submitInput,
                cancel: viewModel.collapseInput
            )
            .frame(height: viewModel.inputTextHeight)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .background(Color.white.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button(action: viewModel.submitInput) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.92))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmitInput)
        }
        .frame(width: 272)
    }

    private var cursorAngleDegrees: Double {
        PointerPromptSpawnGeometry.angleDegrees(
            from: viewModel.position,
            to: viewModel.destination
        )
    }

    private var holdingPulseScale: CGFloat {
        viewModel.freezesMovement ? 1.04 : 1.14
    }

    private var holdingPulseOpacity: Double {
        viewModel.freezesMovement ? 0.32 : 0.2
    }

    private var holdingCursorScale: CGFloat {
        viewModel.freezesMovement ? 1.02 : 1.08
    }

    private func accentColor(for index: Int) -> Color {
        Self.accentColors[((index % Self.accentColors.count) + Self.accentColors.count) % Self.accentColors.count]
    }

    private static let accentColors: [Color] = [
        Color(red: 0.114, green: 0.62, blue: 0.46),
        Color(red: 0.94, green: 0.62, blue: 0.15),
        Color(red: 0.83, green: 0.33, blue: 0.49),
        Color(red: 0.22, green: 0.54, blue: 0.87),
        Color(red: 0.5, green: 0.47, blue: 0.87),
        Color(red: 0.88, green: 0.35, blue: 0.28),
        Color(red: 0.24, green: 0.69, blue: 0.71),
        Color(red: 0.66, green: 0.34, blue: 0.79)
    ]
}

private struct TypewriterText: View {
    let text: String
    let identity: String
    @State private var visibleText = ""
    @State private var generation = UUID()

    var body: some View {
        Text(visibleText)
            .onAppear {
                restart()
            }
            .onChange(of: identity) {
                restart()
            }
    }

    private func restart() {
        let currentGeneration = UUID()
        generation = currentGeneration
        visibleText = ""

        let characters = Array(text)
        guard !characters.isEmpty else { return }

        for index in characters.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.026) {
                guard generation == currentGeneration else { return }

                visibleText = String(characters[...index])
            }
        }
    }
}

private struct SpawnLabelTextInput: NSViewRepresentable {
    @Binding var text: String
    let isActive: Bool
    let textHeightChanged: @MainActor (CGFloat) -> Void
    let submit: @MainActor () -> Void
    let cancel: @MainActor () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = SpawnLabelTextView()
        textView.delegate = context.coordinator
        textView.shouldFocusWhenAttached = isActive
        textView.submit = {
            Task { @MainActor in
                submit()
            }
        }
        textView.cancel = {
            Task { @MainActor in
                cancel()
            }
        }
        textView.string = text
        textView.insertionPointColor = .white
        SpawnLabelTextStyle.apply(to: textView)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = CGSize(width: 0, height: PointerPromptSpawnOverlayViewModel.inputMinimumTextHeight)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SpawnLabelTextView else { return }

        textView.shouldFocusWhenAttached = isActive
        textView.submit = {
            Task { @MainActor in
                submit()
            }
        }
        textView.cancel = {
            Task { @MainActor in
                cancel()
            }
        }
        SpawnLabelTextStyle.apply(to: textView)

        if textView.string != text {
            textView.string = text
            SpawnLabelTextStyle.apply(to: textView)
            textView.needsDisplay = true
        }

        DispatchQueue.main.async {
            context.coordinator.updateTextContainerWidth(for: textView, in: scrollView)
            context.coordinator.reportTextHeight(for: textView)

            if isActive, textView.window?.firstResponder !== textView {
                textView.focusIfNeeded()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpawnLabelTextInput

        init(parent: SpawnLabelTextInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? SpawnLabelTextView else { return }

            parent.text = textView.string
            textView.needsDisplay = true
            reportTextHeight(for: textView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func updateTextContainerWidth(
            for textView: NSTextView,
            in scrollView: NSScrollView
        ) {
            let width = max(1, scrollView.contentView.bounds.width)
            textView.textContainer?.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            let documentHeight = max(
                PointerPromptSpawnOverlayViewModel.inputMinimumTextHeight,
                measuredTextHeight(for: textView)
            )
            textView.frame = CGRect(x: 0, y: 0, width: width, height: documentHeight)
        }

        func reportTextHeight(for textView: NSTextView) {
            parent.textHeightChanged(measuredTextHeight(for: textView))
        }

        private func measuredTextHeight(for textView: NSTextView) -> CGFloat {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return PointerPromptSpawnOverlayViewModel.inputMinimumTextHeight
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return ceil(max(
                PointerPromptSpawnOverlayViewModel.inputMinimumTextHeight,
                usedRect.height
            ))
        }
    }
}

private final class SpawnLabelTextView: NSTextView {
    var submit: (() -> Void)?
    var cancel: (() -> Void)?
    var shouldFocusWhenAttached = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }

    func focusIfNeeded() {
        guard shouldFocusWhenAttached else { return }

        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let isEscape = event.keyCode == 53
        let shouldInsertNewline = event.modifierFlags.contains(.shift)

        if isEscape {
            cancel?()
            return
        }

        if isReturn, !shouldInsertNewline {
            submit?()
            return
        }

        super.keyDown(with: event)
    }
}

@MainActor
private enum SpawnLabelTextStyle {
    static var font: NSFont {
        NSFont.systemFont(ofSize: 12, weight: .regular)
    }

    static func apply(to textView: NSTextView) {
        let textAttributes = attributes(color: .white, font: font)
        textView.font = font
        textView.textColor = .white
        textView.typingAttributes = textAttributes

        let textRange = NSRange(location: 0, length: textView.string.utf16.count)
        guard textRange.length > 0 else { return }

        textView.textStorage?.setAttributes(textAttributes, range: textRange)
    }

    static func attributes(
        color: NSColor,
        font: NSFont
    ) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: color,
            .font: font,
            .ligature: 0
        ]
    }
}

private struct SpawnPointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: svgPoint(x: 83.086, y: 5.6406, width: w, height: h))
        path.addLine(to: svgPoint(x: 10.453, y: 34.6836, width: w, height: h))
        path.addCurve(
            to: svgPoint(x: 11.13269, y: 51.0276, width: w, height: h),
            control1: svgPoint(x: 2.8514, y: 37.7227, width: w, height: h),
            control2: svgPoint(x: 3.3085, y: 48.6326, width: w, height: h)
        )
        path.addLine(to: svgPoint(x: 35.69469, y: 58.5471, width: w, height: h))
        path.addCurve(
            to: svgPoint(x: 41.44859, y: 64.301, width: w, height: h),
            control1: svgPoint(x: 38.44859, y: 59.39085, width: w, height: h),
            control2: svgPoint(x: 40.60489, y: 61.5471, width: w, height: h)
        )
        path.addLine(to: svgPoint(x: 48.96809, y: 88.863, width: w, height: h))
        path.addCurve(
            to: svgPoint(x: 65.31209, y: 89.54269, width: w, height: h),
            control1: svgPoint(x: 51.36649, y: 96.6911, width: w, height: h),
            control2: svgPoint(x: 62.27309, y: 97.1442, width: w, height: h)
        )
        path.addLine(to: svgPoint(x: 94.35509, y: 16.90969, width: w, height: h))
        path.addCurve(
            to: svgPoint(x: 83.08209, y: 5.63669, width: w, height: h),
            control1: svgPoint(x: 97.18709, y: 9.83159, width: w, height: h),
            control2: svgPoint(x: 90.15979, y: 2.80769, width: w, height: h)
        )
        path.closeSubpath()

        return path
    }

    private func svgPoint(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(
            x: x / 100 * width,
            y: y / 100 * height
        )
    }
}
