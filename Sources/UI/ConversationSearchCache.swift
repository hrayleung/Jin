import Foundation

/// Caches extracted plain text from conversation messages for efficient content search.
///
/// On the first search, message `contentData` (JSON-encoded `[ContentPart]`) is decoded and the
/// text portions are concatenated per conversation. Subsequent searches reuse the cached text.
/// The cache self-invalidates when the message count for a conversation changes (e.g. new messages
/// are added or messages are deleted).
final class ConversationSearchCache {
    private var textCache: [UUID: String] = [:]
    private var messageCounts: [UUID: Int] = [:]

    /// Returns the searchable plain text for a conversation, building the cache entry if needed.
    func searchableText(for conversation: ConversationEntity) -> String {
        let currentCount = conversation.messages.count

        if let cached = textCache[conversation.id],
           messageCounts[conversation.id] == currentCount {
            return cached
        }

        let text = Self.extractSearchableText(from: conversation.messages)
        textCache[conversation.id] = text
        messageCounts[conversation.id] = currentCount
        return text
    }

    // MARK: - Text Extraction

    /// Extracts searchable plain text from user and assistant messages.
    /// Excludes tool/system messages and thinking/redacted blocks.
    static func extractSearchableText(from messages: [MessageEntity]) -> String {
        let decoder = JSONDecoder()
        let searchableRoles: Set<String> = [
            MessageRole.user.rawValue,
            MessageRole.assistant.rawValue,
        ]

        return messages
            .filter { searchableRoles.contains($0.role) }
            .compactMap { message -> String? in
                guard let parts = try? decoder.decode([ContentPart].self, from: message.contentData) else {
                    return nil
                }

                let texts = parts.compactMap { part -> String? in
                    switch part {
                    case .text(let text): return text
                    case .file(let file): return file.filename
                    default: return nil
                    }
                }

                return texts.isEmpty ? nil : texts.joined(separator: " ")
            }
            .joined(separator: "\n")
    }

    // MARK: - Snippet Extraction

    /// Extracts a short snippet around the first match of `query` in `text`.
    /// Returns `nil` if the query is not found.
    static func extractSnippet(from text: String, query: String, maxLength: Int = 80) -> String? {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let contextBefore = 20
        let snippetStart = max(0, matchStart - contextBefore)
        let startIdx = text.index(text.startIndex, offsetBy: snippetStart)
        let remaining = text.distance(from: startIdx, to: text.endIndex)
        let endIdx = text.index(startIdx, offsetBy: min(maxLength, remaining))

        var snippet = String(text[startIdx..<endIdx])
            .components(separatedBy: .newlines)
            .joined(separator: " ")

        if snippetStart > 0 { snippet = "…" + snippet }
        if endIdx < text.endIndex { snippet += "…" }

        return snippet
    }
}
