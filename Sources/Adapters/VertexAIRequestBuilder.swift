import Foundation

struct VertexAIRequestBuilder {
    let providerConfig: ProviderConfig
    let serviceAccountJSON: ServiceAccountCredentials
    let modelSupport: VertexAIModelSupport

    init(
        providerConfig: ProviderConfig,
        serviceAccountJSON: ServiceAccountCredentials,
        modelSupport: VertexAIModelSupport
    ) {
        self.providerConfig = providerConfig
        self.serviceAccountJSON = serviceAccountJSON
        self.modelSupport = modelSupport
    }

    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool,
        accessToken: String
    ) throws -> URLRequest {
        let normalizedModelID = normalizedModelID(from: modelID)
        let endpoint = try makeRequestURL(modelID: normalizedModelID, streaming: streaming)
        var body = try makeRequestBody(
            messages: messages,
            modelID: normalizedModelID,
            controls: controls,
            tools: tools
        )

        if !controls.providerSpecific.isEmpty {
            deepMergeDictionary(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
        }

        return try NetworkRequestFactory.makeJSONRequest(
            url: endpoint,
            timeoutSeconds: modelSupport.requestTimeoutInterval(for: normalizedModelID, controls: controls),
            headers: vertexHeaders(accessToken: accessToken),
            body: body
        )
    }

    func vertexHeaders(
        accessToken: String,
        accept: String? = nil,
        contentType: String? = nil
    ) -> [String: String] {
        var headers: [String: String] = ["Authorization": "Bearer \(accessToken)"]
        if let accept {
            headers["Accept"] = accept
        }
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return headers
    }

}
