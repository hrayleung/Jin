import SwiftUI

struct ThinkingBlockHeaderButton: View {
    enum Style {
        case completed
        case streaming
    }

    let style: Style
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            headerRow
        }
        .buttonStyle(.plain)
    }

    private var headerRow: some View {
        HStack(spacing: JinSpacing.small) {
            headerIcon
            titleText
            streamingIndicator
            Spacer()
            disclosureIndicator
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch style {
        case .completed:
            Image(systemName: "brain")
                .font(.subheadline)
                .foregroundStyle(.primary)
        case .streaming:
            ThinkingPulseIcon()
        }
    }

    private var titleText: some View {
        Text("Thinking")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        if style == .streaming, !isExpanded {
            ThinkingWaveDotsView()
                .transition(.opacity)
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}

struct ThinkingBlockExpandedTextContent: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            textContent
        }
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
        .padding(.top, JinSpacing.xSmall)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var textContent: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
    }
}

struct StreamingThinkingBlockExpandedContent: View {
    let chunks: [String]
    let codeFont: Font

    var body: some View {
        chunkedText
            .foregroundStyle(.secondary)
            .padding(JinSpacing.small)
            .jinSurface(.subtle, cornerRadius: JinRadius.small)
            .padding(.top, JinSpacing.xSmall)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var chunkedText: some View {
        ChunkedTextView(
            chunks: chunks,
            font: codeFont,
            allowsTextSelection: false
        )
    }
}

private struct ThinkingPulseIcon: View {
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: "brain")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .scaleEffect(pulseScale)
            .opacity(pulseOpacity)
            .animation(pulseAnimation, value: isPulsing)
            .onAppear { isPulsing = true }
    }

    private var pulseScale: CGFloat {
        isPulsing ? 1.1 : 1.0
    }

    private var pulseOpacity: Double {
        isPulsing ? 1.0 : 0.65
    }

    private var pulseAnimation: Animation {
        .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    }
}

private struct ThinkingWaveDotsView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                dot(at: index)
            }
        }
        .padding(.leading, 2)
        .onAppear { isAnimating = true }
    }

    private func dot(at index: Int) -> some View {
        Circle()
            .fill(.secondary)
            .frame(width: 4, height: 4)
            .offset(y: dotOffset)
            .animation(dotAnimation(for: index), value: isAnimating)
    }

    private var dotOffset: CGFloat {
        isAnimating ? -2.5 : 2.5
    }

    private func dotAnimation(for index: Int) -> Animation {
        .easeInOut(duration: 0.5)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.15)
    }
}
