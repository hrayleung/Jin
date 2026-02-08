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
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .nativePDF, .imageGeneration]

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
        let request = try buildRequest(
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
            let response = try decoder.decode(GenerateContentResponse.self, from: data)

            // Handle prompt-level blocks explicitly (Gemini returns promptFeedback for blocked prompts).
            if response.promptFeedback?.blockReason != nil {
                throw LLMError.contentFiltered
            }

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: UUID().uuidString))

                let usage = response.toUsage()

                if let candidate = response.candidates?.first {
                    if isCandidateContentFiltered(candidate) {
                        continuation.yield(.error(.contentFiltered))
                        continuation.finish()
                        return
                    }

                    for part in candidate.content?.parts ?? [] {
                        for event in events(from: part) {
                            continuation.yield(event)
                        }
                    }
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

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            guard let jsonData = data.data(using: .utf8) else { continue }

                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            let chunk = try decoder.decode(GenerateContentResponse.self, from: jsonData)

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

                                for part in candidate.content?.parts ?? [] {
                                    for streamEvent in events(from: part) {
                                        continuation.yield(streamEvent)
                                    }
                                }
                            }

                        case .done:
                            // Gemini SSE streams typically end by closing the connection (no [DONE]),
                            // but handle it anyway for compatibility.
                            break
                        }
                    }

                    if didStart {
                        continuation.yield(.messageEnd(usage: pendingUsage))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.addValue(key, forHTTPHeaderField: "x-goog-api-key")

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var pageToken: String?
        var models: [ModelInfo] = []
        var seenIDs: Set<String> = []

        while true {
            var components = URLComponents(string: "\(baseURL)/models")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "pageSize", value: "1000")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw LLMError.invalidRequest(message: "Invalid Gemini models URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

            let (data, _) = try await networkManager.sendRequest(request)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ListModelsResponse.self, from: data)

            for model in response.models {
                let info = makeModelInfo(from: model)
                guard !seenIDs.contains(info.id) else { continue }
                seenIDs.insert(info.id)
                models.append(info)
            }

            guard let next = response.nextPageToken,
                  !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  next != pageToken else {
                break
            }

            pageToken = next
        }

        return models.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        providerConfig.baseURL ?? ProviderType.gemini.defaultBaseURL ?? "https://generativelanguage.googleapis.com/v1beta"
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let modelPath = modelIDForPath(modelID)
        let method = streaming ? "streamGenerateContent?alt=sse" : "generateContent"
        let endpoint = "\(baseURL)/models/\(modelPath):\(method)"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && supportsNativePDF(modelID)

        var body: [String: Any] = [
            "contents": translateContents(messages, supportsNativePDF: nativePDFEnabled),
            "generationConfig": buildGenerationConfig(controls, modelID: modelID)
        ]

        if let systemInstruction = systemInstructionText(from: messages) {
            body["systemInstruction"] = [
                "parts": [
                    ["text": systemInstruction]
                ]
            ]
        }

        var toolArray: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsGoogleSearch(modelID) {
            toolArray.append(["google_search": [:]])
        }

        if supportsFunctionCalling(modelID), !tools.isEmpty,
           let functionDeclarations = translateTools(tools) as? [[String: Any]] {
            toolArray.append(["functionDeclarations": functionDeclarations])
        }

        if !toolArray.isEmpty {
            body["tools"] = toolArray
        }

        if !controls.providerSpecific.isEmpty {
            deepMerge(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func systemInstructionText(from messages: [Message]) -> String? {
        let text = messages
            .filter { $0.role == .system }
            .flatMap(\.content)
            .compactMap { part -> String? in
                if case .text(let text) = part { return text }
                return nil
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    private func modelIDForPath(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        isGemini3Model(modelID) && !isImageGenerationModel(modelID)
    }

    private func isGemini3Model(_ modelID: String) -> Bool {
        modelID.lowercased().contains("gemini-3")
    }

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        // Gemini image-generation models include `-image` (e.g. gemini-2.5-flash-image, gemini-3-pro-image-preview).
        return lower.contains("-image")
    }

    private func supportsFunctionCalling(_ modelID: String) -> Bool {
        // Gemini image-generation models do not support function calling.
        !isImageGenerationModel(modelID)
    }

    private func supportsGoogleSearch(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        // Gemini 2.5 Flash Image does not support Google Search grounding.
        if lower.contains("gemini-2.5-flash-image") {
            return false
        }
        return true
    }

    private func supportsImageSize(_ modelID: String) -> Bool {
        // imageSize is documented for Gemini 3 Pro Image.
        modelID.lowercased().contains("gemini-3-pro-image")
    }

    private func supportsThinking(_ modelID: String) -> Bool {
        // Gemini 2.5 Flash Image does not support thinking; Gemini 3 Pro Image does.
        !modelID.lowercased().contains("gemini-2.5-flash-image")
    }

    private func buildGenerationConfig(_ controls: GenerationControls, modelID: String) -> [String: Any] {
        var config: [String: Any] = [:]
        let isImageModel = isImageGenerationModel(modelID)

        if let temperature = controls.temperature {
            config["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            config["maxOutputTokens"] = maxTokens
        }
        if let topP = controls.topP {
            config["topP"] = topP
        }

        // Gemini 3: dynamic thinking is on by default; thinkingLevel controls the amount of thinking.
        if supportsThinking(modelID), let reasoning = controls.reasoning {
            if reasoning.enabled {
                var thinkingConfig: [String: Any] = [
                    "includeThoughts": true
                ]

                if let effort = reasoning.effort {
                    thinkingConfig["thinkingLevel"] = mapEffortToThinkingLevel(effort, modelID: modelID)
                } else if let budget = reasoning.budgetTokens {
                    thinkingConfig["thinkingBudget"] = budget
                }

                config["thinkingConfig"] = thinkingConfig
            } else if isGemini3Model(modelID) {
                // Best-effort "off": minimize thinking level (cannot be fully disabled for Gemini 3 Pro).
                config["thinkingConfig"] = [
                    "thinkingLevel": defaultThinkingLevelWhenOff(modelID: modelID)
                ]
            }
        }

        if isImageModel {
            let imageControls = controls.imageGeneration
            let responseMode = imageControls?.responseMode ?? .textAndImage
            config["responseModalities"] = responseMode.responseModalities

            if let seed = imageControls?.seed {
                config["seed"] = seed
            }

            var imageConfig: [String: Any] = [:]
            if let aspectRatio = imageControls?.aspectRatio {
                imageConfig["aspectRatio"] = aspectRatio.rawValue
            }
            if supportsImageSize(modelID), let imageSize = imageControls?.imageSize {
                imageConfig["imageSize"] = imageSize.rawValue
            }
            if !imageConfig.isEmpty {
                config["imageConfig"] = imageConfig
            }
        }

        return config
    }

    private func defaultThinkingLevelWhenOff(modelID: String) -> String {
        let lower = modelID.lowercased()
        if lower.contains("gemini-3-pro") {
            return "LOW"
        }
        return "MINIMAL"
    }

    private func mapEffortToThinkingLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        let lower = modelID.lowercased()
        let isPro = lower.contains("gemini-3-pro")

        switch effort {
        case .none:
            return isPro ? "LOW" : "MINIMAL"
        case .minimal:
            return isPro ? "LOW" : "MINIMAL"
        case .low:
            return "LOW"
        case .medium:
            return isPro ? "HIGH" : "MEDIUM"
        case .high:
            return "HIGH"
        case .xhigh:
            return "HIGH"
        }
    }

    private func translateContents(_ messages: [Message], supportsNativePDF: Bool) -> [[String: Any]] {
        var out: [[String: Any]] = []
        out.reserveCapacity(messages.count + 4)

        for message in messages where message.role != .system {
            switch message.role {
            case .system:
                continue
            case .tool:
                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    out.append(translateToolResults(toolResults))
                }
            case .user, .assistant:
                out.append(translateNonToolMessage(message, supportsNativePDF: supportsNativePDF))

                // Some providers/users serialize tool results inline on non-tool messages; handle defensively.
                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    out.append(translateToolResults(toolResults))
                }
            }
        }

        return out
    }

    private func translateNonToolMessage(_ message: Message, supportsNativePDF: Bool) -> [String: Any] {
        let role: String = (message.role == .assistant) ? "model" : "user"

        var parts: [[String: Any]] = []

        // Preserve thoughts first for model turns to keep tool calling stable when thought signatures are enabled.
        if message.role == .assistant {
            for part in message.content {
                if case .thinking(let thinking) = part {
                    var dict: [String: Any] = [
                        "text": thinking.text,
                        "thought": true
                    ]
                    if let signature = thinking.signature {
                        dict["thoughtSignature"] = signature
                    }
                    parts.append(dict)
                }
            }
        }

        // User-visible content (text/images/files).
        for part in message.content {
            switch part {
            case .text(let text):
                parts.append(["text": text])

            case .image(let image):
                if let inline = inlineDataPart(mimeType: image.mimeType, data: image.data, url: image.url) {
                    parts.append(inline)
                }

            case .file(let file):
                // Native PDF support for Gemini 3 series.
                if supportsNativePDF, file.mimeType == "application/pdf" {
                    let pdfData: Data?
                    if let data = file.data {
                        pdfData = data
                    } else if let url = file.url, url.isFileURL {
                        pdfData = try? Data(contentsOf: url)
                    } else {
                        pdfData = nil
                    }

                    if let pdfData {
                        parts.append([
                            "inlineData": [
                                "mimeType": "application/pdf",
                                "data": pdfData.base64EncodedString()
                            ]
                        ])
                        continue
                    }
                }

                // Fallback to text extraction.
                let text = AttachmentPromptRenderer.fallbackText(for: file)
                parts.append(["text": text])

            case .thinking, .redactedThinking, .audio:
                continue
            }
        }

        // Function calls (model output) are appended to model turns.
        if message.role == .assistant, let toolCalls = message.toolCalls {
            for call in toolCalls {
                var part: [String: Any] = [
                    "functionCall": [
                        "name": call.name,
                        "args": call.arguments.mapValues { $0.value }
                    ]
                ]
                if let signature = call.signature {
                    part["thoughtSignature"] = signature
                }
                parts.append(part)
            }
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return [
            "role": role,
            "parts": parts
        ]
    }

    private func translateToolResults(_ results: [ToolResult]) -> [String: Any] {
        var parts: [[String: Any]] = []
        parts.reserveCapacity(results.count)

        for result in results {
            guard let toolName = result.toolName, !toolName.isEmpty else { continue }

            var part: [String: Any] = [
                "functionResponse": [
                    "name": toolName,
                    "response": [
                        "content": result.content
                    ]
                ]
            ]

            if let signature = result.signature {
                part["thoughtSignature"] = signature
            }

            parts.append(part)
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return [
            "role": "user",
            "parts": parts
        ]
    }

    private func inlineDataPart(mimeType: String, data: Data?, url: URL?) -> [String: Any]? {
        if let data {
            return [
                "inlineData": [
                    "mimeType": mimeType,
                    "data": data.base64EncodedString()
                ]
            ]
        }

        if let url {
            if url.isFileURL, let data = try? Data(contentsOf: url) {
                return [
                    "inlineData": [
                        "mimeType": mimeType,
                        "data": data.base64EncodedString()
                    ]
                ]
            }
        }

        return nil
    }

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        var propertiesDict: [String: Any] = [:]
        for (key, prop) in tool.parameters.properties {
            propertiesDict[key] = prop.toDictionary()
        }

        return [
            "name": tool.name,
            "description": tool.description,
            "parameters": [
                "type": tool.parameters.type,
                "properties": propertiesDict,
                "required": tool.parameters.required
            ]
        ]
    }

    private func events(from part: GenerateContentResponse.Part) -> [StreamEvent] {
        var out: [StreamEvent] = []

        if part.thought == true {
            let text = part.text ?? ""
            let signature = part.thoughtSignature
            if !text.isEmpty || signature != nil {
                out.append(.thinkingDelta(.thinking(textDelta: text, signature: signature)))
            }
        } else if let text = part.text, !text.isEmpty {
            out.append(.contentDelta(.text(text)))
        }

        if let inline = part.inlineData,
           let base64 = inline.data,
           let data = Data(base64Encoded: base64) {
            let mimeType = inline.mimeType ?? "image/png"
            if mimeType.lowercased().hasPrefix("image/") {
                out.append(.contentDelta(.image(ImageContent(mimeType: mimeType, data: data))))
            }
        }

        if let functionCall = part.functionCall {
            let toolCall = ToolCall(
                id: UUID().uuidString,
                name: functionCall.name,
                arguments: functionCall.args ?? [:],
                signature: part.thoughtSignature
            )
            out.append(.toolCallStart(toolCall))
            out.append(.toolCallEnd(toolCall))
        }

        return out
    }

    private func isCandidateContentFiltered(_ candidate: GenerateContentResponse.Candidate) -> Bool {
        // Gemini can signal blocks via finishReason. Treat safety/blocked as filtered.
        let reason = (candidate.finishReason ?? "").uppercased()
        if reason == "SAFETY" || reason == "BLOCKED" || reason == "PROHIBITED_CONTENT" {
            return true
        }
        return false
    }

    private func makeModelInfo(from model: ListModelsResponse.Model) -> ModelInfo {
        let id = model.id
        let lower = id.lowercased()
        let methods = Set(model.supportedGenerationMethods?.map { $0.lowercased() } ?? [])

        var caps: ModelCapability = []

        let supportsGenerateContent = methods.contains("generatecontent") || methods.contains("streamgeneratecontent") || methods.isEmpty
        let supportsStream = methods.contains("streamgeneratecontent") || methods.isEmpty

        if supportsStream {
            caps.insert(.streaming)
        }

        let isImageModel = isImageGenerationModel(id) || lower.contains("imagen")
        let isGeminiModel = lower.contains("gemini")

        if supportsGenerateContent && !isImageModel {
            caps.insert(.toolCalling)
        }

        if isGeminiModel || isImageModel || lower.contains("vision") || lower.contains("multimodal") {
            caps.insert(.vision)
        }

        var reasoningConfig: ModelReasoningConfig?
        if supportsThinking(id) && (isGeminiModel || lower.contains("reason") || lower.contains("thinking")) {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
        }

        if supportsNativePDF(id) {
            caps.insert(.nativePDF)
        }

        if isImageModel {
            caps.insert(.imageGeneration)
        }

        let contextWindow = model.inputTokenLimit ?? 1_048_576

        return ModelInfo(
            id: id,
            name: model.displayName ?? id,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            isEnabled: true
        )
    }

    private func deepMerge(into base: inout [String: Any], additional: [String: Any]) {
        for (key, value) in additional {
            if var baseDict = base[key] as? [String: Any],
               let addDict = value as? [String: Any] {
                deepMerge(into: &baseDict, additional: addDict)
                base[key] = baseDict
                continue
            }
            base[key] = value
        }
    }
}

// MARK: - DTOs

private struct ListModelsResponse: Codable {
    let models: [Model]
    let nextPageToken: String?

    struct Model: Codable {
        let name: String
        let displayName: String?
        let description: String?
        let inputTokenLimit: Int?
        let outputTokenLimit: Int?
        let supportedGenerationMethods: [String]?

        var id: String {
            if name.lowercased().hasPrefix("models/") {
                return String(name.dropFirst("models/".count))
            }
            return name
        }
    }
}

private struct GenerateContentResponse: Codable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let usageMetadata: UsageMetadata?

    struct Candidate: Codable {
        let content: Content?
        let finishReason: String?
    }

    struct Content: Codable {
        let parts: [Part]?
        let role: String?
    }

    struct Part: Codable {
        let text: String?
        let thought: Bool?
        let thoughtSignature: String?
        let functionCall: FunctionCall?
        let functionResponse: FunctionResponse?
        let inlineData: InlineData?
    }

    struct InlineData: Codable {
        let mimeType: String?
        let data: String?
    }

    struct FunctionCall: Codable {
        let name: String
        let args: [String: AnyCodable]?
    }

    struct FunctionResponse: Codable {
        let name: String?
        let response: [String: AnyCodable]?
    }

    struct PromptFeedback: Codable {
        let blockReason: String?
    }

    struct UsageMetadata: Codable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?
    }

    func toUsage() -> Usage? {
        guard let usageMetadata else { return nil }
        guard let input = usageMetadata.promptTokenCount,
              let output = usageMetadata.candidatesTokenCount else {
            return nil
        }
        return Usage(
            inputTokens: input,
            outputTokens: output,
            thinkingTokens: nil
        )
    }
}
