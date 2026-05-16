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

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            // Left cluster: title is the disclosure target. Copy + streaming
            // sit *next to* the title (not pushed to the right margin) so the
            // user doesn't have to traverse the row to find them.
            Button(action: action) {
                HStack(spacing: JinSpacing.xSmall) {
                    headerIcon
                    titleText
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Copy fades in on hover but reserves layout space so the row
            // doesn't jump. Matches Claude/ChatGPT message-action pattern.
            copyAffordance
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeOut(duration: 0.12), value: isHovering)

            streamingIndicator

            Spacer(minLength: 0)

            // Chevron stays on the right as the conventional disclosure cue;
            // both left cluster and chevron toggle expanded state.
            Button(action: action) {
                disclosureIndicator
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: ThinkingHeaderCopyButton.hitSize)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // No surface — Thinking lives inline in the message like MCP/tool blocks.
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
            .foregroundStyle(JinSemanticColor.textTertiary)
    }
}

struct ThinkingBlockExpandedTextContent: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(JinSemanticColor.textSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, JinSpacing.medium)
            .padding(.top, JinSpacing.xSmall)
            .overlay(alignment: .leading) {
                // Subtle left accent line, marker for "this is reasoning content"
                // without dropping a full-bleed background.
                Rectangle()
                    .fill(JinSemanticColor.borderEmphasized)
                    .frame(width: 2)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct StreamingThinkingBlockExpandedContent: View {
    let chunks: [String]
    let codeFont: Font

    var body: some View {
        chunkedText
            .foregroundStyle(JinSemanticColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, JinSpacing.medium)
            .padding(.top, JinSpacing.xSmall)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(JinSemanticColor.borderEmphasized)
                    .frame(width: 2)
            }
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
    fileprivate static let hitSize: CGFloat = 22

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
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }

    private var pulseScale: CGFloat {
        isPulsing ? 1.1 : 1.0
    }

    private var pulseOpacity: Double {
        isPulsing ? 1.0 : 0.65
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
