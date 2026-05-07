import Foundation

actor ClaudeManagedAgentsAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .promptCaching]

    let apiKey: String
    let networkManager: NetworkManager

    init(
        providerConfig: ProviderConfig,
        apiKey: String,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming _: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let session = try await resolveSession(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools
        )
        let initialRequest = try buildTurnSubmissionRequest(
            sessionID: session.id,
            messages: messages,
            controls: controls
        )
        return makeManagedAgentStream(
            session: session,
            initialRequest: initialRequest,
            tools: tools
        )
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map { tool in
            [
                "type": "custom",
                "name": tool.name,
                "description": tool.description,
                "input_schema": [
                    "type": tool.parameters.type,
                    "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                    "required": tool.parameters.required
                ]
            ]
        }
    }
}
