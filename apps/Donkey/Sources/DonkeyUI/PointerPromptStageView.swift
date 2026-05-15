import AppKit
import DonkeyContracts
import SwiftUI

public struct PointerPromptStageView: View {
    private let state: PointerPromptState
    @Binding private var messageText: String
    private let placement: PointerPromptPlacement
    private weak var intentSink: (any PointerPromptIntentSink)?

    public init(
        state: PointerPromptState,
        messageText: Binding<String>,
        placement: PointerPromptPlacement = .bottomRight,
        intentSink: any PointerPromptIntentSink
    ) {
        self.state = state
        self._messageText = messageText
        self.placement = placement
        self.intentSink = intentSink
    }

    public var body: some View {
        promptContent
            .padding(.horizontal, PointerPromptLayout.stageHorizontalPadding)
            .padding(.vertical, PointerPromptLayout.stageVerticalPadding)
            .background(Color.clear)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var promptContent: some View {
        if placement.placesContentOnLeft {
            HStack(alignment: .top, spacing: PointerPromptLayout.pointerComposerSpacing) {
                activeComposer
                pointer
            }
        } else {
            HStack(alignment: .top, spacing: PointerPromptLayout.pointerComposerSpacing) {
                pointer
                activeComposer
            }
        }
    }

    private var pointer: some View {
        AgentPointerView(
            placement: placement,
            theme: state.theme,
            isActive: state.isActive
        )
        .frame(
            width: PointerPromptLayout.pointerSlotSize.width,
            height: PointerPromptLayout.pointerSlotSize.height
        )
    }

    private var composer: some View {
        PointerPromptComposer(
            state: state,
            messageText: $messageText,
            addContext: {
                intentSink?.handle(.addContextRequested)
            },
            voiceInput: {
                intentSink?.handle(.voiceInputRequested)
            },
            dismiss: {
                intentSink?.handle(.dismissed)
            },
            submit: {
                intentSink?.handle(.messageSubmitted(text: messageText))
            }
        )
        .frame(
            width: PointerPromptLayout.composerSize.width,
            height: PointerPromptLayout.composerSize.height
        )
    }

    private var activeComposer: some View {
        composer
            .opacity(state.isActive ? 1 : 0)
            .allowsHitTesting(state.isActive)
            .accessibilityHidden(!state.isActive)
    }
}

private struct PointerPromptComposer: View {
    let state: PointerPromptState
    @Binding var messageText: String
    let addContext: @MainActor () -> Void
    let voiceInput: @MainActor () -> Void
    let dismiss: @MainActor () -> Void
    let submit: @MainActor () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(state.promptText, text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .focused($isFocused)
                    .onSubmit(submit)
                    .accessibilityLabel("Message for Donkey")
                    .frame(maxWidth: .infinity)
                    .padding(.leading, closeButtonContentClearance)

                Divider()

                HStack(spacing: 10) {
                    ComposerToolbarButton(
                        systemName: "plus",
                        title: "Add",
                        action: addContext
                    )

                    ComposerToolbarButton(
                        systemName: "waveform",
                        title: "Voice",
                        action: voiceInput
                    )

                    Spacer(minLength: 12)

                    ComposerToolbarButton(
                        systemName: "arrow.up",
                        title: "Send",
                        isProminent: true,
                        isDisabled: isSubmitDisabled,
                        action: submit
                    )
                }
            }
            .padding(16)

            ComposerCloseButton(action: dismiss)
                .padding(.leading, PointerPromptLayout.closeButtonInset)
                .padding(.top, PointerPromptLayout.closeButtonInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: PointerPromptLayout.composerCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: PointerPromptLayout.composerCornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(state.isActive ? 0.16 : 0.08),
            radius: state.isActive ? 14 : 8,
            x: 0,
            y: state.isActive ? 6 : 3
        )
        .controlSize(.regular)
        .onAppear(perform: syncFocusWithActiveState)
        .onChange(of: state.isActive) { _, _ in
            syncFocusWithActiveState()
        }
    }

    private var isSubmitDisabled: Bool {
        !state.isPrimaryActionEnabled ||
            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var closeButtonContentClearance: CGFloat {
        PointerPromptLayout.closeButtonInset +
            PointerPromptLayout.closeButtonSize
    }

    private func syncFocusWithActiveState() {
        guard state.isActive else {
            isFocused = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFocused = true
        }
    }
}

private struct ComposerCloseButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .systemRed))
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                    }

                Image(systemName: "xmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.58))
            }
            .frame(
                width: PointerPromptLayout.closeButtonSize,
                height: PointerPromptLayout.closeButtonSize
            )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Close prompt")
    }
}

private struct ComposerToolbarButton: View {
    let systemName: String
    let title: String
    var isProminent = false
    var isDisabled = false
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

private struct AgentPointerView: View {
    let placement: PointerPromptPlacement
    let theme: PointerPromptTheme
    let isActive: Bool

    var body: some View {
        ZStack(alignment: shapeAlignment) {
            if isActive {
                Ellipse()
                    .fill(Color(promptColor: theme.activeShadow))
                    .frame(width: 17, height: 5)
                    .blur(radius: 2)
                    .offset(y: 11)
            }

            AgentPointerShape()
                .fill(Color(promptColor: theme.pointerFill))
                .overlay {
                    AgentPointerShape()
                        .stroke(
                            Color(promptColor: theme.accent),
                            style: StrokeStyle(
                                lineWidth: PointerPromptLayout.pointerStrokeWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
                .shadow(
                    color: Color(promptColor: theme.accent).opacity(isActive ? 0.12 : 0),
                    radius: isActive ? 3 : 0,
                    x: 0,
                    y: isActive ? 2 : 0
                )
                .frame(
                    width: PointerPromptLayout.pointerVisualSize.width,
                    height: PointerPromptLayout.pointerVisualSize.height
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: shapeAlignment)
        .accessibilityHidden(true)
    }

    private var shapeAlignment: Alignment {
        Alignment(
            horizontal: placement.placesContentOnLeft ? .leading : .trailing,
            vertical: .top
        )
    }
}

private struct AgentPointerShape: Shape {
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
            x: (100 - x) / 100 * width,
            y: y / 100 * height
        )
    }
}

private extension Color {
    init(promptColor: PointerPromptColor) {
        self.init(
            red: promptColor.red,
            green: promptColor.green,
            blue: promptColor.blue,
            opacity: promptColor.alpha
        )
    }
}
