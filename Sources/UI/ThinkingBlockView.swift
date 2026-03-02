import SwiftUI

// MARK: - Thinking Block View (completed messages)

/// Collapsible thinking block for completed (non-streaming) messages.
struct ThinkingBlockView: View {
    let thinking: ThinkingBlock
    @State private var isExpanded: Bool

    init(thinking: ThinkingBlock) {
        self.thinking = thinking
        let mode = Self.resolveDisplayMode()
        _isExpanded = State(initialValue: mode.startsExpandedOnComplete)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thinkingHeaderButton(isExpanded: isExpanded) {
                withAnimation(.spring(duration: 0.25, bounce: 0.0)) {
                    isExpanded.toggle()
                }
            }

            VStack(spacing: 0) {
                if isExpanded {
                    VStack(alignment: .leading, spacing: JinSpacing.small) {
                        Text(thinking.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(.horizontal, JinSpacing.medium)
                            .padding(.vertical, JinSpacing.small)
                    }
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)
                    .padding(.top, JinSpacing.xSmall)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipped()
        }
    }

    private static func resolveDisplayMode() -> ThinkingBlockDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.thinkingBlockDisplayMode) ?? ""
        return ThinkingBlockDisplayMode(rawValue: raw) ?? .expanded
    }
}

// MARK: - Streaming Thinking Block View

/// Collapsible thinking block for actively streaming messages.
///
/// In "Always Collapsed" mode, shows a compact header with an elegant
/// wave-dot animation to indicate active thinking. Users can click to
/// expand and see the streaming content at any time.
struct StreamingThinkingBlockView: View {
    let chunks: [String]
    let codeFont: Font
    @State private var isExpanded: Bool

    init(chunks: [String], codeFont: Font) {
        self.chunks = chunks
        self.codeFont = codeFont
        let mode = Self.resolveDisplayMode()
        _isExpanded = State(initialValue: mode.startsExpandedDuringStreaming)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            streamingHeaderButton(isExpanded: isExpanded) {
                withAnimation(.spring(duration: 0.25, bounce: 0.0)) {
                    isExpanded.toggle()
                }
            }

            VStack(spacing: 0) {
                if isExpanded {
                    ChunkedTextView(
                        chunks: chunks,
                        font: codeFont,
                        allowsTextSelection: false
                    )
                    .foregroundStyle(.secondary)
                    .padding(JinSpacing.small)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)
                    .padding(.top, JinSpacing.xSmall)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipped()
        }
    }

    private static func resolveDisplayMode() -> ThinkingBlockDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.thinkingBlockDisplayMode) ?? ""
        return ThinkingBlockDisplayMode(rawValue: raw) ?? .expanded
    }
}

// MARK: - Header Buttons

/// Header for a completed thinking block (static brain icon).
private func thinkingHeaderButton(isExpanded: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: "brain")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("Thinking")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
    }
    .buttonStyle(.plain)
}

/// Header for a streaming thinking block (pulsing brain icon + animated dots when collapsed).
private func streamingHeaderButton(isExpanded: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: JinSpacing.small) {
            ThinkingPulseIcon()

            Text("Thinking")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            if !isExpanded {
                ThinkingWaveDotsView()
                    .transition(.opacity)
            }

            Spacer()

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
    }
    .buttonStyle(.plain)
}

// MARK: - Thinking Pulse Icon

/// Brain icon with a gentle breathing pulse to indicate active thinking.
private struct ThinkingPulseIcon: View {
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: "brain")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .opacity(isPulsing ? 1.0 : 0.65)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Thinking Wave Dots

/// Three dots that gently bob in a wave pattern, indicating ongoing thought.
private struct ThinkingWaveDotsView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 4, height: 4)
                    .offset(y: isAnimating ? -2.5 : 2.5)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .padding(.leading, 2)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Previews

#Preview("Thinking Block - Completed") {
    ThinkingBlockView(
        thinking: ThinkingBlock(
            text: """
            First, I need to determine what the user is asking about. They want to know about photosynthesis.

            Let me break this down step by step:
            1. Photosynthesis is the process plants use to convert light into energy
            2. It occurs in chloroplasts
            3. The chemical equation is: 6CO2 + 6H2O + light -> C6H12O6 + 6O2

            I should explain this in simple terms for the user.
            """,
            signature: "SHA256:abc123"
        )
    )
    .padding()
    .frame(maxWidth: 600)
}

#Preview("Streaming Thinking - Collapsed") {
    StreamingThinkingBlockView(
        chunks: ["Analyzing the problem...\n\nLet me think step by step..."],
        codeFont: .system(.caption, design: .monospaced)
    )
    .padding()
    .frame(maxWidth: 600)
}
