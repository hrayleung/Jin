import SwiftUI

// MARK: - Thinking Block View (completed messages)

/// Collapsible thinking block for completed (non-streaming) messages.
struct ThinkingBlockView: View {
    let thinking: ThinkingBlock
    /// Optional height-invalidation hook for parents that version-gate layout.
    var onExpansionChanged: () -> Void = {}
    @State private var isExpanded: Bool

    init(thinking: ThinkingBlock, onExpansionChanged: @escaping () -> Void = {}) {
        self.thinking = thinking
        self.onExpansionChanged = onExpansionChanged
        let mode = Self.resolveDisplayMode()
        _isExpanded = State(
            initialValue: ThinkingBlockSupport.initialExpansionForCompletedBlock(
                displayMode: mode
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThinkingBlockHeaderButton(
                style: .completed,
                isExpanded: isExpanded,
                copyText: thinking.text
            ) {
                let expanding = !isExpanded
                withAnimation(JinMotion.disclosure(expanding: expanding)) {
                    isExpanded = expanding
                }
            }

            // Always mounted — thinking content is plain text (no favicon
            // .task cost), so keep it in-tree and drive height through the
            // animatable clip for a continuous spring instead of
            // insert/remove transitions that reflow the timeline row.
            JinCollapsibleContent(isExpanded: isExpanded) {
                ThinkingBlockExpandedTextContent(text: thinking.text)
            }
        }
        .onChange(of: isExpanded) { _, _ in
            onExpansionChanged()
        }
    }

    private static func resolveDisplayMode() -> ThinkingBlockDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.thinkingBlockDisplayMode) ?? ""
        return ThinkingBlockSupport.displayMode(rawValue: raw)
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
    let isThinkingComplete: Bool
    /// Fired whenever `isExpanded` changes (manual toggle or the
    /// auto-collapse on completion). The streaming bubble's
    /// `ConstrainedWidth` cache is version-gated on `renderTick`, which
    /// doesn't tick for this row-internal state change — the host must
    /// bump its layout version or the row keeps the stale height and the
    /// expanded content is clipped at the old row bottom.
    let onExpansionChanged: () -> Void
    @State private var isExpanded: Bool

    init(
        chunks: [String],
        codeFont: Font,
        isThinkingComplete: Bool = false,
        onExpansionChanged: @escaping () -> Void = {}
    ) {
        self.chunks = chunks
        self.codeFont = codeFont
        self.isThinkingComplete = isThinkingComplete
        self.onExpansionChanged = onExpansionChanged
        let mode = Self.resolveDisplayMode()
        _isExpanded = State(
            initialValue: ThinkingBlockSupport.initialExpansionForStreamingBlock(
                displayMode: mode
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThinkingBlockHeaderButton(
                style: isThinkingComplete ? .completed : .streaming,
                isExpanded: isExpanded,
                copyText: chunks.joined()
            ) {
                let expanding = !isExpanded
                withAnimation(JinMotion.disclosure(expanding: expanding)) {
                    isExpanded = expanding
                }
            }

            JinCollapsibleContent(isExpanded: isExpanded) {
                StreamingThinkingBlockExpandedContent(
                    chunks: chunks,
                    codeFont: codeFont
                )
            }
        }
        .onChange(of: isThinkingComplete) { _, complete in
            let mode = Self.resolveDisplayMode()
            if let shouldExpand = ThinkingBlockSupport.shouldExpandAfterThinkingCompletion(
                isComplete: complete,
                displayMode: mode
            ) {
                withAnimation(JinMotion.disclosure(expanding: shouldExpand)) {
                    isExpanded = shouldExpand
                }
            }
        }
        .onChange(of: isExpanded) { _, _ in
            onExpansionChanged()
        }
    }

    private static func resolveDisplayMode() -> ThinkingBlockDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.thinkingBlockDisplayMode) ?? ""
        return ThinkingBlockSupport.displayMode(rawValue: raw)
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
