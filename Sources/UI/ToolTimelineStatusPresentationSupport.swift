import SwiftUI

extension ToolTimelinePresentationSupport {
    struct CompactStatusStyle {
        let text: String
        let icon: String
        let color: Color

        init(text: String, icon: String, color: Color) {
            self.text = text
            self.icon = icon
            self.color = color
        }

        init(text: String, icon: String, tone: StatusTone) {
            self.init(text: text, icon: icon, color: tone.color)
        }

        init(_ status: CodeExecutionTimelineSupport.CompactStatus) {
            self.init(text: status.text, icon: status.icon, tone: status.kind.timelineTone)
        }
    }

    struct CompactStatusBadge: View {
        enum Variant: Equatable {
            case capsule
            case inline
        }

        let style: CompactStatusStyle
        var variant: Variant = .capsule

        var body: some View {
            compactContent
                .foregroundStyle(style.color.opacity(0.9))
                .background {
                    if variant == .capsule {
                        Capsule(style: .continuous)
                            .fill(style.color.opacity(0.1))
                    }
                }
                .lineLimit(1)
        }

        private var compactContent: some View {
            HStack(spacing: 4) {
                Image(systemName: style.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(style.text)
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, variant == .capsule ? 6 : 0)
            .padding(.vertical, variant == .capsule ? 3 : 0)
        }
    }

    static func emphasizedCompactStatusColor(
        for tone: MCPToolTimelineSupport.CompactStatusBadge.Tone
    ) -> Color {
        tone.timelineTone.emphasizedColor
    }

    struct RunningIndicator: View {
        @State private var isAnimating = false

        var body: some View {
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: isAnimating ? -2.5 : 2.5)
                        .animation(
                            .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12),
                            value: isAnimating
                        )
                }
            }
            .frame(height: 10)
            .onAppear { isAnimating = true }
        }
    }

    struct StatusPill: View {
        let status: ToolCallExecutionStatus
        let label: String
        let textColor: Color
        let accentColor: Color

        var body: some View {
            HStack(spacing: 5) {
                FilledStatusGlyph(status: status, color: accentColor)
                Text(label)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.1))
            )
            .lineLimit(1)
        }
    }

    struct InlineStatusLabel: View {
        let glyph: TerminalStatusNodeGlyph
        let label: String
        let detail: String?
        let textColor: Color
        let accentColor: Color

        init(
            status: ToolCallExecutionStatus,
            label: String,
            detail: String? = nil,
            textColor: Color,
            accentColor: Color
        ) {
            self.init(
                glyph: TerminalStatusNodeGlyph(status: status),
                label: label,
                detail: detail,
                textColor: textColor,
                accentColor: accentColor
            )
        }

        init(
            glyph: TerminalStatusNodeGlyph,
            label: String,
            detail: String? = nil,
            textColor: Color,
            accentColor: Color
        ) {
            self.glyph = glyph
            self.label = label
            self.detail = detail
            self.textColor = textColor
            self.accentColor = accentColor
        }

        var body: some View {
            HStack(spacing: 6) {
                InlineStatusGlyph(glyph: glyph, color: accentColor)

                Text(label)

                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(textColor)
            .lineLimit(1)
        }
    }

    private struct InlineStatusGlyph: View {
        let glyph: TerminalStatusNodeGlyph
        let color: Color

        var body: some View {
            switch glyph {
            case .running:
                Circle()
                    .fill(color)
                    .frame(width: 4.5, height: 4.5)
            case .success:
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            case .error:
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            case .neutral:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
    }

    private struct FilledStatusGlyph: View {
        let status: ToolCallExecutionStatus
        let color: Color

        var body: some View {
            switch status {
            case .running:
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(color)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
    }
}

private extension CodeExecutionTimelineSupport.CompactStatusKind {
    var timelineTone: ToolTimelinePresentationSupport.StatusTone {
        switch self {
        case .success:
            return .success
        case .failure:
            return .failure
        }
    }
}

private extension MCPToolTimelineSupport.CompactStatusBadge.Tone {
    var timelineTone: ToolTimelinePresentationSupport.StatusTone {
        switch self {
        case .success:
            return .success
        case .failure:
            return .failure
        }
    }
}
