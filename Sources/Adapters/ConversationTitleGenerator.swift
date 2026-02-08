import Foundation

actor ConversationTitleGenerator {
    private let providerManager: ProviderManager

    init(providerManager: ProviderManager = ProviderManager()) {
        self.providerManager = providerManager
    }

    func generateTitle(
        providerConfig: ProviderConfig,
        modelID: String,
        contextMessages: [Message],
        maxCharacters: Int = 20
    ) async throws -> String {
        let trimmedContext = contextMessages.filter { !$0.content.isEmpty }
        guard !trimmedContext.isEmpty else {
            throw LLMError.invalidRequest(message: "No context to generate title.")
        }

        let adapter = try await providerManager.createAdapter(for: providerConfig)

        let instruction = """
Generate a concise chat title in the user's language.
Rules:
- Return title text only
- No quotation marks
- No emojis
- Neutral and descriptive
- Max \(maxCharacters) characters
"""

        let requestMessages: [Message] = [
            Message(role: .system, content: [.text(instruction)]),
            Message(role: .user, content: [.text(renderContextText(trimmedContext))])
        ]

        let stream = try await adapter.sendMessage(
            messages: requestMessages,
            modelID: modelID,
            controls: GenerationControls(temperature: 0.2, maxTokens: 64),
            tools: [],
            streaming: false
        )

        var collected = ""
        for try await event in stream {
            if case .contentDelta(let part) = event,
               case .text(let text) = part {
                collected.append(text)
            }
        }

        let normalized = Self.normalizeTitle(collected, maxCharacters: maxCharacters)
        guard !normalized.isEmpty else {
            throw LLMError.decodingError(message: "Empty generated title.")
        }

        return normalized
    }

    private func renderContextText(_ messages: [Message]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(messages.count)

        for message in messages {
            let role = message.role.rawValue
            let content = message.content.compactMap { part -> String? in
                switch part {
                case .text(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                case .file(let file):
                    let fallback = AttachmentPromptRenderer.fallbackText(for: file)
                    let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                case .image:
                    return "[image]"
                case .thinking, .redactedThinking, .audio, .video:
                    return nil
                }
            }
            let merged = content.joined(separator: "\n")
            if !merged.isEmpty {
                lines.append("\(role): \(merged)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func normalizeTitle(_ raw: String, maxCharacters: Int = 20) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }

        if text.hasPrefix("“") && text.hasSuffix("”") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }

        if let firstLine = text.split(whereSeparator: \.isNewline).first {
            text = String(firstLine)
        }

        while text.hasPrefix("标题:") || text.hasPrefix("Title:") {
            if let colon = text.firstIndex(of: ":") {
                text = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                break
            }
        }

        text = text.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }
}
