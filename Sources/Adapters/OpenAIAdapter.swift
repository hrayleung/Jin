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

    private func translateInput(
        _ messages: [Message],
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .tool:
                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": sanitizedToolOutput(result.content, toolName: result.toolName)
                        ])
                    }
                }

            case .system, .user, .assistant:
                if let translated = try await translateMessage(
                    message,
                    supportsNativeFileInput: supportsNativeFileInput,
                    allowNativePDF: allowNativePDF
                ) {
                    items.append(translated)
                }

                if message.role == .assistant, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    items.append(contentsOf: translateFunctionCalls(toolCalls))
                }

                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": sanitizedToolOutput(result.content, toolName: result.toolName)
                        ])
                    }
                }
            }
        }

        return items
    }

    private func translateMessage(
        _ message: Message,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) async throws -> [String: Any]? {
        var content: [[String: Any]] = []
        for part in message.content {
            if let translated = try await translateContentPart(
                part,
                role: message.role,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            ) {
                content.append(translated)
            }
        }

        guard !content.isEmpty else { return nil }

        return [
            "role": message.role.rawValue,
            "content": content
        ]
    }

    private func translateFunctionCalls(_ calls: [ToolCall]) -> [[String: Any]] {
        calls.map { call in
            [
                "type": "function_call",
                "call_id": call.id,
                "name": call.name,
                "arguments": encodeJSONObject(call.arguments)
            ]
        }
    }

    private func sanitizedToolOutput(_ raw: String, toolName: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        if let toolName, !toolName.isEmpty {
            return "Tool \(toolName) returned no output"
        }
        return "Tool returned no output"
    }

    private func translateContentPart(
        _ part: ContentPart,
        role: MessageRole,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) async throws -> [String: Any]? {
        switch part {
        case .text(let text):
            // OpenAI Responses API: assistant uses output_text, others use input_text
            let textType = (role == .assistant) ? "output_text" : "input_text"
            return [
                "type": textType,
                "text": text
            ]

        case .image(let image):
            if let data = image.data {
                return [
                    "type": "input_image",
                    "image_url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"
                ]
            }
            if let url = image.url {
                if url.isFileURL {
                    let data = try resolveFileData(from: url)
                    return [
                        "type": "input_image",
                        "image_url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"
                    ]
                }
                return [
                    "type": "input_image",
                    "image_url": url.absoluteString
                ]
            }
            return nil

        case .file(let file):
            let normalizedFileMIMEType = normalizedMIMEType(file.mimeType)
            let shouldAllowNativeFileUpload =
                supportsNativeFileInput &&
                openAISupportedFileMIMETypes.contains(normalizedFileMIMEType) &&
                (normalizedFileMIMEType != "application/pdf" || allowNativePDF)

            if shouldAllowNativeFileUpload {
                // Remote URL: use file_url directly (Responses API supports this)
                if let url = file.url, !url.isFileURL {
                    return [
                        "type": "input_file",
                        "file_url": url.absoluteString
                    ]
                }

                if let hostedFile = try await uploadHostedOpenAIFile(file) {
                    return [
                        "type": "input_file",
                        "file_id": hostedFile.id
                    ]
                }

                // Load data from file URL or use existing data
                let fileData: Data?
                if let data = file.data {
                    fileData = data
                } else if let url = file.url, url.isFileURL {
                    fileData = try resolveFileData(from: url)
                } else {
                    fileData = nil
                }

                if let fileData {
                    return [
                        "type": "input_file",
                        "filename": file.filename,
                        "file_data": "data:\(normalizedFileMIMEType);base64,\(fileData.base64EncodedString())"
                    ]
                }
            }

            // Fallback to text extraction for unsupported types or models
            let textType = (role == .assistant) ? "output_text" : "input_text"
            let text = AttachmentPromptRenderer.fallbackText(for: file)
            return [
                "type": textType,
                "text": text
            ]

        case .video(let video):
            let textType = (role == .assistant) ? "output_text" : "input_text"
            return [
                "type": textType,
                "text": unsupportedVideoInputNotice(video, providerName: "OpenAI")
            ]

        case .audio(let audio):
            guard role == .user else { return nil }
            return try openAIInputAudioPart(audio)

        case .thinking, .redactedThinking:
            return nil
        }
    }

    private func uploadHostedOpenAIFile(_ file: FileContent) async throws -> HostedProviderFileReference? {
        do {
            return try await ProviderHostedFileStore.shared.uploadOpenAIFile(
                file: file,
                baseURL: baseURL,
                apiKey: apiKey,
                networkManager: networkManager
            )
        } catch {
            if shouldFallbackFromHostedFileUpload(error) {
                return nil
            }
            throw error
        }
    }

    private func openAIInputAudioPart(_ audio: AudioContent) throws -> [String: Any]? {
        let payloadData: Data?
        if let data = audio.data {
            payloadData = data
        } else if let url = audio.url, url.isFileURL {
            payloadData = try resolveFileData(from: url)
        } else {
            payloadData = nil
        }

        guard let payloadData, let format = openAIInputAudioFormat(mimeType: audio.mimeType) else {
            return nil
        }

        return [
            "type": "input_audio",
            "input_audio": [
                "data": payloadData.base64EncodedString(),
                "format": format
            ]
        ]
    }

    private func openAIInputAudioFormat(mimeType: String) -> String? {
        let lower = mimeType.lowercased()
        if lower == "audio/wav" || lower == "audio/x-wav" {
            return "wav"
        }
        if lower == "audio/mpeg" || lower == "audio/mp3" {
            return "mp3"
        }
        return nil
    }

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "name": tool.name,
            "description": tool.description,
            "parameters": [
                "type": tool.parameters.type,
                "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                "required": tool.parameters.required
            ]
        ]
    }

    private func parseSSEEvent(
        type: String,
        data: String,
        functionCallsByItemID: inout [String: ResponsesAPIFunctionCallState],
        codeInterpreterState: inout OpenAICodeInterpreterState
    ) throws -> StreamEvent? {
        guard let jsonData = data.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        switch type {
        case "response.created":
            let event = try decoder.decode(ResponsesAPICreatedEvent.self, from: jsonData)
            return .messageStart(id: event.response.id)

        case "response.output_text.delta":
            let event = try decoder.decode(ResponsesAPIOutputTextDeltaEvent.self, from: jsonData)
            return .contentDelta(.text(event.delta))

        case "response.reasoning_text.delta":
            let event = try decoder.decode(ResponsesAPIReasoningTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.reasoning_summary_text.delta":
            let event = try decoder.decode(ResponsesAPIReasoningSummaryTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.output_item.added":
            let event = try decoder.decode(ResponsesAPIOutputItemAddedEvent.self, from: jsonData)
            if event.item.type == "function_call" {
                guard let itemID = event.item.id,
                      let callID = event.item.callId,
                      let name = event.item.name else {
                    return nil
                }

                functionCallsByItemID[itemID] = ResponsesAPIFunctionCallState(callID: callID, name: name)
                return .toolCallStart(ToolCall(id: callID, name: name, arguments: [:]))
            }

            if event.item.type == "code_interpreter_call",
               let itemID = event.item.id {
                codeInterpreterState.currentItemID = itemID
                codeInterpreterState.codeBuffer = ""
                return .codeExecutionActivity(CodeExecutionActivity(
                    id: itemID,
                    status: .inProgress
                ))
            }

            if event.item.type == "web_search_call",
               let activity = searchActivityFromOutputItem(
                event.item,
                outputIndex: event.outputIndex,
                sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            return nil

        case "response.output_item.done":
            let event = try decoder.decode(ResponsesAPIOutputItemDoneEvent.self, from: jsonData)
            if event.item.type == "code_interpreter_call" {
                let activity = parseCodeInterpreterOutputItem(event.item, state: &codeInterpreterState)
                if let activity {
                    return .codeExecutionActivity(activity)
                }
                return nil
            }
            if event.item.type == "web_search_call",
               let activity = searchActivityFromOutputItem(
                event.item,
                outputIndex: event.outputIndex,
                sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            if event.item.type == "message",
               let activity = citationSearchActivityFromMessageItem(
                event.item,
                outputIndex: event.outputIndex,
                sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            return nil

        case "response.function_call_arguments.delta":
            let event = try decoder.decode(ResponsesAPIFunctionCallArgumentsDeltaEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }

            functionCallsByItemID[event.itemId]?.argumentsBuffer += event.delta
            return .toolCallDelta(id: state.callID, argumentsDelta: event.delta)

        case "response.function_call_arguments.done":
            let event = try decoder.decode(ResponsesAPIFunctionCallArgumentsDoneEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }
            functionCallsByItemID.removeValue(forKey: event.itemId)

            let args = parseJSONObject(event.arguments)
            return .toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args))

        case "response.web_search_call.in_progress",
             "response.web_search_call.searching",
             "response.web_search_call.completed",
             "response.web_search_call.failed":
            let event = try decoder.decode(ResponsesAPIWebSearchCallStatusEvent.self, from: jsonData)
            return .searchActivity(
                SearchActivity(
                    id: event.itemId,
                    type: "web_search_call",
                    status: searchStatus(fromEventType: type),
                    arguments: [:],
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
                )
            )

        case "response.code_interpreter_call.in_progress":
            let event = try decoder.decode(ResponsesAPICodeInterpreterStatusEvent.self, from: jsonData)
            codeInterpreterState.currentItemID = event.itemId
            codeInterpreterState.codeBuffer = ""
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .inProgress
            ))

        case "response.code_interpreter_call_code.delta":
            let event = try decoder.decode(ResponsesAPICodeInterpreterCodeDeltaEvent.self, from: jsonData)
            codeInterpreterState.codeBuffer += event.delta
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .writingCode,
                code: codeInterpreterState.codeBuffer
            ))

        case "response.code_interpreter_call_code.done":
            let event = try decoder.decode(ResponsesAPICodeInterpreterCodeDoneEvent.self, from: jsonData)
            codeInterpreterState.codeBuffer = event.code ?? codeInterpreterState.codeBuffer
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .writingCode,
                code: codeInterpreterState.codeBuffer
            ))

        case "response.code_interpreter_call.interpreting":
            let event = try decoder.decode(ResponsesAPICodeInterpreterStatusEvent.self, from: jsonData)
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .interpreting,
                code: codeInterpreterState.codeBuffer
            ))

        case "response.code_interpreter_call.completed":
            let event = try decoder.decode(ResponsesAPICodeInterpreterStatusEvent.self, from: jsonData)
            codeInterpreterState.currentItemID = nil
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .completed,
                code: codeInterpreterState.codeBuffer
            ))

        case "response.completed":
            let event = try decoder.decode(ResponsesAPICompletedEvent.self, from: jsonData)
            return .messageEnd(usage: event.response.toUsage())

        case "response.failed":
            if let errorEvent = try? decoder.decode(ResponsesAPIFailedEvent.self, from: jsonData),
               let message = errorEvent.response.error?.message {
                return .error(.providerError(code: errorEvent.response.error?.code ?? "response_failed", message: message))
            }
            return .error(.providerError(code: "response_failed", message: data))

        default:
            return nil
        }
    }

    private func searchActivityFromOutputItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        outputIndex: Int?,
        sequenceNumber: Int?
    ) -> SearchActivity? {
        guard let id = item.id else { return nil }
        let actionType = item.action?.type ?? "web_search_call"
        return SearchActivity(
            id: id,
            type: actionType,
            status: searchStatus(from: item.status),
            arguments: ResponsesAPIResponse.searchActivityArguments(from: item.action),
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }

    private func citationSearchActivityFromMessageItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        outputIndex: Int?,
        sequenceNumber: Int?
    ) -> SearchActivity? {
        let arguments = ResponsesAPIResponse.citationArguments(from: item.content)
        guard !arguments.isEmpty else { return nil }

        let baseID = item.id ?? "message_\(outputIndex ?? -1)"
        return SearchActivity(
            id: "\(baseID):citations",
            type: "url_citation",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }

    private func searchStatus(from raw: String?) -> SearchActivityStatus {
        guard let raw, !raw.isEmpty else { return .inProgress }
        return SearchActivityStatus(rawValue: raw)
    }

    private func searchStatus(fromEventType eventType: String) -> SearchActivityStatus {
        if eventType.hasSuffix(".completed") {
            return .completed
        }
        if eventType.hasSuffix(".searching") {
            return .searching
        }
        if eventType.hasSuffix(".failed") {
            return .failed
        }
        return .inProgress
    }

    // MARK: - Code Interpreter Helpers

    private func isCodeInterpreterDoneItem(_ data: String) -> Bool {
        data.contains("\"code_interpreter_call\"")
    }

    private func parseCodeInterpreterOutputItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        state: inout OpenAICodeInterpreterState
    ) -> CodeExecutionActivity? {
        guard let id = item.id else { return nil }

        var stdout: String?
        var outputImages: [CodeExecutionOutputImage]?

        if let outputs = item.outputs {
            var logLines: [String] = []
            var images: [CodeExecutionOutputImage] = []

            for output in outputs {
                if output.type == "logs", let logs = output.logs {
                    logLines.append(logs)
                } else if output.type == "image" {
                    if let url = output.url ?? output.imageUrl {
                        images.append(CodeExecutionOutputImage(url: url))
                    }
                }
            }

            if !logLines.isEmpty {
                stdout = logLines.joined(separator: "\n")
            }
            if !images.isEmpty {
                outputImages = images
            }
        }

        let status: CodeExecutionStatus
        switch item.status {
        case "completed":
            status = .completed
        case "failed":
            status = .failed
        case "incomplete":
            status = .incomplete
        case "interpreting":
            status = .interpreting
        default:
            status = .completed
        }

        state.currentItemID = nil

        return CodeExecutionActivity(
            id: id,
            status: status,
            code: item.code ?? state.codeBuffer,
            stdout: stdout,
            outputImages: outputImages,
            containerID: item.containerId
        )
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
