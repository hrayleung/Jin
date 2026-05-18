import Foundation
import NaturalLanguage

actor ConversationTitleGenerator {
    private let providerManager: ProviderManager

    init(providerManager: ProviderManager = ProviderManager()) {
        self.providerManager = providerManager
    }

    static let maxCharactersPlaceholder = "{maxCharacters}"
    static let languagePlaceholder = "{language}"
    static let fallbackLanguageInstruction = "the same language as the user's first message"

    private static let minimumLanguageDetectionLetterCount = 12
    private static let minimumLanguageDetectionWordCount = 3
    private static let minimumLanguageDetectionConfidence = 0.75
    private static let minimumLanguageDetectionConfidenceMargin = 0.25

    static let defaultPromptTemplate = """
You are writing a short title for a chat conversation. The title appears in a sidebar list, so it must let the user instantly recall what the chat is about.

CRITICAL: Write the title in \(languagePlaceholder). Do not translate, do not transliterate, do not mix in any other language.

Other rules:
- Be specific to the topic. Mention the concrete subject, technology, or question. Avoid generic words like question, discussion, help, or chat.
- Hard limit: \(maxCharactersPlaceholder) characters. Keep it tight and scannable.
- Plain text only. No surrounding quotes, no ending punctuation, no emoji, no prefix label, no Markdown.

Output the title text and nothing else.
"""

    func generateTitle(
        providerConfig: ProviderConfig,
        modelID: String,
        contextMessages: [Message],
        maxCharacters: Int = 24,
        promptTemplate: String? = nil
    ) async throws -> String {
        let trimmedContext = contextMessages.filter { !$0.content.isEmpty }
        guard !trimmedContext.isEmpty else {
            throw LLMError.invalidRequest(message: "No context to generate title.")
        }

        let contextText = Self.renderContextText(trimmedContext)
        guard !contextText.isEmpty else {
            throw LLMError.invalidRequest(message: "No usable text in context messages.")
        }

        let adapter = try await providerManager.createAdapter(for: providerConfig)

        let resolvedTemplate = promptTemplate?.trimmedNonEmpty ?? Self.defaultPromptTemplate
        let language = Self.detectLanguageName(from: trimmedContext)
        let instruction = resolvedTemplate
            .replacingOccurrences(of: Self.maxCharactersPlaceholder, with: String(maxCharacters))
            .replacingOccurrences(of: Self.languagePlaceholder, with: language)

        let requestMessages: [Message] = [
            Message(role: .system, content: [.text(instruction)]),
            Message(role: .user, content: [.text(contextText)])
        ]

        let titleControls = GenerationControls(
            temperature: 0.2,
            maxTokens: 64,
            reasoning: ReasoningControls(enabled: false, effort: ReasoningEffort.none)
        )
        let shouldStream = ChatNamingModelSupport.shouldRequestStreaming(
            providerConfig: providerConfig,
            modelID: modelID
        )

        let stream = try await adapter.sendMessage(
            messages: requestMessages,
            modelID: modelID,
            controls: titleControls,
            tools: [],
            streaming: shouldStream
        )

        var collected = ""
        for try await event in stream {
            switch event {
            case .contentDelta(.text(let text)):
                collected.append(text)
            case .error(let error):
                throw error
            default:
                continue
            }
        }

        let normalized = Self.normalizeTitle(collected, maxCharacters: maxCharacters)
        guard !normalized.isEmpty else {
            throw LLMError.decodingError(message: "Empty generated title.")
        }

        return normalized
    }

    static func renderContextText(_ messages: [Message]) -> String {
        var lines: [String] = ["<conversation>"]

        for message in messages {
            let role = message.role.rawValue
            let content = message.content.compactMap { part -> String? in
                switch part {
                case .text(let text):
                    let visibleText = ArtifactMarkupParser.visibleText(from: text)
                    return visibleText.trimmedNonEmpty
                case .quote(let quote):
                    return quote.quotedText.trimmedNonEmpty
                case .file(let file):
                    let fallback = AttachmentPromptRenderer.fallbackText(for: file)
                    return fallback.trimmedNonEmpty
                case .image:
                    return "[image]"
                case .thinking, .redactedThinking, .audio, .video:
                    return nil
                }
            }
            let merged = content.joined(separator: "\n")
            if !merged.isEmpty {
                lines.append("<\(role)>\(merged)</\(role)>")
            }
        }

        lines.append("</conversation>")

        // Only return a wrapped block if at least one role contributed content.
        guard lines.count > 2 else { return "" }
        return lines.joined(separator: "\n")
    }

    static func detectLanguageName(from messages: [Message]) -> String {
        let userText = messages
            .first(where: { $0.role == .user })?
            .content
            .compactMap { part -> String? in
                switch part {
                case .text(let text):
                    return ArtifactMarkupParser.visibleText(from: text).trimmedNonEmpty
                case .quote(let quote):
                    return quote.quotedText.trimmedNonEmpty
                default:
                    return nil
                }
            }
            .joined(separator: " ")

        let fallback = fallbackLanguageInstruction
        guard let userText, !userText.isEmpty else { return fallback }

        let detectionText = normalizedLanguageDetectionText(from: userText)
        guard hasEnoughLanguageDetectionEvidence(in: detectionText) else { return fallback }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(detectionText)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
            .sorted { lhs, rhs in lhs.value > rhs.value }
        guard let dominant = hypotheses.first else { return fallback }

        let runnerUpConfidence = hypotheses.dropFirst().first?.value ?? 0
        guard dominant.value >= minimumLanguageDetectionConfidence,
              dominant.value - runnerUpConfidence >= minimumLanguageDetectionConfidenceMargin else {
            return fallback
        }

        let englishLocale = Locale(identifier: "en_US_POSIX")
        if let name = englishLocale.localizedString(forLanguageCode: dominant.key.rawValue)?.trimmedNonEmpty {
            return name
        }
        return fallback
    }

    private static func normalizedLanguageDetectionText(from text: String) -> String {
        text.replacingOccurrences(of: #"(?s)```.*?```"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"`[^`\n]+`"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
    }

    private static func hasEnoughLanguageDetectionEvidence(in text: String) -> Bool {
        let letterCount = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letterCount >= minimumLanguageDetectionLetterCount else { return false }

        if containsCJKScript(in: text) {
            return true
        }

        let wordCount = text
            .split { !$0.isLetter }
            .filter { token in
                token.count >= 2 && !isLikelyTechnicalToken(token)
            }
            .count

        return wordCount >= minimumLanguageDetectionWordCount
    }

    private static func containsCJKScript(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private static func isLikelyTechnicalToken(_ token: Substring) -> Bool {
        let uppercaseCount = token.filter(\.isUppercase).count
        let lowercaseCount = token.filter(\.isLowercase).count

        if uppercaseCount > 1 {
            return true
        }

        if lowercaseCount > 0,
           token.dropFirst().contains(where: \.isUppercase) {
            return true
        }

        return false
    }

    static func normalizeTitle(_ raw: String, maxCharacters: Int = 24) -> String {
        var text = raw.trimmed

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
                text = String(text[text.index(after: colon)...]).trimmed
            } else {
                break
            }
        }

        text = text.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmed

        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters)).trimmed
        }

        return text
    }
}
