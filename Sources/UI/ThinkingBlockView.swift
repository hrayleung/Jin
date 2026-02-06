import SwiftUI

/// Collapsible thinking block view.
struct ThinkingBlockView: View {
    let thinking: ThinkingBlock
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: JinSpacing.small) {
                    Image(systemName: "brain")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Thinking")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, JinSpacing.small)
                .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
            }
            .buttonStyle(.plain)

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
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.vertical, JinSpacing.xSmall)
    }
}

/// Redacted thinking block view (encrypted content)
struct RedactedThinkingBlockView: View {
    let redactedThinking: RedactedThinkingBlock

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Encrypted reasoning")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.xSmall + 2)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
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
