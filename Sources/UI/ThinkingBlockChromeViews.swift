import SwiftUI
import AppKit

struct ThinkingBlockHeaderButton: View {
    let isExpanded: Bool
    let copyText: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        // Flat header: chevron + semantic icon + title + hover-revealed copy.
        // The streaming bubble header owns the turn's only animated orb.
        HStack(spacing: JinSpacing.small) {
            // Disclosure chevron leftmost, hugging the title cluster —
            // matches macOS native DisclosureGroup / Finder folder pattern.
            chevronDisclosureButton

            titleDisclosureButton

            // Copy fades in on hover but reserves layout space so the row
            // doesn't jump. Matches Claude/ChatGPT message-action pattern.
            copyAffordance
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeOut(duration: 0.12), value: isHovering)

            Spacer(minLength: 0)
        }
        .frame(minHeight: ThinkingHeaderCopyButton.hitSize)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // No surface — Thinking lives inline in the message like MCP/tool blocks.
    }

    private var titleDisclosureButton: some View {
        Button(action: action) {
            HStack(spacing: JinSpacing.xSmall) {
                headerIcon
                titleText
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevronDisclosureButton: some View {
        Button(action: action) {
            disclosureIndicator
                .padding(.leading, JinSpacing.xSmall)
                .padding(.vertical, JinSpacing.xSmall)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
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
        Image(systemName: "brain")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(JinSemanticColor.textSecondary)
            .frame(width: 16, height: 16)
    }

    private var titleText: some View {
        Text("Thinking")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
    }

    private var disclosureIndicator: some View {
        JinDisclosureChevron(
            isExpanded: isExpanded,
            font: .caption.weight(.semibold),
            foregroundStyle: JinSemanticColor.textTertiary
        )
    }
}

struct ThinkingBlockExpandedTextContent: View {
    let text: String

    var body: some View {
        AttributedTextBlock(
            attributedString: attributedText,
            contentSignature: contentSignature
        )
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
    }

    private var attributedText: NSAttributedString {
        CJKPunctuationSpacing.applied(to: NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
    }

    private var contentSignature: UInt64 {
        var hasher = FNVHasher()
        hasher.combine("thinking")
        hasher.combine(text)
        return hasher.value
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
    @State private var resetTask: Task<Void, Never>?

    private static let glyphSize: CGFloat = JinControlMetrics.iconButtonGlyphSize
    fileprivate static let hitSize: CGFloat = 20

    var body: some View {
        Button(action: copy) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: Self.glyphSize, weight: .semibold))
                .foregroundStyle(glyphColor)
                .symbolRenderingMode(.monochrome)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(didCopy ? "Copied" : "Copy thinking")
        .onDisappear {
            resetTask?.cancel()
        }
    }

    private var glyphColor: Color {
        didCopy ? Color.accentColor : .secondary
    }

    @MainActor
    private func copy() {
        PasteboardSupport.writeString(text)

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


