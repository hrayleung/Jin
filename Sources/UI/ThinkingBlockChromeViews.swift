import SwiftUI
import AppKit

struct ThinkingBlockHeaderButton: View {
    enum Style {
        case completed
        case streaming
    }

    let style: Style
    let isExpanded: Bool
    let copyText: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: JinSpacing.xSmall) {
            disclosureRegion
            copyAffordance
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
    }

    private var disclosureRegion: some View {
        Button(action: action) {
            HStack(spacing: JinSpacing.small) {
                headerIcon
                titleText
                streamingIndicator
                Spacer(minLength: JinSpacing.small)
                disclosureIndicator
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var copyAffordance: some View {
        if !copyText.isEmpty {
            ThinkingHeaderCopyButton(text: copyText)
                .accessibilityLabel("Copy thinking")
        }
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

struct ThinkingHeaderCopyButton: View {
    let text: String

    @State private var didCopy = false
    @State private var isHovering = false
    @State private var resetTask: Task<Void, Never>?

    private static let glyphSize: CGFloat = 11
    private static let hitSize: CGFloat = 22

    var body: some View {
        Button(action: copy) {
            ZStack {
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(backgroundFill)
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: Self.glyphSize, weight: .semibold))
                    .foregroundStyle(glyphColor)
                    .symbolRenderingMode(.monochrome)
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .frame(width: Self.hitSize, height: Self.hitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(didCopy ? "Copied" : "Copy thinking")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .onDisappear {
            resetTask?.cancel()
        }
    }

    private var backgroundFill: Color {
        if didCopy {
            return Color.accentColor.opacity(0.18)
        }
        return isHovering
            ? JinSemanticColor.subtleSurfaceStrong
            : Color.clear
    }

    private var glyphColor: Color {
        didCopy ? Color.accentColor : .secondary
    }

    @MainActor
    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation(.easeInOut(duration: 0.18)) {
            didCopy = true
        }

        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                didCopy = false
            }
        }
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
