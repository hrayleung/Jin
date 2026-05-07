import Foundation

struct ChatMessageRenderMetadata: Sendable {
    let preferredRenderMode: MessageRenderMode
    let isMemoryIntensiveAssistantContent: Bool
    let collapsedPreview: LightweightMessagePreview?
}

enum ChatMessageRenderMetadataBuilder {
    static func copyableText(from content: [RenderedContentPart], role: MessageRole) -> String {
        let textParts = content.compactMap { part -> String? in
            switch part {
            case .text(let text):
                let sourceText = role == .assistant ? ArtifactMarkupParser.visibleText(from: text) : text
                return sourceText.trimmedNonEmpty
            case .quote(let quote):
                guard let trimmed = quote.quotedText.trimmedNonEmpty else { return nil }
                return "“\(trimmed)”"
            default:
                return nil
            }
        }

        if !textParts.isEmpty {
            return textParts.joined(separator: "\n\n")
        }

        let fileParts = content.compactMap { part -> String? in
            guard case .file(let file) = part else { return nil }
            return file.filename.trimmedNonEmpty
        }

        return fileParts.joined(separator: "\n")
    }

    static func renderMetadata(
        role: MessageRole,
        content: [RenderedContentPart],
        renderedBlocks: [RenderedMessageBlock],
        copyText: String
    ) -> ChatMessageRenderMetadata {
        guard role == .assistant else {
            return ChatMessageRenderMetadata(
                preferredRenderMode: .fullWeb,
                isMemoryIntensiveAssistantContent: false,
                collapsedPreview: nil
            )
        }

        let containsArtifact = renderedBlocks.contains { block in
            if case .artifact = block { return true }
            return false
        }
        let visibleContent = renderedBlocks.compactMap { block -> RenderedContentPart? in
            guard case .content(_, let part) = block else { return nil }
            return part
        }
        let combinedText = assistantVisibleText(from: content)
        let hasSingleTextPartOnly = renderedBlocks.count == 1
            && visibleContent.count == 1
            && visibleContent.allSatisfy(isTextPart)
            && !containsArtifact
        let previewSourceText = collapsedPreviewSourceText(copyText: copyText, renderedBlocks: renderedBlocks)
        let lineCount = max(1, previewSourceText.components(separatedBy: .newlines).count)
        let containsCode = containsLikelyCode(in: combinedText)
        let containsRichMarkdown = containsArtifact || containsLikelyRichMarkdown(in: combinedText)
        let isMemoryIntensive = containsCode || copyText.count > 1_800 || lineCount > 18 || containsArtifact

        return ChatMessageRenderMetadata(
            preferredRenderMode: hasSingleTextPartOnly && !containsRichMarkdown ? .nativeText : .fullWeb,
            isMemoryIntensiveAssistantContent: isMemoryIntensive,
            collapsedPreview: isMemoryIntensive
                ? makeCollapsedPreview(from: previewSourceText, containsCode: containsCode, lineCount: lineCount)
                : nil
        )
    }

    private static func assistantVisibleText(from content: [RenderedContentPart]) -> String {
        content.compactMap { part -> String? in
            switch part {
            case .text(let text):
                return ArtifactMarkupParser.visibleText(from: text)
            case .quote(let quote):
                return quote.quotedText
            default:
                return nil
            }
        }
        .joined(separator: "\n\n")
    }

    private static func isTextPart(_ part: RenderedContentPart) -> Bool {
        switch part {
        case .text, .quote:
            return true
        default:
            return false
        }
    }

    private static func makeCollapsedPreview(
        from text: String,
        containsCode: Bool,
        lineCount: Int
    ) -> LightweightMessagePreview? {
        let headlineLimit = 120
        let bodyLimit = 240
        var headline: String?
        var body = ""

        for rawLine in text.components(separatedBy: .newlines) {
            guard let trimmed = rawLine.trimmedNonEmpty else { continue }

            if headline == nil {
                headline = String(trimmed.prefix(headlineLimit))
                continue
            }

            guard body.count < bodyLimit else { break }
            let separator = body.isEmpty ? "" : " "
            let remainingBudget = bodyLimit - body.count - separator.count
            guard remainingBudget > 0 else { break }
            body += separator + String(trimmed.prefix(remainingBudget))
        }

        guard let headline else { return nil }
        return LightweightMessagePreview(headline: headline, body: body, lineCount: lineCount, containsCode: containsCode)
    }

    private static func collapsedPreviewSourceText(
        copyText: String,
        renderedBlocks: [RenderedMessageBlock]
    ) -> String {
        guard copyText.trimmedNonEmpty == nil else { return copyText }

        return renderedBlocks.compactMap { block -> String? in
            guard case .artifact(let artifact) = block else { return nil }
            return "\(artifact.title)\n\(artifact.contentType.displayName) Artifact"
        }
        .joined(separator: "\n\n")
    }

    private static func containsLikelyCode(in text: String) -> Bool {
        if text.contains("```") { return true }
        let indentedLineCount = text.components(separatedBy: .newlines).filter { line in
            line.hasPrefix("    ") || line.hasPrefix("\t")
        }.count
        return indentedLineCount >= 2
    }

    private static func containsLikelyRichMarkdown(in text: String) -> Bool {
        if text.contains("```") || text.contains("|") || text.contains("`") { return true }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#")
                || trimmed.hasPrefix("- ")
                || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("> ")
                || trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}
