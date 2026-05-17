import Foundation
import SwiftData
import SwiftUI

extension ChatView {
    func draftQuote(
        from snapshot: MessageSelectionSnapshot,
        sourceModelName: String?,
        sourceProviderIconID: String?
    ) -> DraftQuote? {
        guard let selectedText = MessageSelectionSupport.normalizedSelectedText(snapshot.selectedText) else {
            return nil
        }

        return DraftQuote(
            content: QuoteContent(
                sourceMessageID: snapshot.messageID,
                // Quotes currently originate from assistant reply selection only.
                sourceRole: .assistant,
                sourceModelName: sourceModelName,
                sourceProviderIconID: sourceProviderIconID,
                quotedText: selectedText,
                prefixContext: snapshot.prefixContext,
                suffixContext: snapshot.suffixContext
            )
        )
    }

    func addDraftQuote(
        from snapshot: MessageSelectionSnapshot,
        sourceModelName: String?,
        sourceProviderIconID: String?
    ) {
        guard let quote = draftQuote(
            from: snapshot,
            sourceModelName: sourceModelName,
            sourceProviderIconID: sourceProviderIconID
        ) else { return }
        let alreadyExists = draftQuotes.contains {
            $0.content.sourceMessageID == quote.content.sourceMessageID
                && $0.content.sourceRole == quote.content.sourceRole
                && $0.content.sourceModelName == quote.content.sourceModelName
                && $0.content.quotedText == quote.content.quotedText
                && $0.content.prefixContext == quote.content.prefixContext
                && $0.content.suffixContext == quote.content.suffixContext
        }
        if !alreadyExists {
            withAnimation(quoteListAnimation) {
                draftQuotes.append(quote)
            }
        }
        if isComposerHidden {
            showComposer()
        } else {
            isComposerFocused = true
        }
    }

    var quoteListAnimation: Animation {
        accessibilityReduceMotion
            ? .linear(duration: 0.12)
            : .spring(response: 0.32, dampingFraction: 0.86)
    }

    func persistHighlight(from snapshot: MessageSelectionSnapshot) {
        guard let selectedText = MessageSelectionSupport.normalizedSelectedText(snapshot.selectedText) else {
            return
        }
        guard let messageEntity = renderCache.messageEntitiesByID[snapshot.messageID]
                ?? conversationEntity.messages.first(where: { $0.id == snapshot.messageID }) else {
            return
        }

        let duplicate = messageEntity.highlights.contains {
            $0.anchorID == snapshot.anchorID
                && $0.startOffset == snapshot.startOffset
                && $0.endOffset == snapshot.endOffset
                && $0.selectedText == selectedText
        }
        guard !duplicate else { return }

        let highlight = MessageHighlightEntity(
            messageID: snapshot.messageID,
            conversationID: conversationEntity.id,
            anchorID: snapshot.anchorID,
            selectedText: selectedText,
            prefixContext: snapshot.prefixContext,
            suffixContext: snapshot.suffixContext,
            startOffset: snapshot.startOffset,
            endOffset: snapshot.endOffset,
            colorStyle: .readerYellow
        )
        highlight.message = messageEntity
        highlight.conversation = conversationEntity
        highlight.syncIDsWithRelationships()
        messageEntity.highlights.append(highlight)
        conversationEntity.messageHighlights.append(highlight)

        do {
            try modelContext.save()
            DispatchQueue.main.async { [self] in
                rebuildMessageCaches()
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    func removeHighlights(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let highlights = conversationEntity.messageHighlights.filter { idSet.contains($0.id) }
        guard !highlights.isEmpty else { return }

        for highlight in highlights {
            modelContext.delete(highlight)
        }

        do {
            try modelContext.save()
            DispatchQueue.main.async { [self] in
                rebuildMessageCaches()
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
