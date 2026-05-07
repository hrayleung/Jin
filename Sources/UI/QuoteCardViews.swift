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
        MessageSelectionSupport.selectionIsEmpty(selectedText)
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
        QuoteCardPresentationSupport.sourceLine(
            role: quote.sourceRole,
            modelName: quote.sourceModelName
        )
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
        Text(quote.quotedText)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var composerHeader: QuoteCardPresentationSupport.ComposerHeader {
        QuoteCardPresentationSupport.composerHeader(
            role: quote.sourceRole,
            modelName: quote.sourceModelName
        )
    }

    private var composerQuoteBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: JinSpacing.xSmall + 2) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(QuoteCardPalette.accent)

                if let iconID = quote.sourceProviderIconID {
                    ProviderIconView(iconID: iconID, fallbackSystemName: "sparkles", size: 11)
                        .frame(width: 11, height: 11)
                }

                headerLabel

                Spacer(minLength: JinSpacing.xSmall)

                accessory
                    .layoutPriority(1)
            }

            Text(quote.quotedText)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.86))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, JinSpacing.medium + 4)
        .padding(.trailing, JinSpacing.small + 2)
        .padding(.vertical, JinSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .fill(JinSemanticColor.subtleSurface)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                .fill(QuoteCardPalette.accent)
                .frame(width: 2.5)
                .padding(.vertical, JinSpacing.small)
                .padding(.leading, JinSpacing.small)
        }
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .stroke(JinSemanticColor.separator.opacity(0.5), lineWidth: JinStrokeWidth.hairline)
        )
    }

    @ViewBuilder
    private var headerLabel: some View {
        let header = composerHeader
        if let modelName = header.modelName {
            HStack(spacing: 4) {
                Text(header.prefix)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(modelName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text(header.prefix)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

struct ComposerQuoteCardView: View, Equatable {
    let quote: DraftQuote
    let onRemove: () -> Void

    var body: some View {
        QuoteCardContainer(quote: quote.content, density: .composer) {
            QuoteDismissButton(action: onRemove)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.quote == rhs.quote
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        )
    }
}

private struct QuoteDismissButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(
                    isHovering
                        ? AnyShapeStyle(Color.primary.opacity(0.78))
                        : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
                )
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Remove quote")
        .help("Remove quote")
    }
}
