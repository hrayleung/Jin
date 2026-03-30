import Foundation

actor VertexAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF, .imageGeneration, .videoGeneration]
    let networkManager: NetworkManager
    let serviceAccountJSON: ServiceAccountCredentials

    private let modelSupport: VertexAIModelSupport
    private let cachedContentClient: VertexAICachedContentClient
    private let tokenProvider: VertexAIAccessTokenProvider

    init(
        providerConfig: ProviderConfig,
        serviceAccountJSON: ServiceAccountCredentials,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.providerConfig = providerConfig
        self.serviceAccountJSON = serviceAccountJSON
        self.networkManager = networkManager

        let modelSupport = VertexAIModelSupport()
        self.modelSupport = modelSupport
        self.cachedContentClient = VertexAICachedContentClient(
            serviceAccountJSON: serviceAccountJSON,
            networkManager: networkManager
        )
        self.tokenProvider = VertexAIAccessTokenProvider(
            serviceAccountJSON: serviceAccountJSON,
            networkManager: networkManager
        )
    }

    struct CachedContentResource: Codable, Hashable, Sendable {
        let name: String
        let model: String?
        let displayName: String?
        let createTime: String?
        let updateTime: String?
        let expireTime: String?
    }

    func listCachedContents() async throws -> [CachedContentResource] {
        let token = try await getAccessToken()
        return try await cachedContentClient.listCachedContents(accessToken: token)
    }

    func getCachedContent(named name: String) async throws -> CachedContentResource {
        let token = try await getAccessToken()
        return try await cachedContentClient.getCachedContent(named: name, accessToken: token)
    }

    func createCachedContent(payload: [String: Any]) async throws -> CachedContentResource {
        let token = try await getAccessToken()
        return try await cachedContentClient.createCachedContent(payload: payload, accessToken: token)
    }

    func updateCachedContent(
        named name: String,
        payload: [String: Any],
        updateMask: String? = nil
    ) async throws -> CachedContentResource {
        let token = try await getAccessToken()
        return try await cachedContentClient.updateCachedContent(
            named: name,
            payload: payload,
            updateMask: updateMask,
            accessToken: token
        )
    }

    func deleteCachedContent(named name: String) async throws {
        let token = try await getAccessToken()
        try await cachedContentClient.deleteCachedContent(named: name, accessToken: token)
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let token = try await getAccessToken()

        if GoogleVideoGenerationCore.isVideoGenerationModel(modelID) {
            return try makeVideoGenerationStream(
                messages: messages,
                modelID: modelID,
                controls: controls,
                accessToken: token
            )
        }

        let request = try makeRequestBuilder().buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming,
            accessToken: token
        )

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let response = try decodeGenerateContentResponse(from: data)
            return try makeNonStreamingEventStream(response: response)
        }

        let parser = JSONLineParser()
        let lineStream = await networkManager.streamRequest(request, parser: parser)
        return makeEventStream(from: lineStream)
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        do {
            _ = try await getAccessToken()
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        modelSupport.knownModels.map {
            modelSupport.makeModelInfo(id: $0.id, displayName: $0.name, contextWindow: $0.contextWindow)
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "parametersJsonSchema": [
                "type": tool.parameters.type,
                "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                "required": tool.parameters.required
            ]
        ]
    }

    func getAccessToken() async throws -> String {
        try await tokenProvider.accessToken()
    }

    func vertexHeaders(
        accessToken: String,
        accept: String? = nil,
        contentType: String? = nil
    ) -> [String: String] {
        makeRequestBuilder().vertexHeaders(
            accessToken: accessToken,
            accept: accept,
            contentType: contentType
        )
    }

    var baseURL: String {
        if location == "global" {
            return "https://aiplatform.googleapis.com/v1"
        }
        return "https://\(location)-aiplatform.googleapis.com/v1"
    }

    var location: String {
        serviceAccountJSON.location ?? "global"
    }

    private func makeRequestBuilder() -> VertexAIRequestBuilder {
        VertexAIRequestBuilder(
            providerConfig: providerConfig,
            serviceAccountJSON: serviceAccountJSON,
            modelSupport: modelSupport
        )
    }

    private func decodeGenerateContentResponse(from data: Data) throws -> VertexGenerateContentResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VertexGenerateContentResponse.self, from: data)
    }

    private func makeNonStreamingEventStream(
        response: VertexGenerateContentResponse
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        if isResponseContentFiltered(response) {
            throw LLMError.contentFiltered
        }

        return AsyncThrowingStream { continuation in
            continuation.yield(.messageStart(id: UUID().uuidString))

            let usage = usageFromVertexResponse(response)
            var codeExecutionState = GeminiModelConstants.GoogleCodeExecutionEventState()
            for event in eventsFromVertexResponse(response, codeExecutionState: &codeExecutionState) {
                continuation.yield(event)
            }

            continuation.yield(.messageEnd(usage: usage))
            continuation.finish()
        }
    }

    private func makeEventStream(
        from lineStream: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let messageID = UUID().uuidString
                do {
                    var didStart = false
                    var decodedChunkCount = 0
                    var pendingJSON = ""
                    var pendingUsage: Usage?
                    var codeExecutionState = GeminiModelConstants.GoogleCodeExecutionEventState()

                    for try await line in lineStream {
                        guard let data = normalizeVertexStreamLine(line) else { continue }

                        if !didStart {
                            didStart = true
                            continuation.yield(.messageStart(id: messageID))
                        }

                        pendingJSON += data
                        pendingJSON += "\n"
                        let outcome = try yieldParsedEvents(
                            from: &pendingJSON,
                            pendingUsage: &pendingUsage,
                            codeExecutionState: &codeExecutionState,
                            continuation: continuation
                        )
                        decodedChunkCount += outcome.decodedObjectCount

                        if outcome.contentFiltered {
                            continuation.yield(.error(.contentFiltered))
                            continuation.finish()
                            return
                        }

                        if pendingJSON.count > 64_000_000 {
                            pendingJSON = String(pendingJSON.suffix(1_048_576))
                        }
                    }

                    let finalOutcome = try yieldParsedEvents(
                        from: &pendingJSON,
                        pendingUsage: &pendingUsage,
                        codeExecutionState: &codeExecutionState,
                        continuation: continuation
                    )
                    decodedChunkCount += finalOutcome.decodedObjectCount

                    if finalOutcome.contentFiltered {
                        if !didStart {
                            continuation.yield(.messageStart(id: messageID))
                        }
                        continuation.yield(.error(.contentFiltered))
                        continuation.finish()
                        return
                    }

                    if decodedChunkCount == 0 {
                        if !didStart {
                            continuation.yield(.messageStart(id: messageID))
                        }
                        continuation.yield(.error(.decodingError(message: "Vertex AI returned an empty response with no usable JSON content.")))
                        continuation.yield(.messageEnd(usage: nil))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.messageEnd(usage: pendingUsage))
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

    private func yieldParsedEvents(
        from pendingJSON: inout String,
        pendingUsage: inout Usage?,
        codeExecutionState: inout GeminiModelConstants.GoogleCodeExecutionEventState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) throws -> (decodedObjectCount: Int, contentFiltered: Bool) {
        guard !pendingJSON.isEmpty else { return (0, false) }

        let jsonObjects = extractJSONObjectStrings(from: &pendingJSON)
        guard !jsonObjects.isEmpty else { return (0, false) }

        for jsonObject in jsonObjects {
            let parsed = try parseStreamChunk(jsonObject, codeExecutionState: &codeExecutionState)
            if parsed.contentFiltered {
                return (1, true)
            }
            if let usage = parsed.usage {
                pendingUsage = usage
            }
            for streamEvent in parsed.events {
                continuation.yield(streamEvent)
            }
        }

        return (jsonObjects.count, false)
    }
}

// JWT types, PEM/DER parsing, and base64URL encoding are in VertexAIJWTSupport.swift
// Response types are defined in VertexAIAdapterResponseTypes.swift
