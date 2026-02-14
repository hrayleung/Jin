import Foundation

/// xAI provider adapter.
///
/// - Chat models use the Responses API (`/responses`).
/// - Image models use `/images/generations` + `/images/edits`.
actor XAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .imageGeneration]

    private let networkManager: NetworkManager
    private let apiKey: String

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

        return try await sendResponsesConversation(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await networkManager.sendRequest(request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ModelsResponse.self, from: data)

        return response.data
            .filter { !isUnsupportedVideoGenerationModel($0) }
            .map { model in
                let caps = inferCapabilities(for: model)
                return ModelInfo(
                    id: model.id,
                    name: model.id,
                    capabilities: caps,
                    contextWindow: model.contextWindow ?? 128000,
                    reasoningConfig: nil
                )
            }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        providerConfig.baseURL ?? "https://api.x.ai/v1"
    }

    // MARK: - Chat (Responses API)

    private func sendResponsesConversation(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let request = try buildResponsesRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let response = try JSONDecoder().decode(ResponsesAPIResponse.self, from: data)

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: response.id))

                for text in response.outputTextParts {
                    continuation.yield(.contentDelta(.text(text)))
                }

                continuation.yield(.messageEnd(usage: response.toUsage()))
                continuation.finish()
            }
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var functionCallsByItemID: [String: FunctionCallState] = [:]

                    for try await event in sseStream {
                        switch event {
                        case .event(let type, let data):
                            if type == "response.completed",
                               let encrypted = extractEncryptedReasoningEncryptedContent(from: data) {
                                continuation.yield(.thinkingDelta(.redacted(data: encrypted)))
                            }

                            if let streamEvent = try parseSSEEvent(
                                type: type,
                                data: data,
                                functionCallsByItemID: &functionCallsByItemID
                            ) {
                                continuation.yield(streamEvent)
                            }
                        case .done:
                            continuation.yield(.messageEnd(usage: nil))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildResponsesRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && supportsNativePDF(modelID)

        var body: [String: Any] = [
            "model": modelID,
            "input": translateInput(messages, supportsNativePDF: nativePDFEnabled),
            "stream": streaming
        ]

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            body["max_output_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }

        if supportsReasoningEffort(modelID: modelID),
           let reasoning = controls.reasoning,
           reasoning.enabled,
           let effort = reasoning.effort {
            body["reasoning_effort"] = mapReasoningEffort(effort)
        }

        if supportsEncryptedReasoning(modelID: modelID) {
            var include = Set((body["include"] as? [String]) ?? [])
            include.insert("reasoning.encrypted_content")
            body["include"] = Array(include).sorted()
        }

        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true {
            let sources = Set(controls.webSearch?.sources ?? [.web])

            if sources.contains(.web) {
                toolObjects.append(["type": "web_search"])
            }

            if sources.contains(.x) {
                toolObjects.append(["type": "x_search"])
            }
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            toolObjects.append(contentsOf: functionTools)
        }

        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        applyProviderSpecificOverrides(controls: controls, body: &body)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Image generation

    private func makeImageGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let imageURL = imageURLForImageGeneration(from: messages)
        let prompt = try mediaPrompt(from: messages, isImageEdit: imageURL?.isEmpty == false)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildImageGenerationRequest(
                        modelID: modelID,
                        prompt: prompt,
                        imageURL: imageURL,
                        controls: controls
                    )
                    let (data, _) = try await networkManager.sendRequest(request)

                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let response = try decoder.decode(XAIImageGenerationResponse.self, from: data)

                    if let error = response.error {
                        throw LLMError.providerError(code: error.code ?? "image_generation_failed", message: error.message)
                    }

                    let images = resolveImageOutputs(from: response.mediaItems)
                    guard !images.isEmpty else {
                        throw LLMError.decodingError(message: "xAI image generation returned no image output.")
                    }

                    continuation.yield(.messageStart(id: response.resolvedID ?? "img_\(UUID().uuidString)"))
                    for image in images {
                        continuation.yield(.contentDelta(.image(image)))
                    }
                    continuation.yield(.messageEnd(usage: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func buildImageGenerationRequest(
        modelID: String,
        prompt: String,
        imageURL: String?,
        controls: GenerationControls
    ) throws -> URLRequest {
        let endpoint = (imageURL?.isEmpty == false) ? "images/edits" : "images/generations"

        var request = URLRequest(url: URL(string: "\(baseURL)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let imageControls = controls.xaiImageGeneration

        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt
        ]

        if let count = imageControls?.count, count > 0 {
            body["n"] = min(max(count, 1), 10)
        }
        if let imageURL, !imageURL.isEmpty {
            body["image_url"] = imageURL
        }

        // xAI currently uses `aspect_ratio`; map older persisted `size` values for compatibility.
        if let aspectRatio = imageControls?.aspectRatio ?? imageControls?.size?.mappedAspectRatio {
            body["aspect_ratio"] = aspectRatio.rawValue
        }

        let responseFormat = imageControls?.responseFormat ?? .b64JSON
        body["response_format"] = responseFormat.rawValue
        if let user = imageControls?.user?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            body["user"] = user
        }

        applyProviderSpecificOverrides(controls: controls, body: &body)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Capability/model inference

    private func isUnsupportedVideoGenerationModel(_ model: ModelData) -> Bool {
        let lowerID = model.id.lowercased()
        if lowerID.contains("imagine-video")
            || lowerID.contains("grok-video")
            || lowerID.contains("video-generation")
            || lowerID.hasSuffix("-video") {
            return true
        }

        let outputModalities = (model.outputModalities ?? []) + (model.modalities ?? [])
        return outputModalities.contains(where: { $0.lowercased().contains("video") })
    }

    private func inferCapabilities(for model: ModelData) -> ModelCapability {
        let lowerID = model.id.lowercased()

        let inputModalities = Set((model.inputModalities ?? []).map { $0.lowercased() })
        let outputModalities = Set((model.outputModalities ?? []).map { $0.lowercased() })
        let allModalities = Set((model.modalities ?? []).map { $0.lowercased() })

        let hasImageOutput = outputModalities.contains(where: { $0.contains("image") })
            || allModalities.contains(where: { $0.contains("image") })
        let imageModel = hasImageOutput || isImageGenerationModelID(lowerID)

        if imageModel {
            return [.imageGeneration]
        }

        var caps: ModelCapability = [.streaming, .toolCalling]

        if inputModalities.contains(where: { $0.contains("image") }) || outputModalities.contains(where: { $0.contains("image") }) {
            caps.insert(.vision)
        }

        if lowerID.contains("grok") {
            caps.insert(.vision)
            caps.insert(.reasoning)
        }

        if supportsNativePDF(model.id) {
            caps.insert(.nativePDF)
        }

        return caps
    }

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.imageGeneration) == true {
            return true
        }
        return isImageGenerationModelID(modelID.lowercased())
    }

    private func isImageGenerationModelID(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("imagine-image")
            || lowerModelID.hasSuffix("-image")
            || lowerModelID.contains("grok-2-image")
    }

    // MARK: - Shared helpers

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh:
            return "high"
        }
    }

    private func supportsReasoningEffort(modelID: String) -> Bool {
        modelID.lowercased().contains("grok-3-mini")
    }

    private func supportsEncryptedReasoning(modelID: String) -> Bool {
        let lower = modelID.lowercased()
        guard lower.contains("grok-4") else { return false }
        return !lower.contains("non-reasoning")
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower.contains("grok-4.1")
            || lower.contains("grok-4-1")
            || lower.contains("grok-4.2")
            || lower.contains("grok-4-2")
            || lower.contains("grok-5")
            || lower.contains("grok-6")
    }

    private func mediaPrompt(from messages: [Message], isImageEdit: Bool) throws -> String {
        let userPrompts = userTextPrompts(from: messages)
        guard let latest = userPrompts.last else {
            throw LLMError.invalidRequest(message: "xAI image generation requires a text prompt.")
        }

        guard isImageEdit else {
            return latest
        }

        guard userPrompts.count >= 2 else {
            return latest
        }

        let recentPrompts = Array(userPrompts.suffix(6))
        let originalPrompt = recentPrompts.first ?? latest
        let latestPrompt = recentPrompts.last ?? latest
        let priorEdits = Array(recentPrompts.dropFirst().dropLast())

        if priorEdits.isEmpty, originalPrompt.caseInsensitiveCompare(latestPrompt) == .orderedSame {
            return latest
        }

        var lines: [String] = [
            "Edit the provided input image.",
            "Keep the main subject, composition, and scene continuity unless explicitly changed.",
            "",
            "Original request:",
            originalPrompt
        ]

        if !priorEdits.isEmpty {
            lines.append("")
            lines.append("Edits already applied:")
            for (idx, edit) in priorEdits.enumerated() {
                lines.append("\(idx + 1). \(edit)")
            }
        }

        lines.append("")
        lines.append("Apply this new edit now:")
        lines.append(latestPrompt)

        return lines.joined(separator: "\n")
    }

    private func userTextPrompts(from messages: [Message]) -> [String] {
        messages.compactMap { message in
            guard message.role == .user else { return nil }

            let text = message.content.compactMap { part -> String? in
                guard case .text(let value) = part else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            return text.isEmpty ? nil : text
        }
    }

    private func imageURLForImageGeneration(from messages: [Message]) -> String? {
        // If the latest user turn includes an image, prefer that explicit input.
        if let latestUserImageURL = latestUserImageURL(from: messages) {
            return latestUserImageURL
        }

        // Otherwise, continue editing from the latest assistant-generated image.
        if let assistantImageURL = firstImageURLString(from: messages, roles: [.assistant]) {
            return assistantImageURL
        }

        // Finally, fall back to any older user-provided image in history.
        return firstImageURLString(from: messages, roles: [.user])
    }

    private func latestUserImageURL(from messages: [Message]) -> String? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return firstImageURLString(in: latestUserMessage)
    }

    private func firstImageURLString(in message: Message) -> String? {
        for part in message.content {
            if case .image(let image) = part,
               let urlString = imageURLString(image) {
                return urlString
            }
        }
        return nil
    }

    private func firstImageURLString(from messages: [Message], roles: [MessageRole]) -> String? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let urlString = firstImageURLString(in: message) {
                return urlString
            }
        }
        return nil
    }

    private func imageURLString(_ image: ImageContent) -> String? {
        if let data = image.data {
            return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
        }

        if let url = image.url {
            if url.isFileURL, let data = try? Data(contentsOf: url) {
                return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
            }
            return url.absoluteString
        }

        return nil
    }

    private func resolveImageOutputs(from items: [XAIMediaItem]) -> [ImageContent] {
        var out: [ImageContent] = []
        out.reserveCapacity(items.count)

        for item in items {
            if let b64 = item.b64JSON,
               let data = Data(base64Encoded: b64) {
                out.append(ImageContent(mimeType: item.mimeType ?? "image/png", data: data, url: nil))
                continue
            }

            if let rawURL = item.resolvedURL,
               let url = URL(string: rawURL) {
                let mime = item.mimeType ?? inferImageMIMEType(from: url) ?? "image/png"
                out.append(ImageContent(mimeType: mime, data: nil, url: url))
            }
        }

        return out
    }

    private func inferImageMIMEType(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        default:
            return nil
        }
    }

    private func applyProviderSpecificOverrides(controls: GenerationControls, body: inout [String: Any]) {
        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }
    }

    private func extractEncryptedReasoningEncryptedContent(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return findEncryptedContent(in: object)
    }

    private func findEncryptedContent(in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            if let type = dict["type"] as? String,
               type == "reasoning",
               let encrypted = dict["encrypted_content"] as? String {
                return encrypted
            }

            if let encrypted = dict["encrypted_content"] as? String {
                return encrypted
            }

            for value in dict.values {
                if let found = findEncryptedContent(in: value) {
                    return found
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for element in array {
                if let found = findEncryptedContent(in: element) {
                    return found
                }
            }
            return nil
        }

        return nil
    }

    private func translateInput(_ messages: [Message], supportsNativePDF: Bool) -> [[String: Any]] {
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
                if let translated = translateMessage(message, supportsNativePDF: supportsNativePDF) {
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

    private func translateMessage(_ message: Message, supportsNativePDF: Bool) -> [String: Any]? {
        let content = message.content.compactMap { translateContentPart($0, supportsNativePDF: supportsNativePDF) }

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

    private func translateContentPart(_ part: ContentPart, supportsNativePDF: Bool) -> [String: Any]? {
        switch part {
        case .text(let text):
            return [
                "type": "input_text",
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
                if url.isFileURL, let data = try? Data(contentsOf: url) {
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
            if supportsNativePDF && file.mimeType == "application/pdf" {
                let pdfData: Data?
                if let data = file.data {
                    pdfData = data
                } else if let url = file.url, url.isFileURL {
                    pdfData = try? Data(contentsOf: url)
                } else {
                    pdfData = nil
                }

                if let pdfData {
                    return [
                        "type": "input_file",
                        "filename": file.filename,
                        "file_data": "data:application/pdf;base64,\(pdfData.base64EncodedString())"
                    ]
                }
            }

            let text = AttachmentPromptRenderer.fallbackText(for: file)
            return [
                "type": "input_text",
                "text": text
            ]

        case .thinking, .redactedThinking, .audio, .video:
            return nil
        }
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
        functionCallsByItemID: inout [String: FunctionCallState]
    ) throws -> StreamEvent? {
        guard let jsonData = data.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        switch type {
        case "response.created":
            let event = try decoder.decode(ResponseCreatedEvent.self, from: jsonData)
            return .messageStart(id: event.response.id)

        case "response.output_text.delta":
            let event = try decoder.decode(OutputTextDeltaEvent.self, from: jsonData)
            return .contentDelta(.text(event.delta))

        case "response.reasoning_text.delta":
            let event = try decoder.decode(ReasoningTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.reasoning_summary_text.delta":
            let event = try decoder.decode(ReasoningSummaryTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.output_item.added":
            let event = try decoder.decode(OutputItemAddedEvent.self, from: jsonData)
            guard event.item.type == "function_call",
                  let itemID = event.item.id,
                  let callID = event.item.callId,
                  let name = event.item.name else {
                return nil
            }

            functionCallsByItemID[itemID] = FunctionCallState(callID: callID, name: name)
            return .toolCallStart(ToolCall(id: callID, name: name, arguments: [:]))

        case "response.function_call_arguments.delta":
            let event = try decoder.decode(FunctionCallArgumentsDeltaEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }

            functionCallsByItemID[event.itemId]?.argumentsBuffer += event.delta
            return .toolCallDelta(id: state.callID, argumentsDelta: event.delta)

        case "response.function_call_arguments.done":
            let event = try decoder.decode(FunctionCallArgumentsDoneEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }
            functionCallsByItemID.removeValue(forKey: event.itemId)

            let args = parseJSONObject(event.arguments)
            return .toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args))

        case "response.completed":
            let event = try decoder.decode(ResponseCompletedEvent.self, from: jsonData)
            let usage = Usage(
                inputTokens: event.response.usage.inputTokens,
                outputTokens: event.response.usage.outputTokens,
                thinkingTokens: event.response.usage.outputTokensDetails?.reasoningTokens
            )
            return .messageEnd(usage: usage)

        case "response.failed":
            if let errorEvent = try? decoder.decode(ResponseFailedEvent.self, from: jsonData),
               let message = errorEvent.response.error?.message {
                return .error(.providerError(code: errorEvent.response.error?.code ?? "response_failed", message: message))
            }
            return .error(.providerError(code: "response_failed", message: data))

        default:
            return nil
        }
    }

    private func parseJSONObject(_ jsonString: String) -> [String: AnyCodable] {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.mapValues(AnyCodable.init)
    }

    private func encodeJSONObject(_ object: [String: AnyCodable]) -> String {
        let raw = object.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

private struct FunctionCallState {
    let callID: String
    let name: String
    var argumentsBuffer: String = ""
}

// MARK: - Models Response

private struct ModelsResponse: Codable {
    let data: [ModelData]
}

private struct ModelData: Codable {
    let id: String
    let inputModalities: [String]?
    let outputModalities: [String]?
    let modalities: [String]?
    let contextWindow: Int?
}

// MARK: - Streaming Event Types

private struct ResponseCreatedEvent: Codable {
    let response: ResponseInfo

    struct ResponseInfo: Codable {
        let id: String
    }
}

private struct OutputTextDeltaEvent: Codable {
    let delta: String
}

private struct ReasoningTextDeltaEvent: Codable {
    let delta: String
}

private struct ReasoningSummaryTextDeltaEvent: Codable {
    let delta: String
}

private struct OutputItemAddedEvent: Codable {
    let item: Item

    struct Item: Codable {
        let id: String?
        let type: String
        let callId: String?
        let name: String?
    }
}

private struct FunctionCallArgumentsDeltaEvent: Codable {
    let itemId: String
    let delta: String
}

private struct FunctionCallArgumentsDoneEvent: Codable {
    let itemId: String
    let arguments: String
}

private struct ResponseCompletedEvent: Codable {
    let response: Response

    struct Response: Codable {
        let usage: UsageInfo

        struct UsageInfo: Codable {
            let inputTokens: Int
            let outputTokens: Int
            let outputTokensDetails: OutputTokensDetails?

            struct OutputTokensDetails: Codable {
                let reasoningTokens: Int?
            }
        }
    }
}

private struct ResponseFailedEvent: Codable {
    let response: Response

    struct Response: Codable {
        let error: ErrorInfo?

        struct ErrorInfo: Codable {
            let code: String?
            let message: String
        }
    }
}

// MARK: - Media Generation Response Types

private struct XAIAPIError: Codable {
    let code: String?
    let message: String
}

private struct XAIMediaItem: Codable {
    let url: String?
    let imageUrl: String?
    let videoUrl: String?
    let resultUrl: String?
    let b64Json: String?
    let mimeType: String?

    var b64JSON: String? {
        b64Json
    }

    var resolvedURL: String? {
        url ?? imageUrl ?? videoUrl ?? resultUrl
    }
}

private struct XAIImageGenerationResponse: Codable {
    let id: String?
    let requestId: String?
    let responseId: String?
    let data: [XAIMediaItem]?
    let output: [XAIMediaItem]?
    let result: [XAIMediaItem]?
    let images: [XAIMediaItem]?
    let url: String?
    let imageUrl: String?
    let b64Json: String?
    let mimeType: String?
    let error: XAIAPIError?

    var resolvedID: String? {
        requestId ?? responseId ?? id
    }

    var mediaItems: [XAIMediaItem] {
        var merged: [XAIMediaItem] = []
        for collection in [data, output, result, images] {
            if let collection {
                merged.append(contentsOf: collection)
            }
        }

        if let inline = inlineMediaItem {
            merged.append(inline)
        }

        return merged
    }

    private var inlineMediaItem: XAIMediaItem? {
        guard url != nil || imageUrl != nil || b64Json != nil else {
            return nil
        }

        return XAIMediaItem(
            url: url,
            imageUrl: imageUrl,
            videoUrl: nil,
            resultUrl: nil,
            b64Json: b64Json,
            mimeType: mimeType
        )
    }
}

// MARK: - Non-streaming Responses API Types

private struct ResponsesAPIResponse: Codable {
    let id: String
    let output: [OutputItem]
    let usage: UsageInfo?

    struct OutputItem: Codable {
        let type: String
        let content: [Content]?
        let summary: [Content]?

        struct Content: Codable {
            let type: String
            let text: String?
        }
    }

    struct UsageInfo: Codable {
        let inputTokens: Int
        let outputTokens: Int
        let outputTokensDetails: OutputTokensDetails?

        struct OutputTokensDetails: Codable {
            let reasoningTokens: Int?
        }
    }

    var outputTextParts: [String] {
        output.flatMap { item in
            switch item.type {
            case "message":
                return item.content?.compactMap { $0.type == "output_text" ? $0.text : nil } ?? []
            case "reasoning":
                return item.summary?.compactMap { $0.type == "summary_text" ? $0.text : nil } ?? []
            default:
                return []
            }
        }
    }

    func toUsage() -> Usage? {
        guard let usage else { return nil }
        return Usage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            thinkingTokens: usage.outputTokensDetails?.reasoningTokens
        )
    }
}
