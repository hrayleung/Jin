import SwiftUI

// MARK: - Thinking Block View (completed messages)

/// Collapsible thinking block for completed (non-streaming) messages.
struct ThinkingBlockView: View {
    let thinking: ThinkingBlock
    @State private var isExpanded: Bool

    init(thinking: ThinkingBlock) {
        self.thinking = thinking
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
                withAnimation(.spring(duration: 0.25, bounce: 0.0)) {
                    isExpanded.toggle()
                }
            }

            VStack(spacing: 0) {
                if isExpanded {
                    ThinkingBlockExpandedTextContent(text: thinking.text)
                }
            }
            .clipped()
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
    @State private var isExpanded: Bool

    init(chunks: [String], codeFont: Font, isThinkingComplete: Bool = false) {
        self.chunks = chunks
        self.codeFont = codeFont
        self.isThinkingComplete = isThinkingComplete
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
                withAnimation(.spring(duration: 0.25, bounce: 0.0)) {
                    isExpanded.toggle()
                }
            }

            VStack(spacing: 0) {
                if isExpanded {
                    StreamingThinkingBlockExpandedContent(
                        chunks: chunks,
                        codeFont: codeFont
                    )
                }
            }
            .clipped()
        }
        .onChange(of: isThinkingComplete) { _, complete in
            let mode = Self.resolveDisplayMode()
            if let shouldExpand = ThinkingBlockSupport.shouldExpandAfterThinkingCompletion(
                isComplete: complete,
                displayMode: mode
            ) {
                withAnimation(.spring(duration: 0.25, bounce: 0.0)) {
                    isExpanded = shouldExpand
                }
            }
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
