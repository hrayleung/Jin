import Foundation

enum ChatHistoryTruncator {
    static func truncatedHistory(_ history: [Message], contextWindow: Int, reservedOutputTokens: Int) -> [Message] {
        guard contextWindow > 0 else { return history }

        let effectiveReserved = min(max(0, reservedOutputTokens), contextWindow)
        let budget = max(0, contextWindow - effectiveReserved)

        guard history.count > 2 else { return history }

        var prefix: [Message] = []
        var index = 0
        while index < history.count, history[index].role == .system {
            prefix.append(history[index])
            index += 1
        }

        var totalTokens = prefix.reduce(0) { $0 + approximateTokenCount(for: $1) }
        var tail: [Message] = []

        for message in history[index...].reversed() {
            let tokens = approximateTokenCount(for: message)
            if totalTokens + tokens <= budget || tail.isEmpty {
                tail.append(message)
                totalTokens += tokens
                continue
            }
            break
        }

        return prefix + tail.reversed()
    }

    static func approximateTokenCount(for history: [Message]) -> Int {
        history.reduce(0) { $0 + approximateTokenCount(for: $1) }
    }

    static func approximateTokenCount(for message: Message) -> Int {
        var tokens = 4 // role/metadata overhead

        for part in message.content {
            tokens += approximateTokenCount(for: part)
        }

        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                tokens += approximateTokenCount(for: call.name)
                for (key, value) in call.arguments {
                    tokens += approximateTokenCount(for: key)
                    tokens += approximateTokenCount(for: String(describing: value.value))
                }
                if let signature = call.signature {
                    tokens += approximateTokenCount(for: signature)
                }
            }
        }

        if let toolResults = message.toolResults {
            for result in toolResults {
                if let toolName = result.toolName {
                    tokens += approximateTokenCount(for: toolName)
                }
                tokens += approximateTokenCount(for: result.content)
                if let signature = result.signature {
                    tokens += approximateTokenCount(for: signature)
                }
            }
        }

        return tokens
    }

    private static func approximateTokenCount(for part: ContentPart) -> Int {
        switch part {
        case .text(let text):
            return approximateTokenCount(for: text)
        case .quote(let quote):
            return approximateTokenCount(for: quote.quotedText)
        case .thinking(let thinking):
            return approximateTokenCount(for: thinking.text)
        case .redactedThinking:
            return 16
        case .image(let image):
            return imageTokenEstimate(for: image)
        case .file(let file):
            let extractedTokens = approximateTokenCount(for: file.extractedText ?? "")
            return approximateTokenCount(for: file.filename) + max(256, extractedTokens)
        case .audio:
            return 1024
        case .video(let video):
            return video.data != nil ? 1536 : 384
        }
    }

    private static func approximateTokenCount(for text: String) -> Int {
        guard let trimmed = text.trimmedNonEmpty else { return 0 }
        return max(1, trimmed.count / 4)
    }

    /// Vision inputs bill by resolution, not by a flat constant: ~w×h/750
    /// tracks Anthropic's published formula, and OpenAI's tile math lands in
    /// the same range. The previous flat 256 for disk-backed images
    /// undercounted a full-resolution photo ~10×, so media-bearing turns
    /// never aged out of a truncated history — every send re-read and
    /// re-encoded the entire conversation's images forever.
    private static func imageTokenEstimate(for image: ImageContent) -> Int {
        if let pixels = ImagePixelDimensionsCache.dimensions(for: image) {
            return max(256, Int((pixels.width * pixels.height) / 750))
        }
        // Unknown size (unreadable header, remote URL): assume a large image
        // rather than a trivial one.
        return 1500
    }
}
