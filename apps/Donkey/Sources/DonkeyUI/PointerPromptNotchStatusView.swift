import DonkeyContracts
import SwiftUI

public struct PointerPromptNotchStatusView: View {
    private let state: PointerPromptState
    private let updateState: PointerPromptUpdateState
    private let layout: PointerPromptNotchLayout
    private let surfaceWidth: CGFloat
    private let surfaceHeight: CGFloat
    private let isExpanded: Bool
    private let hoverChanged: @MainActor (Bool) -> Void
    private let commandRequested: @MainActor () -> Void
    private let updateRequested: @MainActor () -> Void

    public init(
        state: PointerPromptState,
        updateState: PointerPromptUpdateState,
        layout: PointerPromptNotchLayout,
        surfaceWidth: CGFloat,
        surfaceHeight: CGFloat,
        isExpanded: Bool,
        hoverChanged: @escaping @MainActor (Bool) -> Void,
        commandRequested: @escaping @MainActor () -> Void,
        updateRequested: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.updateState = updateState
        self.layout = layout
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
        self.isExpanded = isExpanded
        self.hoverChanged = hoverChanged
        self.commandRequested = commandRequested
        self.updateRequested = updateRequested
    }

    public var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: cornerRadius,
                    bottomTrailing: cornerRadius,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .fill(Color.black)

            content
                .offset(y: max(0, layout.voidHeight))
        }
        .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
        .clipped()
        .onHover { isHovering in
            Task { @MainActor in
                hoverChanged(isHovering)
            }
        }
        .animation(.smooth(duration: 0.24), value: isExpanded)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        if isExpanded {
            expandedContent
        } else {
            collapsedContent
        }
    }

    private var collapsedContent: some View {
        HStack(spacing: 10) {
            agentIcon(agent: activeAgent, size: 25, symbolSize: 11)

            Text("\(activeAgent.name) · \(activeAgent.subtitle)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if activeAgent.isRunning {
                activityBars(color: activeAgent.color)
            }
        }
        .padding(.horizontal, max(12, layout.contentHorizontalInset))
        .frame(
            width: surfaceWidth,
            height: layout.visibleHeight,
            alignment: .center
        )
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            expandedHeader

            VStack(spacing: 10) {
                ForEach(displayAgentRows) { agent in
                    expandedAgentRow(agent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Spacer(minLength: 10)

            commandRow
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .frame(
            width: surfaceWidth,
            height: max(0, surfaceHeight - layout.voidHeight),
            alignment: .top
        )
    }

    private var expandedHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(activeAgent.color.opacity(0.92))

                Image(systemName: "face.smiling")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 22, height: 22)

            Text("Donkey")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))

            Text("\(runningAgentCount) of 5 running")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.42))

            Spacer()

            if let updateTitle = updateState.headerButtonTitle {
                Button(action: updateRequested) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(red: 0.94, green: 0.62, blue: 0.15))
                            .frame(width: 7, height: 7)

                        Text(updateTitle)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color(red: 0.94, green: 0.62, blue: 0.15).opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button(action: commandRequested) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .regular))
                    Text("new task")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.46))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func expandedAgentRow(_ agent: NotchAgentDisplay) -> some View {
        HStack(spacing: 14) {
            agentIcon(agent: agent, size: 32, symbolSize: 15)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(agent.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))

                    Text(agent.statusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(agent.isRunning ? agent.color : Color.white.opacity(0.44))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(agent.isRunning ? agent.color.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Text(agent.isRunning ? agent.subtitle : "No active task")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer()

            if agent.isRunning {
                activityBars(color: agent.color)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background {
            if agent.isRunning {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(agent.color.opacity(0.1))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(agent.color)
                            .frame(width: 3)
                    }
            }
        }
    }

    private var commandRow: some View {
        Button(action: commandRequested) {
            HStack(spacing: 13) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))

                Text("Tell donkey what to do...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))

                Spacer()

                Text("⌘ K")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func agentIcon(
        agent: NotchAgentDisplay,
        size: CGFloat,
        symbolSize: CGFloat
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(agent.color)

            Image(systemName: agent.symbolName)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
    }

    private func activityBars(color: Color) -> some View {
        HStack(spacing: 3) {
            ForEach([0.44, 0.82, 0.58], id: \.self) { scale in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 3, height: 18 * scale)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var activeAgent: NotchAgentDisplay {
        displayAgentRows[0]
    }

    private var activeSubtitle: String {
        switch state.leadingSignalLevel {
        case .idle:
            return "resting"
        case .ready:
            let text = state.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return "ready" }
            return text
        case .thinking:
            return "ranking models on SWE-bench"
        }
    }

    private var activeStatusLabel: String {
        switch state.leadingSignalLevel {
        case .idle:
            return "idle"
        case .ready:
            return "done"
        case .thinking:
            return "running"
        }
    }

    private var runningAgentCount: Int {
        displayAgentRows.filter(\.isRunning).count
    }

    private var displayAgentRows: [NotchAgentDisplay] {
        var rows = baseAgentRows
        rows[0].subtitle = activeSubtitle
        rows[0].statusLabel = activeStatusLabel
        rows[0].isRunning = state.leadingSignalLevel == .thinking
        return rows
    }

    private var baseAgentRows: [NotchAgentDisplay] {
        [
            NotchAgentDisplay(
                id: "coder",
                name: "Coder",
                subtitle: "Ranking models on SWE-bench",
                statusLabel: "running",
                symbolName: "chevron.left.forwardslash.chevron.right",
                color: Color(red: 0.114, green: 0.62, blue: 0.46),
                isRunning: true
            ),
            NotchAgentDisplay(
                id: "browser",
                name: "Browser",
                subtitle: "Pulling pricing from 3 sites",
                statusLabel: "idle",
                symbolName: "globe",
                color: Color(red: 0.94, green: 0.62, blue: 0.15),
                isRunning: false
            ),
            NotchAgentDisplay(
                id: "researcher",
                name: "Researcher",
                subtitle: "Reading 12 ArXiv papers",
                statusLabel: "idle",
                symbolName: "magnifyingglass",
                color: Color(red: 0.83, green: 0.33, blue: 0.49),
                isRunning: false
            ),
            NotchAgentDisplay(
                id: "inbox",
                name: "Inbox",
                subtitle: "Drafting reply to recruiter",
                statusLabel: "idle",
                symbolName: "envelope",
                color: Color(red: 0.22, green: 0.54, blue: 0.87),
                isRunning: false
            ),
            NotchAgentDisplay(
                id: "scheduler",
                name: "Scheduler",
                subtitle: "Finding slots across KST/PT",
                statusLabel: "idle",
                symbolName: "calendar",
                color: Color(red: 0.5, green: 0.47, blue: 0.87),
                isRunning: false
            )
        ]
    }

    private var cornerRadius: CGFloat {
        layout.cornerRadius
    }
}

private struct NotchAgentDisplay: Identifiable {
    var id: String
    var name: String
    var subtitle: String
    var statusLabel: String
    var symbolName: String
    var color: Color
    var isRunning: Bool
}
