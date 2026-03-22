import Foundation

// MARK: - Text Splitting, Input Rendering, URL Extraction, Error Handling Utilities

extension CodexAppServerAdapter {

    // MARK: - Assistant Text Emission

    func emitAssistantText(
        _ text: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard !text.isEmpty else { return }
        ensureMessageStartIfNeeded(params: params, continuation: continuation, state: state)
        continuation.yield(.contentDelta(.text(text)))
        state.assistantTextBuffer.append(text)
        state.didEmitAssistantText = true
    }

    func emitAssistantTextSnapshot(
        _ snapshot: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard let delta = Self.assistantTextSuffix(fromSnapshot: snapshot, emitted: state.assistantTextBuffer) else {
            return
        }
        emitAssistantText(delta, params: params, continuation: continuation, state: state)
    }

    func ensureMessageStartIfNeeded(
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        state: CodexStreamState
    ) {
        guard !state.didEmitMessageStart else { return }
        let turnID = params.string(at: ["turnId"]) ?? params.string(at: ["turn", "id"]) ?? state.activeTurnID ?? UUID().uuidString
        state.activeTurnID = turnID
        continuation.yield(.messageStart(id: turnID))
        state.didEmitMessageStart = true
    }

    // MARK: - Input Rendering

    nonisolated static func makeTurnInput(from messages: [Message], resumeExistingThread: Bool) -> [Any] {
        let fallbackPrompt = makePrompt(from: messages)

        guard resumeExistingThread,
              let lastMessage = messages.last,
              lastMessage.role == .user else {
            return [makeCodexTextInput(fallbackPrompt)]
        }

        let imageInputs = lastMessage.content.compactMap { part -> [String: Any]? in
            guard case .image(let image) = part else { return nil }
            return Self.codexImageInputItem(from: image)
        }
        guard !imageInputs.isEmpty else {
            let latestUserText = renderUserTextForCodex(from: lastMessage.content)
            let trimmedUserText = latestUserText.trimmingCharacters(in: .whitespacesAndNewlines)
            return [makeCodexTextInput(trimmedUserText.isEmpty ? "Continue." : trimmedUserText)]
        }

        let latestUserText = renderUserTextForCodex(from: lastMessage.content)

        var inputs: [Any] = []
        let trimmedUserText = latestUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputs.append(makeCodexTextInput(trimmedUserText.isEmpty ? "Continue." : trimmedUserText))
        inputs.append(contentsOf: imageInputs)
        return inputs.isEmpty ? [makeCodexTextInput(fallbackPrompt)] : inputs
    }

    private nonisolated static func renderUserTextForCodex(from content: [ContentPart]) -> String {
        content.compactMap { part -> String? in
            switch part {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .thinking(let block):
                let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : "[Thinking] \(trimmed)"
            case .redactedThinking:
                return "[Thinking redacted]"
            case .image(let image):
                return Self.codexImageInputItem(from: image) == nil ? "[Image attachment]" : nil
            case .video(let video):
                if let url = video.url?.absoluteString {
                    return "[Video] \(url)"
                }
                return "[Video attachment]"
            case .file(let file):
                return "[File] \(file.filename)"
            case .audio:
                return "[Audio attachment]"
            }
        }.joined(separator: "\n")
    }

    nonisolated static func makeCodexTextInput(_ text: String) -> [String: Any] {
        [
            "type": "text",
            "text": text,
            "text_elements": [Any]()
        ]
    }

    private nonisolated static func makePrompt(from messages: [Message]) -> String {
        let rendered = messages
            .map { message in
                let role: String
                switch message.role {
                case .system:
                    role = "System"
                case .user:
                    role = "User"
                case .assistant:
                    role = "Assistant"
                case .tool:
                    role = "Tool"
                }

                let content = message.content.compactMap { part -> String? in
                    switch part {
                    case .text(let text):
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    case .thinking(let block):
                        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : "[Thinking] \(trimmed)"
                    case .redactedThinking:
                        return "[Thinking redacted]"
                    case .image(let image):
                        if let url = image.url?.absoluteString {
                            return "[Image] \(url)"
                        }
                        return "[Image attachment]"
                    case .video(let video):
                        if let url = video.url?.absoluteString {
                            return "[Video] \(url)"
                        }
                        return "[Video attachment]"
                    case .file(let file):
                        return "[File] \(file.filename)"
                    case .audio:
                        return "[Audio attachment]"
                    }
                }.joined(separator: "\n")

                if content.isEmpty {
                    return "\(role):"
                }
                return "\(role):\n\(content)"
            }
            .joined(separator: "\n\n")

        let trimmed = rendered.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Continue."
        }
        return trimmed
    }

    // MARK: - Image Input

    nonisolated static func codexImageInputItem(from image: ImageContent) -> [String: Any]? {
        if let url = image.url {
            if url.isFileURL {
                return [
                    "type": "localImage",
                    "path": url.path
                ]
            }
            return [
                "type": "image",
                "url": url.absoluteString
            ]
        }
        return nil
    }

    // MARK: - Usage Parsing

    func parseUsage(from dict: [String: JSONValue]?) -> Usage? {
        guard let dict else { return nil }

        let input = dict.int(at: ["inputTokens"]) ?? 0
        let output = dict.int(at: ["outputTokens"]) ?? 0
        let reasoning = dict.int(at: ["reasoningOutputTokens"])
        let cached = dict.int(at: ["cachedInputTokens"])

        return Usage(
            inputTokens: input,
            outputTokens: output,
            thinkingTokens: reasoning,
            cachedTokens: cached
        )
    }
}
