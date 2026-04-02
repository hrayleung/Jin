import Foundation
import SwiftData

extension ChatView {
    func draftQuote(from snapshot: MessageSelectionSnapshot, sourceModelName: String?) -> DraftQuote? {
        let trimmed = snapshot.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return DraftQuote(
            content: QuoteContent(
                sourceMessageID: snapshot.messageID,
                sourceThreadID: snapshot.contextThreadID,
                sourceRole: .assistant,
                sourceModelName: sourceModelName,
                quotedText: trimmed,
                prefixContext: snapshot.prefixContext,
                suffixContext: snapshot.suffixContext
            )
        )
    }

    func addDraftQuote(from snapshot: MessageSelectionSnapshot, sourceModelName: String?) {
        guard let quote = draftQuote(from: snapshot, sourceModelName: sourceModelName) else { return }
        let alreadyExists = draftQuotes.contains {
            $0.content.sourceMessageID == quote.content.sourceMessageID
                && $0.content.sourceThreadID == quote.content.sourceThreadID
                && $0.content.sourceRole == quote.content.sourceRole
                && $0.content.sourceModelName == quote.content.sourceModelName
                && $0.content.quotedText == quote.content.quotedText
                && $0.content.prefixContext == quote.content.prefixContext
                && $0.content.suffixContext == quote.content.suffixContext
        }
        if !alreadyExists {
            draftQuotes.append(quote)
        }
        if isComposerHidden {
            showComposer()
        } else {
            isComposerFocused = true
        }
    }

    func persistHighlight(from snapshot: MessageSelectionSnapshot) {
        let trimmed = snapshot.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let messageEntity = cachedMessageEntitiesByID[snapshot.messageID]
                ?? conversationEntity.messages.first(where: { $0.id == snapshot.messageID }) else {
            return
        }

        let duplicate = messageEntity.highlights.contains {
            $0.anchorID == snapshot.anchorID
                && $0.startOffset == snapshot.startOffset
                && $0.endOffset == snapshot.endOffset
                && $0.selectedText == trimmed
        }
        guard !duplicate else { return }

        let highlight = MessageHighlightEntity(
            messageID: snapshot.messageID,
            conversationID: conversationEntity.id,
            contextThreadID: snapshot.contextThreadID,
            anchorID: snapshot.anchorID,
            selectedText: trimmed,
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
            rebuildMessageCaches()
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
            rebuildMessageCaches()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
