import Foundation

extension ChatMessagePreparationSupport {
    static func resolvedSystemPrompt(conversationSystemPrompt: String?, assistant: AssistantEntity?) -> String? {
        let conversationPrompt = conversationSystemPrompt?.trimmedNonEmpty
        let assistantPrompt = assistant?.systemInstruction.trimmedNonEmpty
        let replyLanguage = assistant?.replyLanguage?.trimmedNonEmpty

        var prompt = conversationPrompt ?? assistantPrompt

        if let replyLanguage {
            if let existingPrompt = prompt {
                prompt = "\(existingPrompt)\n\nAlways reply in \(replyLanguage)."
            } else {
                prompt = "Always reply in \(replyLanguage)."
            }
        }

        return prompt?.trimmedNonEmpty
    }

    static func providerType(forProviderID providerID: String, providers: [ProviderConfigEntity]) -> ProviderType? {
        if let provider = providers.first(where: { $0.id == providerID }),
           let resolvedType = ProviderType(rawValue: provider.typeRaw) {
            return resolvedType
        }
        return ProviderType(rawValue: providerID)
    }

    static func hasTextualPrompt(messageText: String, quoteContents: [QuoteContent]) -> Bool {
        messageText.trimmedNonEmpty != nil
            || quoteContents.contains { $0.quotedText.trimmedNonEmpty != nil }
    }

    static func resolvedRemoteVideoInputURL(from raw: String, supportsExplicitRemoteVideoURLInput: Bool) throws -> URL? {
        guard supportsExplicitRemoteVideoURLInput else { return nil }
        guard !raw.isEmpty else { return nil }

        guard let url = URL(string: raw),
              !url.isFileURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LLMError.invalidRequest(message: "Video URL must be a valid http(s) link.")
        }

        return url
    }

    static func inferredVideoMIMEType(from url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "mpeg", "mpg": return "video/mpeg"
        case "wmv": return "video/x-ms-wmv"
        case "flv": return "video/x-flv"
        case "3gp", "3gpp": return "video/3gpp"
        default: return "video/mp4"
        }
    }

    static func makeConversationTitle(from userText: String) -> String {
        let firstLine = userText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard let trimmed = firstLine.trimmedNonEmpty else { return "New Chat" }
        return String(trimmed.prefix(48))
    }

    static func fallbackTitleFromMessage(_ message: Message) -> String {
        let text = message.content.compactMap { part -> String? in
            switch part {
            case .text(let value):
                return value.trimmedNonEmpty
            case .quote(let quote):
                return quote.quotedText.trimmedNonEmpty
            case .file(let file):
                let base = (file.filename as NSString).deletingPathExtension
                return base.trimmedNonEmpty
            case .image:
                return "Image"
            case .thinking, .redactedThinking, .audio, .video:
                return nil
            }
        }.first

        guard let text else { return "New Chat" }
        return makeConversationTitle(from: text)
    }
}
