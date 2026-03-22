import Collections
import Foundation

/// OpenAI provider adapter (Responses API)
actor OpenAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .imageGeneration]

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
        if isImageGenerationModel(modelID) {
            return try makeImageGenerationStream(messages: messages, modelID: modelID, controls: controls)
        }

        // OpenAI currently documents audio input support primarily on Chat Completions.
        // Route audio-bearing requests through the OpenAI-compatible Chat Completions path.
        if shouldRouteToChatCompletionsForAudio(messages: messages, modelID: modelID) {
            let chatCompletionsAdapter = OpenAICompatibleAdapter(
                providerConfig: providerConfig,
                apiKey: apiKey,
                networkManager: networkManager
            )
            return try await chatCompletionsAdapter.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: streaming
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
            let response = try decoder.decode(ResponsesAPIResponse.self, from: data)

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: response.id))

                for activity in response.searchActivities {
                    continuation.yield(.searchActivity(activity))
                }

                for text in response.outputTextParts {
                    continuation.yield(.contentDelta(.text(text)))
                }

                if let notice = response.incompleteNoticeMarkdown {
                    continuation.yield(.contentDelta(.text(notice)))
                }

                continuation.yield(.messageEnd(usage: response.toUsage()))
                continuation.finish()
            }
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        let streamDecoder = JSONDecoder()
        streamDecoder.keyDecodingStrategy = .convertFromSnakeCase

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var functionCallsByItemID: [String: ResponsesAPIFunctionCallState] = [:]
                    var codeInterpreterState = OpenAICodeInterpreterState()
                    var didEmitTerminalMessageEnd = false

                    for try await event in sseStream {
                        switch event {
                        case .event(let type, let data):
                            if type == "response.incomplete",
                               let jsonData = data.data(using: .utf8),
                               let incomplete = try? streamDecoder.decode(ResponsesAPIIncompleteEvent.self, from: jsonData) {
                                if let notice = incomplete.response.incompleteNoticeMarkdown {
                                    continuation.yield(.contentDelta(.text(notice)))
                                }
                                continuation.yield(.messageEnd(usage: incomplete.response.toUsage()))
                                didEmitTerminalMessageEnd = true
                                continue
                            }

                            do {
                                if let streamEvent = try parseSSEEvent(
                                    type: type,
                                    data: data,
                                    functionCallsByItemID: &functionCallsByItemID,
                                    codeInterpreterState: &codeInterpreterState
                                ) {
                                    if case .messageEnd = streamEvent {
                                        didEmitTerminalMessageEnd = true
                                    }
                                    continuation.yield(streamEvent)
                                }
                            } catch is DecodingError {
                                // Be resilient to provider-side schema drift in individual events.
                                // Skip malformed events instead of aborting the whole response stream.
                                continue
                            }
                        case .done:
                            if !didEmitTerminalMessageEnd {
                                continuation.yield(.messageEnd(usage: nil))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(
            url: try validatedURL("\(baseURL)/models"),
            apiKey: apiKey,
            accept: nil,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return response.data.map { model in
            var info = ModelCatalog.modelInfo(for: model.id, provider: .openai, name: model.id)
            let contextWindow = model.contextWindow.flatMap { $0 > 0 ? $0 : nil }
            let maxOutputTokens = model.maxTokens.flatMap { $0 > 0 ? $0 : nil }
            if let contextWindow {
                info = ModelInfo(
                    id: info.id,
                    name: info.name,
                    capabilities: info.capabilities,
                    contextWindow: contextWindow,
                    maxOutputTokens: maxOutputTokens ?? info.maxOutputTokens,
                    reasoningConfig: info.reasoningConfig,
                    overrides: info.overrides,
                    catalogMetadata: info.catalogMetadata,
                    isEnabled: info.isEnabled
                )
            } else if let maxOutputTokens {
                info = ModelInfo(
                    id: info.id,
                    name: info.name,
                    capabilities: info.capabilities,
                    contextWindow: info.contextWindow,
                    maxOutputTokens: maxOutputTokens,
                    reasoningConfig: info.reasoningConfig,
                    overrides: info.overrides,
                    catalogMetadata: info.catalogMetadata,
                    isEnabled: info.isEnabled
                )
            }
            return info
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    var baseURL: String {
        providerConfig.baseURL ?? "https://api.openai.com/v1"
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> URLRequest {
        let supportsNativeFileInput = supportsNativePDF(modelID)
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let codeExecutionEnabled = controls.codeExecution?.enabled == true && supportsCodeExecution(modelID)

        var body: [String: Any] = [
            "model": modelID,
            "input": try await translateInput(
                messages,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            ),
            "stream": streaming
        ]

        if controls.contextCache?.mode != .off {
            if let cacheKey = normalizedTrimmedString(controls.contextCache?.cacheKey) {
                body["prompt_cache_key"] = cacheKey
            }
            if let retention = controls.contextCache?.ttl?.providerTTLString {
                body["prompt_cache_retention"] = retention
            }
        }

        let reasoningEffort = (controls.reasoning?.enabled == true) ? controls.reasoning?.effort : nil
        let reasoningEnabled = (reasoningEffort ?? .none) != .none
        let supportsSamplingParameters = supportsOpenAIResponsesSamplingParameters(
            modelID: modelID,
            reasoningEnabled: reasoningEnabled
        )

        // Responses API sampling controls are limited for GPT-5 family models.
        if supportsSamplingParameters {
            if let temperature = controls.temperature {
                body["temperature"] = temperature
            }
            if let topP = controls.topP {
                body["top_p"] = topP
            }
        }

        if let maxTokens = controls.maxTokens {
            body["max_output_tokens"] = maxTokens
        }

        if let serviceTier = resolvedOpenAIServiceTier(from: controls) {
            body["service_tier"] = serviceTier
        }

        if reasoningEnabled, let effort = reasoningEffort {
            var reasoningDict: [String: Any] = [
                "effort": mapReasoningEffort(effort, modelID: modelID)
            ]

            // Add summary control if specified
            if let summary = controls.reasoning?.summary {
                reasoningDict["summary"] = summary.rawValue
            }

            body["reasoning"] = reasoningDict
        }

        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
            var webSearchTool: [String: Any] = ["type": "web_search"]
            if let contextSize = controls.webSearch?.contextSize {
                webSearchTool["search_context_size"] = contextSize.rawValue
            }
            toolObjects.append(webSearchTool)
        }

        if codeExecutionEnabled {
            toolObjects.append(buildCodeInterpreterTool(from: controls.codeExecution))
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            toolObjects.append(contentsOf: functionTools)
        }

        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        for (key, value) in controls.providerSpecific {
            guard key != "prompt_cache_min_tokens", key != "service_tier" else {
                continue
            }
            if !supportsSamplingParameters, key == "temperature" || key == "top_p" {
                continue
            }
            body[key] = value.value
        }

        // Ask Responses API to include source URLs/titles for web_search_call actions when possible.
        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
            body["include"] = mergedIncludeFields(body["include"], adding: "web_search_call.action.sources")
        }

        // Include code interpreter outputs (logs, images) in the response.
        if codeExecutionEnabled {
            body["include"] = mergedIncludeFields(body["include"], adding: "code_interpreter_call.outputs")
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/responses"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            includeUserAgent: false
        )
    }

    private func mergedIncludeFields(_ existing: Any?, adding field: String) -> [String] {
        let existingStrings: [String]
        if let strings = existing as? [String] {
            existingStrings = strings
        } else if let anyArray = existing as? [Any] {
            existingStrings = anyArray.compactMap { $0 as? String }
        } else {
            existingStrings = []
        }

        var out = OrderedSet<String>()
        for raw in existingStrings + [field] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            out.append(trimmed)
        }
        return Array(out)
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort, modelID: String) -> String {
        let normalized = ModelCapabilityRegistry.normalizedReasoningEffort(
            effort,
            for: providerConfig.type,
            modelID: modelID
        )

        switch normalized {
        case .none:
            return "none"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        }
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        JinModelSupport.supportsNativePDF(providerType: .openai, modelID: modelID)
    }

    private func supportsCodeExecution(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: modelID)
    }

    private func buildCodeInterpreterTool(from controls: CodeExecutionControls?) -> [String: Any] {
        var codeInterpreterTool: [String: Any] = ["type": "code_interpreter"]
        let openAISettings = controls?.openAI?.normalized()

        if let existingContainerID = openAISettings?.normalizedExistingContainerID {
            codeInterpreterTool["container"] = existingContainerID
            return codeInterpreterTool
        }

        let containerConfig = openAISettings?.container?.normalized()
        var container: [String: Any] = ["type": containerConfig?.normalizedType ?? "auto"]

        if let memoryLimit = containerConfig?.normalizedMemoryLimit {
            container["memory_limit"] = memoryLimit
        }
        if let fileIDs = containerConfig?.normalizedFileIDs, !fileIDs.isEmpty {
            container["file_ids"] = fileIDs
        }

        codeInterpreterTool["container"] = container
        return codeInterpreterTool
    }

    // Shared MIME type set defined in AdapterUtilities.swift

    private func supportsWebSearch(_ modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    private func supportsAudioInputModelID(_ lowerModelID: String) -> Bool {
        isOpenAIAudioInputModelID(lowerModelID)
    }

    private func shouldRouteToChatCompletionsForAudio(messages: [Message], modelID: String) -> Bool {
        guard supportsAudioInputModelID(modelID.lowercased()) else {
            return false
        }

        for message in messages where message.role != .tool {
            if message.content.contains(where: { part in
                if case .audio = part { return true }
                return false
            }) {
                return true
            }
        }

        return false
    }
}

// MARK: - Models Response

private struct ModelsResponse: Codable {
    let data: [ModelData]
}

private struct ModelData: Codable {
    let id: String
    let contextWindow: Int?
    let maxTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case contextWindow = "context_window"
        case maxTokens = "max_tokens"
    }
}
