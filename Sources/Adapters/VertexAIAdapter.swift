import Foundation

actor VertexAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF, .imageGeneration, .videoGeneration]
    let networkManager: NetworkManager
    let serviceAccountJSON: ServiceAccountCredentials

    private let modelSupport: VertexAIModelSupport
    let cachedContentClient: VertexAICachedContentClient
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
            "parametersJsonSchema": toolParametersSchema(tool.parameters)
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
        VertexAIRequestBuilder.makeAuthHeaders(accessToken: accessToken, accept: accept, contentType: contentType)
    }

    var baseURL: String { serviceAccountJSON.vertexBaseURL }
    var location: String { serviceAccountJSON.resolvedLocation }

    func makeRequestBuilder() -> VertexAIRequestBuilder {
        VertexAIRequestBuilder(
            providerConfig: providerConfig,
            serviceAccountJSON: serviceAccountJSON,
            modelSupport: modelSupport
        )
    }
}

// JWT types, PEM/DER parsing, and base64URL encoding are in VertexAIJWTSupport.swift
// Response types are defined in VertexAIAdapterResponseTypes.swift
// Response stream assembly is in VertexAIAdapter+ResponseStreaming.swift
