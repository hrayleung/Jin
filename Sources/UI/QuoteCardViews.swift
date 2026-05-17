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
    let accessoryFocused: Bool
    let accessory: Accessory

    @State private var isHovering = false

    init(
        quote: QuoteContent,
        density: QuoteCardDensity = .message,
        accessoryFocused: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.quote = quote
        self.density = density
        self.accessoryFocused = accessoryFocused
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

    private var composerTooltip: String {
        let header = composerHeader
        let prefix: String
        if let modelName = header.modelName {
            prefix = "\(header.prefix) \(modelName)"
        } else {
            prefix = header.prefix
        }
        return "\(prefix)\n\n\(quote.quotedText)"
    }

    private var composerQuoteBody: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(QuoteCardPalette.accent)
                .frame(width: 2)
                .padding(.vertical, JinSpacing.small - 2)
                .padding(.leading, JinSpacing.small - 2)

            Text(quote.quotedText)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(QuoteCardLayout.composerLineLimit)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.leading, JinSpacing.small)
                .padding(.trailing, JinSpacing.small)
                .padding(.vertical, JinSpacing.small)
        }
        .frame(
            width: QuoteCardLayout.composerWidth,
            height: QuoteCardLayout.composerHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(JinSemanticColor.subtleSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline)
        )
        .overlay(alignment: .topTrailing) {
            accessory
                .opacity(isHovering || accessoryFocused ? 1 : 0)
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                .animation(.easeInOut(duration: 0.12), value: accessoryFocused)
                .padding(.top, 2)
                .padding(.trailing, 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        .onHover { isHovering = $0 }
        .help(composerTooltip)
    }
}

enum QuoteCardLayout {
    static let composerWidth: CGFloat = 160
    static let composerHeight: CGFloat = 76
    static let composerLineLimit: Int = 4
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

    @State private var isDismissFocused = false

    var body: some View {
        QuoteCardContainer(
            quote: quote.content,
            density: .composer,
            accessoryFocused: isDismissFocused
        ) {
            QuoteDismissButton(action: onRemove, isFocused: $isDismissFocused)
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
    @Binding var isFocused: Bool

    @State private var isHovering = false
    @FocusState private var isButtonFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(
                    isHovering || isButtonFocused
                        ? AnyShapeStyle(Color.primary.opacity(0.85))
                        : AnyShapeStyle(Color.primary.opacity(0.55))
                )
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .opacity(isHovering || isButtonFocused ? 1 : 0.85)
                )
                .overlay(
                    Circle()
                        .stroke(
                            isButtonFocused ? Color.accentColor.opacity(0.7) : Color.clear,
                            lineWidth: JinStrokeWidth.regular
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isButtonFocused)
        .onChange(of: isButtonFocused) { _, newValue in
            isFocused = newValue
        }
        .onHover { isHovering = $0 }
        .accessibilityLabel("Remove quote")
        .help("Remove quote")
    }
}
