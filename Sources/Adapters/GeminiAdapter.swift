import Foundation

/// Gemini (AI Studio) provider adapter (Gemini API / Generative Language API).
///
/// This adapter targets Gemini 3 series models via `generateContent` + `streamGenerateContent?alt=sse`.
/// It supports:
/// - Streaming (SSE)
/// - Thinking summaries (thought parts) + thought signatures
/// - Function calling (tools) + tool results
/// - Vision + native PDF (inlineData) for Gemini 3
/// - Grounding with Google Search (`google_search` tool)
actor GeminiAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF, .imageGeneration, .videoGeneration]
    // Model ID sets are shared with VertexAIAdapter via GeminiModelConstants.

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
        if isVideoGenerationModel(modelID) {
            return try makeVideoGenerationStream(
                messages: messages,
                modelID: modelID,
                controls: controls
            )
        }

        let request = try await buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(GeminiGenerateContentResponse.self, from: data)

            // Handle prompt-level blocks explicitly (Gemini returns promptFeedback for blocked prompts).
            if response.promptFeedback?.blockReason != nil {
                throw LLMError.contentFiltered
            }

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: UUID().uuidString))

                let usage = response.toUsage()
                var codeExecutionState = GeminiModelConstants.GoogleCodeExecutionEventState()

                if let candidate = response.candidates?.first {
                    if isCandidateContentFiltered(candidate) {
                        continuation.yield(.error(.contentFiltered))
                        continuation.finish()
                        return
                    }

                    let parts = candidate.content?.parts ?? []
                    for event in GeminiModelConstants.events(from: parts, codeExecutionState: &codeExecutionState) {
                        continuation.yield(event)
                    }
                }

                let grounding = candidateGroundingMetadata(in: response.candidates) ?? response.groundingMetadata
                for event in searchActivities(from: grounding) {
                    continuation.yield(event)
                }

                continuation.yield(.messageEnd(usage: usage))
                continuation.finish()
            }
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var didStart = false
                    let messageID = UUID().uuidString
                    var pendingUsage: Usage?
                    var codeExecutionState = GeminiModelConstants.GoogleCodeExecutionEventState()

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            guard let jsonData = data.data(using: .utf8) else { continue }

                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            let chunk = try decoder.decode(GeminiGenerateContentResponse.self, from: jsonData)

                            if chunk.promptFeedback?.blockReason != nil {
                                continuation.yield(.error(.contentFiltered))
                                continuation.finish()
                                return
                            }

                            if !didStart {
                                didStart = true
                                continuation.yield(.messageStart(id: messageID))
                            }

                            if let usage = chunk.toUsage() {
                                pendingUsage = usage
                            }

                            if let candidate = chunk.candidates?.first {
                                if isCandidateContentFiltered(candidate) {
                                    continuation.yield(.error(.contentFiltered))
                                    continuation.finish()
                                    return
                                }

                                let parts = candidate.content?.parts ?? []
                                for streamEvent in GeminiModelConstants.events(from: parts, codeExecutionState: &codeExecutionState) {
                                    continuation.yield(streamEvent)
                                }
                            }

                            let grounding = candidateGroundingMetadata(in: chunk.candidates) ?? chunk.groundingMetadata
                            for streamEvent in searchActivities(from: grounding) {
                                continuation.yield(streamEvent)
                            }

                        case .done:
                            // Gemini SSE streams typically end by closing the connection (no [DONE]),
                            // but handle it anyway for compatibility.
                            break
                        }
                    }

                    if didStart {
                        continuation.yield(.messageEnd(usage: pendingUsage))
                    } else {
                        // No chunks were received at all — emit an error so callers
                        // don't silently succeed with an empty conversation.
                        continuation.yield(.messageStart(id: messageID))
                        continuation.yield(.error(.decodingError(message: "Gemini returned an empty response with no content.")))
                        continuation.yield(.messageEnd(usage: nil))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        GeminiRequestSupport.functionDeclarations(from: tools)
    }

    // MARK: - Private

    var baseURL: String {
        providerConfig.baseURL ?? ProviderType.gemini.defaultBaseURL ?? "https://generativelanguage.googleapis.com/v1beta"
    }

    func geminiHeaders(apiKey: String? = nil, accept: String? = nil, contentType: String? = nil) -> [String: String] {
        var headers: [String: String] = ["x-goog-api-key": apiKey ?? self.apiKey]
        if let accept {
            headers["Accept"] = accept
        }
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return headers
    }

    // Content translation and event parsing are in GeminiContentTranslation.swift

}

// Cached content: GeminiAdapter+CachedContent.swift
// Content translation and event parsing: GeminiContentTranslation.swift
// Model catalog: GeminiAdapter+ModelCatalog.swift
// Request construction: GeminiAdapter+RequestSupport.swift
// Video generation: GeminiVideoGeneration.swift
// DTOs: GeminiAdapterResponseTypes.swift
