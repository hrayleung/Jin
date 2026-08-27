import Foundation

/// Makora inference adapter (OpenAI-compatible Chat Completions on vLLM).
///
/// Docs / sources:
/// - https://www.makora.com — OpenAI-style drop-in; current model cards
/// - https://inference.makora.com/v1 — unified endpoint (`GET /models`, `POST /chat/completions`)
/// - Keys: https://inference.makora.com (`MAKORA_OPTIMIZE_TOKEN`)
///
/// Makora's vLLM deployment ignores official DeepSeek `thinking: { type }` and
/// several OpenAI reasoning envelopes. Request bodies are rewritten to vLLM-native
/// `chat_template_kwargs` / `include_reasoning` (see `MakoraRequestSupport`).
actor MakoraAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let canonicalID = MakoraModelSupport.canonicalModelID(for: modelID)
        let request = try buildRequest(
            messages: messages,
            modelID: canonicalID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        let stream = try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoningOrReasoningContent,
            networkManager: networkManager
        )

        guard !tools.isEmpty, MakoraModelSupport.needsClientSideToolCallRepair(canonicalID) else {
            return stream
        }
        return repairingToolCallStream(stream, modelID: canonicalID)
    }

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? ProviderType.makora.defaultBaseURL ?? MakoraModelSupport.unifiedBaseURL)
            .trimmed
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/v1") {
            return trimmed
        }

        if let url = URL(string: trimmed), url.path.isEmpty || url.path == "/" {
            return "\(trimmed)/v1"
        }

        return trimmed
    }

    private func repairingToolCallStream(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        modelID: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var bufferedText = ""
                var sawNativeToolCall = false
                do {
                    for try await event in stream {
                        switch event {
                        case .contentDelta(let part):
                            if case .text(let text) = part {
                                bufferedText += text
                            }
                            if sawNativeToolCall {
                                continuation.yield(event)
                            }
                        case .toolCallStart, .toolCallDelta, .toolCallEnd:
                            if !sawNativeToolCall, !bufferedText.isEmpty {
                                continuation.yield(.contentDelta(.text(bufferedText)))
                                bufferedText = ""
                            }
                            sawNativeToolCall = true
                            continuation.yield(event)
                        case .messageEnd(let usage):
                            if !sawNativeToolCall {
                                let parsed = MakoraToolCallRepair.parse(bufferedText, modelID: modelID)
                                if parsed.isEmpty {
                                    if !bufferedText.isEmpty {
                                        continuation.yield(.contentDelta(.text(bufferedText)))
                                    }
                                } else {
                                    let visible = MakoraToolCallRepair.textBeforeTools(bufferedText, modelID: modelID)
                                    if !visible.isEmpty {
                                        continuation.yield(.contentDelta(.text(visible)))
                                    }
                                    for call in MakoraToolCallRepair.toolCalls(from: parsed) {
                                        continuation.yield(.toolCallStart(call))
                                        continuation.yield(.toolCallEnd(call))
                                    }
                                }
                            } else if !bufferedText.isEmpty {
                                continuation.yield(.contentDelta(.text(bufferedText)))
                            }
                            continuation.yield(.messageEnd(usage: usage))
                        default:
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
