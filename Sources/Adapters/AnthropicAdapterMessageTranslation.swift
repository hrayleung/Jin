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
        appendThinkingBlocks(from: message, to: &content)
        try await appendUserFacingBlocks(
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
            let trimmed = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeContent = trimmed.isEmpty ? "<empty_content>" : result.content

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

    private func appendThinkingBlocks(from message: Message, to content: inout [[String: Any]]) {
        guard message.role == .assistant else { return }
        for part in message.content {
            switch part {
            case .thinking(let thinking):
                // Only send thinking blocks that originated from Anthropic.
                // Blocks from other providers (Gemini, OpenAI, etc.) have foreign signatures
                // or nil signatures that would cause a 400 error from Anthropic.
                // Blocks with provider == nil are from pre-tagging persisted data — skip them
                // since we cannot verify their origin.
                guard thinking.provider == ProviderType.anthropic.rawValue,
                      let signature = thinking.signature,
                      !signature.isEmpty else {
                    continue
                }
                content.append([
                    "type": "thinking",
                    "thinking": thinking.text,
                    "signature": signature
                ])
            case .redactedThinking(let redacted):
                guard redacted.provider == ProviderType.anthropic.rawValue,
                      !redacted.data.isEmpty else {
                    continue
                }
                content.append([
                    "type": "redacted_thinking",
                    "data": redacted.data
                ])
            default:
                break
            }
        }
    }

    private func appendUserFacingBlocks(
        from message: Message,
        supportsNativePDF: Bool,
        usesCodeExecutionTool: Bool,
        to content: inout [[String: Any]],
        applyCache: (inout [String: Any]) -> Void
    ) async throws {
        guard message.role != .tool else { return }
        for part in message.content {
            switch part {
            case .text(let text):
                var block: [String: Any] = ["type": "text", "text": text]
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
            default:
                break
            }
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
