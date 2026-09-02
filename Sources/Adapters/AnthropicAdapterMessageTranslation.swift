import Foundation

// MARK: - Anthropic Message & Content Block Translation

extension AnthropicAdapter {

    func translateMessage(
        _ message: Message,
        supportsNativePDF: Bool,
        usesCodeExecutionTool: Bool,
        cacheControl: [String: Any]?,
        cacheStrategy: ContextCacheStrategy
    ) async throws -> [String: Any] {
        var content: [[String: Any]] = []

        func maybeApplyCache(to block: inout [String: Any]) {
            guard let cacheControl, message.role != .assistant else { return }
            switch cacheStrategy {
            case .systemOnly:
                return
            case .systemAndTools:
                block["cache_control"] = cacheControl
            case .prefixWindow:
                // Prefix-window uses top-level Anthropic automatic caching.
                return
            }
        }

        appendToolResultBlocks(from: message, to: &content, applyCache: maybeApplyCache)
        try await appendContentBlocks(
            from: message,
            supportsNativePDF: supportsNativePDF,
            usesCodeExecutionTool: usesCodeExecutionTool,
            to: &content,
            applyCache: maybeApplyCache
        )
        appendToolUseBlocks(from: message, to: &content)

        return [
            "role": message.role == .assistant ? "assistant" : "user",
            "content": content
        ]
    }

    private func appendToolResultBlocks(
        from message: Message,
        to content: inout [[String: Any]],
        applyCache: (inout [String: Any]) -> Void
    ) {
        guard let toolResults = message.toolResults else { return }
        for result in toolResults {
            let safeContent = result.content.trimmedNonEmpty == nil ? "<empty_content>" : result.content

            var block: [String: Any] = [
                "type": "tool_result",
                "tool_use_id": result.toolCallID,
                "content": safeContent,
                "is_error": result.isError
            ]
            applyCache(&block)
            content.append(block)
        }
    }

    /// Replays `message.content` in its stored order.
    ///
    /// Anthropic signs every `thinking` / `redacted_thinking` block against its position in
    /// the original response. Adaptive thinking interleaves reasoning with visible text and
    /// server-tool use, so one reply can be `[thinking, text, thinking, text]`, and the second
    /// block is only valid at that position. Hoisting thinking blocks to the front
    /// (`[thinking, thinking, text, text]`) makes the API reject the whole request with
    /// "`thinking` or `redacted_thinking` blocks in the latest assistant message cannot be
    /// modified" — for every assistant turn in the history, not only the latest one, and on
    /// every Claude model (verified live on Sonnet 5 and Fable 5.1 via `count_tokens`).
    /// Dropping the server-tool blocks Jin does not persist is tolerated; reordering is not.
    private func appendContentBlocks(
        from message: Message,
        supportsNativePDF: Bool,
        usesCodeExecutionTool: Bool,
        to content: inout [[String: Any]],
        applyCache: (inout [String: Any]) -> Void
    ) async throws {
        for part in message.content {
            switch part {
            case .thinking(let thinking):
                guard message.role == .assistant else { continue }
                appendThinkingBlock(thinking, to: &content)
            case .redactedThinking(let redacted):
                guard message.role == .assistant else { continue }
                appendRedactedThinkingBlock(redacted, to: &content)
            default:
                // Tool messages carry only `tool_result` blocks; their display text stays local.
                guard message.role != .tool else { continue }
                try await appendUserFacingBlock(
                    part,
                    supportsNativePDF: supportsNativePDF,
                    usesCodeExecutionTool: usesCodeExecutionTool,
                    to: &content,
                    applyCache: applyCache
                )
            }
        }
    }

    private func appendThinkingBlock(_ thinking: ThinkingBlock, to content: inout [[String: Any]]) {
        // Only send thinking blocks that originated from Anthropic.
        // Blocks from other providers (Gemini, OpenAI, etc.) have foreign signatures
        // or nil signatures that would cause a 400 error from Anthropic.
        // Blocks with provider == nil are from pre-tagging persisted data — skip them
        // since we cannot verify their origin.
        guard thinking.provider == providerConfig.type.rawValue,
              let signature = thinking.signature,
              !signature.isEmpty else {
            return
        }
        content.append([
            "type": "thinking",
            "thinking": thinking.text,
            "signature": signature
        ])
    }

    private func appendRedactedThinkingBlock(_ redacted: RedactedThinkingBlock, to content: inout [[String: Any]]) {
        guard redacted.provider == providerConfig.type.rawValue,
              !redacted.data.isEmpty else {
            return
        }
        content.append([
            "type": "redacted_thinking",
            "data": redacted.data
        ])
    }

    private func appendUserFacingBlock(
        _ part: ContentPart,
        supportsNativePDF: Bool,
        usesCodeExecutionTool: Bool,
        to content: inout [[String: Any]],
        applyCache: (inout [String: Any]) -> Void
    ) async throws {
        switch part {
        case .text(let text):
            var block: [String: Any] = ["type": "text", "text": text]
            applyCache(&block)
            content.append(block)
        case .quote(let quote):
            var block: [String: Any] = ["type": "text", "text": quote.quotedText]
            applyCache(&block)
            content.append(block)
        case .image(let image):
            if let imageBlock = try translateImageBlock(image) {
                content.append(imageBlock)
            }
        case .file(let file):
            try await translateFileBlock(
                file,
                supportsNativePDF: supportsNativePDF,
                usesCodeExecutionTool: usesCodeExecutionTool,
                to: &content,
                applyCache: applyCache
            )
        case .video(let video):
            var block: [String: Any] = [
                "type": "text",
                "text": unsupportedVideoInputNotice(video, providerName: "Anthropic", apiName: "Messages API")
            ]
            applyCache(&block)
            content.append(block)
        case .audio, .thinking, .redactedThinking:
            break
        }
    }

    private func translateImageBlock(_ image: ImageContent) throws -> [String: Any]? {
        let data: Data?
        if let existing = image.data {
            data = existing
        } else if let url = image.url, url.isFileURL {
            data = try resolveFileData(from: url)
        } else {
            data = nil
        }
        guard let data else { return nil }
        return [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": image.mimeType,
                "data": data.base64EncodedString()
            ]
        ]
    }

    private func translateFileBlock(
        _ file: FileContent,
        supportsNativePDF: Bool,
        usesCodeExecutionTool: Bool,
        to content: inout [[String: Any]],
        applyCache: (inout [String: Any]) -> Void
    ) async throws {
        let normalizedFileMIMEType = normalizedMIMEType(file.mimeType)
        let shouldUseHostedDocument: Bool
        if usesCodeExecutionTool {
            shouldUseHostedDocument = anthropicCodeExecutionUploadMIMETypes.contains(normalizedFileMIMEType)
        } else {
            shouldUseHostedDocument =
                anthropicHostedDocumentMIMETypes.contains(normalizedFileMIMEType) &&
                (normalizedFileMIMEType != "application/pdf" || supportsNativePDF)
        }

        if shouldUseHostedDocument, let hostedFile = try await uploadHostedAnthropicFile(file) {
            if usesCodeExecutionTool {
                content.append([
                    "type": "container_upload",
                    "file_id": hostedFile.id
                ])
                return
            } else {
                var block: [String: Any] = [
                    "type": "document",
                    "source": [
                        "type": "file",
                        "file_id": hostedFile.id
                    ]
                ]
                applyCache(&block)
                content.append(block)
                return
            }
        }

        if supportsNativePDF && normalizedFileMIMEType == "application/pdf" {
            let pdfData: Data?
            if let data = file.data {
                pdfData = data
            } else if let url = file.url, url.isFileURL {
                pdfData = try resolveFileData(from: url)
            } else {
                pdfData = nil
            }

            if let pdfData {
                var block: [String: Any] = [
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": pdfData.base64EncodedString()
                    ]
                ]
                applyCache(&block)
                content.append(block)
                return
            }
        }

        let text = AttachmentPromptRenderer.fallbackText(for: file)
        var block: [String: Any] = ["type": "text", "text": text]
        applyCache(&block)
        content.append(block)
    }

    private func uploadHostedAnthropicFile(_ file: FileContent) async throws -> HostedProviderFileReference? {
        do {
            return try await ProviderHostedFileStore.shared.uploadAnthropicFile(
                file: file,
                baseURL: baseURL,
                apiKey: apiKey,
                anthropicVersion: anthropicVersion,
                networkManager: networkManager
            )
        } catch {
            if shouldFallbackFromHostedFileUpload(error) {
                return nil
            }
            throw error
        }
    }

    private func appendToolUseBlocks(from message: Message, to content: inout [[String: Any]]) {
        guard message.role == .assistant, let toolCalls = message.toolCalls else { return }
        for call in toolCalls {
            let input = call.arguments.mapValues { $0.value }
            content.append([
                "type": "tool_use",
                "id": call.id,
                "name": call.name,
                "input": input
            ])
        }
    }
}
