import SwiftUI

struct DraftQuote: Identifiable, Hashable, Sendable {
    let id: UUID
    let content: QuoteContent

    init(id: UUID = UUID(), content: QuoteContent) {
        self.id = id
        self.content = content
    }
}

struct MessageSelectionSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let messageID: UUID
    let contextThreadID: UUID?
    let anchorID: String
    let selectedText: String
    let prefixContext: String?
    let suffixContext: String?
    let startOffset: Int
    let endOffset: Int
    let matchingHighlightIDs: [UUID]

    init(
        id: UUID = UUID(),
        messageID: UUID,
        contextThreadID: UUID? = nil,
        anchorID: String,
        selectedText: String,
        prefixContext: String? = nil,
        suffixContext: String? = nil,
        startOffset: Int,
        endOffset: Int,
        matchingHighlightIDs: [UUID] = []
    ) {
        self.id = id
        self.messageID = messageID
        self.contextThreadID = contextThreadID
        self.anchorID = anchorID
        self.selectedText = selectedText
        self.prefixContext = prefixContext
        self.suffixContext = suffixContext
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.matchingHighlightIDs = matchingHighlightIDs
    }

    var isEmpty: Bool {
        selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MessageTextSelectionActions {
    let onQuote: (MessageSelectionSnapshot) -> Void
    let onHighlight: (MessageSelectionSnapshot) -> Void
    let onRemoveHighlights: ([UUID]) -> Void

    static let none = MessageTextSelectionActions(
        onQuote: { _ in },
        onHighlight: { _ in },
        onRemoveHighlights: { _ in }
    )
}

private enum QuoteCardPalette {
    static let accent = JinSemanticColor.quoteAccent
    static let fill = JinSemanticColor.quoteSurface
    static let fillStrong = JinSemanticColor.quoteSurfaceStrong
}

private enum QuoteCardDensity {
    case message
    case composer
}

private struct QuoteCardContainer<Accessory: View>: View {
    let quote: QuoteContent
    let density: QuoteCardDensity
    let accessory: Accessory

    init(
        quote: QuoteContent,
        density: QuoteCardDensity = .message,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.quote = quote
        self.density = density
        self.accessory = accessory()
    }

    private var sourceLine: String {
        let base: String
        switch quote.sourceRole {
        case .assistant?:
            base = "Assistant"
        case .user?:
            base = "User"
        case .system?:
            base = "System"
        case .tool?:
            base = "Tool"
        case nil:
            base = "Quoted"
        }

        if let model = quote.sourceModelName?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            return "\(base) · \(model)"
        }
        return base
    }

    var body: some View {
        Group {
            switch density {
            case .message:
                messageQuoteBody
            case .composer:
                composerQuoteBody
            }
        }
    }

    @ViewBuilder
    private var quoteTextContent: some View {
        switch density {
        case .message:
            Text(quote.quotedText)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case .composer:
            ScrollView(.vertical, showsIndicators: true) {
                Text(quote.quotedText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 4)
            }
            .frame(minHeight: 52, maxHeight: 112, alignment: .top)
        }
    }

    private var messageQuoteBody: some View {
        HStack(alignment: .top, spacing: JinSpacing.medium) {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(QuoteCardPalette.accent.opacity(0.88))
                .frame(width: 2.5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Quote")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuoteCardPalette.accent)

                    Text(sourceLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                quoteTextContent
            }
        }
        .padding(.leading, 2)
        .padding(.vertical, 2)
        .modifier(QuoteCardSizingModifier(density: .message))
    }

    private var composerQuoteBody: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                Label("Quote", systemImage: "quote.opening")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuoteCardPalette.accent)

                Text(sourceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                accessory
            }

            quoteTextContent
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .modifier(QuoteCardSizingModifier(density: .composer))
        .background(
            RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                .fill(QuoteCardPalette.fill)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [QuoteCardPalette.accent.opacity(0.95), QuoteCardPalette.accent.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, 8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                .stroke(QuoteCardPalette.fillStrong, lineWidth: JinStrokeWidth.hairline)
        )
    }
}

private struct QuoteCardSizingModifier: ViewModifier {
    let density: QuoteCardDensity

    func body(content: Content) -> some View {
        switch density {
        case .message:
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)

        case .composer:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MessageQuoteCardView: View {
    let quote: QuoteContent

    var body: some View {
        QuoteCardContainer(quote: quote, density: .message) {
            EmptyView()
        }
    }
}

struct ComposerQuoteCardView: View {
    let quote: DraftQuote
    let onRemove: () -> Void

    var body: some View {
        QuoteCardContainer(quote: quote.content, density: .composer) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove quote")
        }
    }
}
