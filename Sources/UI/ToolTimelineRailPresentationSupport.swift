import SwiftUI

extension ToolTimelinePresentationSupport {
    enum TerminalStatusNodeGlyph: Equatable {
        case running
        case success
        case error
        case neutral

        init(status: ToolCallExecutionStatus) {
            switch status {
            case .running:
                self = .running
            case .success:
                self = .success
            case .error:
                self = .error
            }
        }
    }

    struct TerminalTimelineRail: View {
        let glyph: TerminalStatusNodeGlyph
        let style: StatusVisualStyle
        let showsConnectorAbove: Bool
        let showsConnectorBelow: Bool
        let isRunningPulse: Bool

        init(
            status: ToolCallExecutionStatus,
            style: StatusVisualStyle,
            showsConnectorAbove: Bool,
            showsConnectorBelow: Bool,
            isRunningPulse: Bool
        ) {
            self.init(
                glyph: TerminalStatusNodeGlyph(status: status),
                style: style,
                showsConnectorAbove: showsConnectorAbove,
                showsConnectorBelow: showsConnectorBelow,
                isRunningPulse: isRunningPulse
            )
        }

        init(
            glyph: TerminalStatusNodeGlyph,
            style: StatusVisualStyle,
            showsConnectorAbove: Bool,
            showsConnectorBelow: Bool,
            isRunningPulse: Bool
        ) {
            self.glyph = glyph
            self.style = style
            self.showsConnectorAbove = showsConnectorAbove
            self.showsConnectorBelow = showsConnectorBelow
            self.isRunningPulse = isRunningPulse
        }

        var body: some View {
            VStack(spacing: 2) {
                connectorSegment(visible: showsConnectorAbove)

                TerminalStatusNode(
                    glyph: glyph,
                    style: style,
                    isRunningPulse: isRunningPulse
                )

                connectorSegment(visible: showsConnectorBelow)
            }
            .frame(width: 16)
            .padding(.top, JinSpacing.xSmall)
        }

        private func connectorSegment(visible: Bool) -> some View {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.7))
                .frame(width: JinStrokeWidth.regular, height: 12)
                .opacity(visible ? 1 : 0)
        }
    }

    private struct TerminalStatusNode: View {
        let glyph: TerminalStatusNodeGlyph
        let style: StatusVisualStyle
        let isRunningPulse: Bool

        var body: some View {
            ZStack {
                Circle()
                    .fill(style.nodeBackground)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(style.nodeBorder, lineWidth: 0.75)
                    )

                glyphContent
            }
        }

        @ViewBuilder
        private var glyphContent: some View {
            switch glyph {
            case .running:
                Circle()
                    .fill(style.accent)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isRunningPulse ? 1.4 : 0.85)
                    .opacity(isRunningPulse ? 0.35 : 1)
                    .animation(
                        .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                        value: isRunningPulse
                    )
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            case .error:
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            case .neutral:
                Image(systemName: "questionmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
        }
    }
}
