import SwiftUI

/// Collapsible thinking block view.
struct ThinkingBlockView: View {
    let thinking: ThinkingBlock
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - Always visible, clickable to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Thinking icon
                    Image(systemName: "brain")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    Text("Thinking")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Chevron indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(thinking.text)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.05))
                )
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Redacted thinking block view (encrypted content)
struct RedactedThinkingBlockView: View {
    let redactedThinking: RedactedThinkingBlock

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text("Encrypted reasoning")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Preview

#Preview("Thinking Block - Collapsed") {
    ThinkingBlockView(
        thinking: ThinkingBlock(
            text: """
            First, I need to determine what the user is asking about. They want to know about photosynthesis.

            Let me break this down step by step:
            1. Photosynthesis is the process plants use to convert light into energy
            2. It occurs in chloroplasts
            3. The chemical equation is: 6CO2 + 6H2O + light → C6H12O6 + 6O2

            I should explain this in simple terms for the user.
            """,
            signature: "SHA256:abc123"
        )
    )
    .padding()
    .frame(maxWidth: 600)
}

#Preview("Redacted Thinking") {
    RedactedThinkingBlockView(
        redactedThinking: RedactedThinkingBlock(
            data: "gAAAAABotI9-FK1PbhZhaZk4yMrZw3XDI1AWFaKb9T0NQq7LndK6zaRB..."
        )
    )
    .padding()
}
