import Foundation
import Security

actor VertexAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF, .imageGeneration, .videoGeneration]
    // Model ID sets are shared with GeminiAdapter via GeminiModelConstants.

    let networkManager: NetworkManager
    let serviceAccountJSON: ServiceAccountCredentials
    private var cachedToken: (token: String, expiresAt: Date)?

    init(
        providerConfig: ProviderConfig,
        serviceAccountJSON: ServiceAccountCredentials,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.providerConfig = providerConfig
        self.serviceAccountJSON = serviceAccountJSON
        self.networkManager = networkManager
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
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL(cachedContentsCollectionEndpoint),
            headers: vertexHeaders(accessToken: token, accept: "application/json")
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(VertexCachedContentsListResponse.self, from: data)
        return response.cachedContents ?? []
    }

    func getCachedContent(named name: String) async throws -> CachedContentResource {
        let token = try await getAccessToken()
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL(cachedContentEndpoint(for: name)),
            headers: vertexHeaders(accessToken: token, accept: "application/json")
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func createCachedContent(payload: [String: Any]) async throws -> CachedContentResource {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent payload.")
        }

        let token = try await getAccessToken()
        let request = try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL(cachedContentsCollectionEndpoint),
            headers: vertexHeaders(accessToken: token),
            body: payload
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func updateCachedContent(named name: String, payload: [String: Any], updateMask: String? = nil) async throws -> CachedContentResource {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent payload.")
        }

        let token = try await getAccessToken()
        var components = URLComponents(string: cachedContentEndpoint(for: name))
        if let updateMask {
            components?.queryItems = [URLQueryItem(name: "updateMask", value: updateMask)]
        }
        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Invalid cachedContent URL.")
        }

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: url,
            method: "PATCH",
            headers: vertexHeaders(accessToken: token),
            body: payload
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func deleteCachedContent(named name: String) async throws {
        let token = try await getAccessToken()
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL(cachedContentEndpoint(for: name)),
            method: "DELETE",
            headers: vertexHeaders(accessToken: token)
        )
        _ = try await networkManager.sendRequest(request)
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

        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming,
            accessToken: token
        )

        // Vertex streams JSON objects per line (sometimes wrapped in SSE "data:" lines).
        let parser = JSONLineParser()
        let lineStream = await networkManager.streamRequest(request, parser: parser)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var didStart = false
                    var pendingJSON = ""
                    var pendingUsage: Usage?
                    var codeExecutionState = GeminiModelConstants.GoogleCodeExecutionEventState()

                    for try await line in lineStream {
                        guard let data = normalizeVertexStreamLine(line) else { continue }

                        if !didStart {
                            didStart = true
                            continuation.yield(.messageStart(id: UUID().uuidString))
                        }

                        pendingJSON += data
                        pendingJSON += "\n"

                        for jsonObject in extractJSONObjectStrings(from: &pendingJSON) {
                            let parsed = try parseStreamChunk(jsonObject, codeExecutionState: &codeExecutionState)
                            if let usage = parsed.usage {
                                pendingUsage = usage
                            }
                            for streamEvent in parsed.events {
                                continuation.yield(streamEvent)
                            }
                        }

                        if pendingJSON.count > 64_000_000 {
                            pendingJSON = String(pendingJSON.suffix(1_048_576))
                        }
                    }
                    if didStart {
                        if !pendingJSON.isEmpty {
                            for jsonObject in extractJSONObjectStrings(from: &pendingJSON) {
                                let parsed = try parseStreamChunk(jsonObject, codeExecutionState: &codeExecutionState)
                                if let usage = parsed.usage {
                                    pendingUsage = usage
                                }
                                for streamEvent in parsed.events {
                                    continuation.yield(streamEvent)
                                }
                            }
                        }
                        continuation.yield(.messageEnd(usage: pendingUsage))
                    }
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

    func validateAPIKey(_ key: String) async throws -> Bool {
        do {
            _ = try await getAccessToken()
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        Self.knownModels.map { makeModelInfo(id: $0.id, displayName: $0.name, contextWindow: $0.contextWindow) }
    }

    private static let knownModels: [(id: String, name: String, contextWindow: Int)] = [
        // Gemini 3
        ("gemini-3-pro-preview", "Gemini 3 Pro Preview", 1_048_576),
        ("gemini-3.1-pro-preview", "Gemini 3.1 Pro Preview", 1_048_576),
        ("gemini-3-flash-preview", "Gemini 3 Flash Preview", 1_048_576),
        ("gemini-3-pro-image-preview", "Gemini 3 Pro Image Preview", 65_536),
        ("gemini-3.1-flash-image-preview", "Gemini 3.1 Flash Image Preview", 131_072),
        ("gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash-Lite Preview", 1_048_576),
        // Gemini 2.5
        ("gemini-2.5-pro", "Gemini 2.5 Pro", 1_048_576),
        ("gemini-2.5-flash", "Gemini 2.5 Flash", 1_048_576),
        ("gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite", 1_048_576),
        ("gemini-2.5-flash-image", "Gemini 2.5 Flash Image", 32_768),
        // Gemini 2.0
        ("gemini-2.0-flash", "Gemini 2.0 Flash", 1_048_576),
        ("gemini-2.0-flash-lite", "Gemini 2.0 Flash Lite", 1_048_576),
        // Gemini 1.5
        ("gemini-1.5-pro", "Gemini 1.5 Pro", 2_097_152),
        ("gemini-1.5-flash", "Gemini 1.5 Flash", 1_048_576),
        // Image generation
        ("imagen-4.0-generate-preview-06-06", "Imagen 4.0", 0),
        ("imagen-3.0-generate-002", "Imagen 3.0", 0),
    ]

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        return tools.map(translateSingleTool)
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

    // MARK: - Private

    func getAccessToken() async throws -> String {
        if let cached = cachedToken, cached.expiresAt > Date().addingTimeInterval(60) {
            return cached.token
        }

        let jwt = try createJWT()
        let token = try await exchangeJWTForToken(jwt)
        cachedToken = (token: token.accessToken, expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)))
        return token.accessToken
    }

    private func createJWT() throws -> String {
        let header = JWTHeader(alg: "RS256", typ: "JWT")
        let now = Date()
        let claims = JWTClaims(
            iss: serviceAccountJSON.clientEmail,
            scope: "https://www.googleapis.com/auth/cloud-platform",
            aud: serviceAccountJSON.tokenURI,
            iat: Int(now.timeIntervalSince1970),
            exp: Int(now.addingTimeInterval(3600).timeIntervalSince1970)
        )

        let headerData = try JSONEncoder().encode(header)
        let claimsData = try JSONEncoder().encode(claims)

        let headerBase64 = headerData.base64URLEncodedString()
        let claimsBase64 = claimsData.base64URLEncodedString()

        let message = "\(headerBase64).\(claimsBase64)"
        let signature = try signWithPrivateKey(message: message, privateKey: serviceAccountJSON.privateKey)

        return "\(message).\(signature)"
    }

    private func signWithPrivateKey(message: String, privateKey: String) throws -> String {
        let key = try loadRSAPrivateKey(pem: privateKey)
        let messageData = Data(message.utf8)

        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256
        guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else {
            throw LLMError.invalidRequest(message: "RSA signing algorithm not supported")
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, algorithm, messageData as CFData, &error) as Data? else {
            let description = (error?.takeRetainedValue().localizedDescription) ?? "Unknown signing error"
            throw LLMError.invalidRequest(message: "Failed to sign JWT: \(description)")
        }

        return signature.base64URLEncodedString()
    }

    private func loadRSAPrivateKey(pem: String) throws -> SecKey {
        let pemBlock = try PEMBlock.parse(pem: pem)

        let pkcs1DER: Data
        switch pemBlock.label {
        case "RSA PRIVATE KEY":
            pkcs1DER = pemBlock.derBytes
        case "PRIVATE KEY":
            pkcs1DER = try PKCS8.extractPKCS1RSAPrivateKey(from: pemBlock.derBytes)
        default:
            if let extracted = try? PKCS8.extractPKCS1RSAPrivateKey(from: pemBlock.derBytes) {
                pkcs1DER = extracted
            } else {
                pkcs1DER = pemBlock.derBytes
            }
        }

        let keySizeInBits = try RSAKeyParsing.modulusSizeInBits(fromPKCS1RSAPrivateKey: pkcs1DER)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: keySizeInBits
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1DER as CFData, attributes as CFDictionary, &error) else {
            let description = (error?.takeRetainedValue().localizedDescription) ?? "Unknown key error"
            throw LLMError.invalidRequest(message: "Failed to load RSA private key: \(description)")
        }
        return key
    }

    private func exchangeJWTForToken(_ jwt: String) async throws -> TokenResponse {
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL(serviceAccountJSON.tokenURI),
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body.data(using: .utf8)
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool,
        accessToken: String
    ) throws -> URLRequest {
        let method = streaming ? "streamGenerateContent" : "generateContent"
        let endpoint = "\(baseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(location)/publishers/google/models/\(modelID):\(method)"
        let timeout = requestTimeoutInterval(for: modelID, controls: controls)

        let systemText: String? = messages
            .first(where: { $0.role == .system })?
            .content
            .compactMap { part in
                if case .text(let text) = part { return text }
                return nil
            }
            .first

        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let supportsNativePDF = allowNativePDF && self.supportsNativePDF(modelID)

        var body: [String: Any] = [
            "contents": try messages.filter { $0.role != .system }.map { try translateMessage($0, supportsNativePDF: supportsNativePDF) },
            "generationConfig": buildGenerationConfig(controls, modelID: modelID)
        ]

        let explicitCachedContent = (controls.contextCache?.mode == .explicit)
            ? normalizedTrimmedString(controls.contextCache?.cachedContentName)
            : nil

        if explicitCachedContent == nil, let systemText, !systemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["systemInstruction"] = [
                "parts": [
                    ["text": systemText]
                ]
            ]
        }

        if let cachedContent = explicitCachedContent {
            body["cachedContent"] = cachedContent
        }

        var toolArray: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
            toolArray.append(["googleSearch": [:]])
        }

        if controls.codeExecution?.enabled == true, supportsCodeExecution(modelID) {
            toolArray.append(["codeExecution": [:]])
        }

        if controls.googleMaps?.enabled == true, supportsGoogleMaps(modelID) {
            var mapsConfig: [String: Any] = [:]
            if controls.googleMaps?.enableWidget == true {
                mapsConfig["enableWidget"] = true
            }
            toolArray.append(["googleMaps": mapsConfig])
        }

        if supportsFunctionCalling(modelID), !tools.isEmpty,
           let functionDeclarations = translateTools(tools) as? [[String: Any]] {
            toolArray.append(["functionDeclarations": functionDeclarations])
        }

        if !toolArray.isEmpty {
            body["tools"] = toolArray
        }

        if controls.googleMaps?.enabled == true, supportsGoogleMaps(modelID) {
            var toolConfig = body["toolConfig"] as? [String: Any] ?? [:]
            var retrievalConfig: [String: Any] = [:]

            if let lat = controls.googleMaps?.latitude,
               let lng = controls.googleMaps?.longitude {
                retrievalConfig["latLng"] = [
                    "latitude": lat,
                    "longitude": lng
                ]
            }

            if let lang = controls.googleMaps?.languageCode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !lang.isEmpty {
                retrievalConfig["languageCode"] = lang
            }

            if !retrievalConfig.isEmpty {
                toolConfig["retrievalConfig"] = retrievalConfig
                body["toolConfig"] = toolConfig
            }
        }

        if !controls.providerSpecific.isEmpty {
            deepMergeDictionary(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
        }

        return try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL(endpoint),
            timeoutSeconds: timeout,
            headers: vertexHeaders(accessToken: accessToken),
            body: body
        )
    }

    func vertexHeaders(accessToken: String, accept: String? = nil, contentType: String? = nil) -> [String: String] {
        var headers: [String: String] = ["Authorization": "Bearer \(accessToken)"]
        if let accept {
            headers["Accept"] = accept
        }
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return headers
    }

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        GeminiModelConstants.isImageGenerationModel(modelID)
    }

    private func supportsFunctionCalling(_ modelID: String) -> Bool {
        !isImageGenerationModel(modelID)
    }

    private func supportsWebSearch(_ modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    private func supportsCodeExecution(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: modelID)
    }

    private func supportsGoogleMaps(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: modelID)
    }

    private func supportsImageSize(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower == "gemini-3-pro-image-preview" || lower == "gemini-3.1-flash-image-preview"
    }

    private func supportsImageSize(_ modelID: String, imageSize: ImageOutputSize) -> Bool {
        guard supportsImageSize(modelID) else { return false }
        let lower = modelID.lowercased()
        if lower == "gemini-3-pro-image-preview" {
            return imageSize != .size512px
        }
        return true
    }

    private func requestTimeoutInterval(for modelID: String, controls: GenerationControls) -> TimeInterval? {
        guard isAnyImageGenerationModel(modelID) else {
            return nil
        }

        switch controls.imageGeneration?.imageSize {
        case .size512px:
            return VertexImageRequestTimeout.size1KSeconds
        case .size4K:
            return VertexImageRequestTimeout.size4KSeconds
        case .size2K:
            return VertexImageRequestTimeout.size2KSeconds
        case .size1K:
            return VertexImageRequestTimeout.size1KSeconds
        case .none:
            return VertexImageRequestTimeout.defaultSeconds
        }
    }

    private func isAnyImageGenerationModel(_ modelID: String) -> Bool {
        isImageGenerationModel(modelID)
    }

    private func supportsThinking(_ modelID: String) -> Bool {
        // Gemini 2.5 Flash Image does not support thinking.
        modelID.lowercased() != "gemini-2.5-flash-image"
    }

    private func supportsThinkingConfig(_ modelID: String) -> Bool {
        // Gemini 3 Pro Image supports thinking capability but doesn't accept
        // public thinkingConfig controls in generateContent.
        let lower = modelID.lowercased()
        return supportsThinking(modelID)
            && lower != "gemini-3-pro-image-preview"
            && lower != "gemini-3.1-flash-image-preview"
    }

    private func supportsThinkingLevel(_ modelID: String) -> Bool {
        supportsThinkingConfig(modelID)
    }

    private func makeModelInfo(id: String, displayName: String, contextWindow: Int) -> ModelInfo {
        let lower = id.lowercased()

        var caps: ModelCapability = []

        let imageModel = isImageGenerationModel(id)
        let geminiModel = GeminiModelConstants.knownModelIDs.contains(lower)

        if !imageModel {
            caps.insert(.streaming)
            caps.insert(.toolCalling)
            caps.insert(.promptCaching)
        }

        if geminiModel || imageModel {
            caps.insert(.vision)
        }

        if geminiModel && !imageModel {
            caps.insert(.audio)
        }

        var reasoningConfig: ModelReasoningConfig?
        if supportsThinking(id) && geminiModel {
            caps.insert(.reasoning)
            if GeminiModelConstants.gemini25TextModelIDs.contains(lower) {
                reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: 2048)
            } else if lower == "gemini-3.1-flash-lite-preview" {
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .minimal)
            } else if supportsThinkingConfig(id) {
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            } else {
                reasoningConfig = nil
            }
        }

        if supportsNativePDF(id) {
            caps.insert(.nativePDF)
        }

        if ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: id) {
            caps.insert(.codeExecution)
        }

        if imageModel {
            caps.insert(.imageGeneration)
        }

        if GoogleVideoGenerationCore.isVideoGenerationModel(id) {
            caps.insert(.videoGeneration)
        }

        return ModelInfo(
            id: id,
            name: displayName,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            isEnabled: true
        )
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

        if supportsThinkingConfig(modelID), let reasoning = controls.reasoning, reasoning.enabled {
            var thinkingConfig: [String: Any] = [
                "includeThoughts": true
            ]

            if let effort = reasoning.effort, supportsThinkingLevel(modelID) {
                let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                    effort,
                    for: .vertexai,
                    modelID: modelID
                )
                thinkingConfig["thinkingLevel"] = mapEffortToVertexLevel(normalizedEffort, modelID: modelID)
            } else if let budget = reasoning.budgetTokens {
                thinkingConfig["thinkingBudget"] = budget
            }

            config["thinkingConfig"] = thinkingConfig
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
            if let imageSize = imageControls?.imageSize, supportsImageSize(modelID, imageSize: imageSize) {
                imageConfig["imageSize"] = imageSize.rawValue
            }
            if let person = imageControls?.vertexPersonGeneration {
                imageConfig["personGeneration"] = person.rawValue
            }

            var imageOutputOptions: [String: Any] = [:]
            if let mime = imageControls?.vertexOutputMIMEType {
                imageOutputOptions["mimeType"] = mime.rawValue
            }
            if let quality = imageControls?.vertexCompressionQuality {
                // Vertex docs define this as JPEG quality [0, 100].
                imageOutputOptions["compressionQuality"] = min(100, max(0, quality))
            }
            if !imageOutputOptions.isEmpty {
                imageConfig["imageOutputOptions"] = imageOutputOptions
            }

            if !imageConfig.isEmpty {
                config["imageConfig"] = imageConfig
            }
        }

        return config
    }

    private func mapEffortToVertexLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        GeminiModelConstants.mapEffortToThinkingLevel(effort, for: .vertexai, modelID: modelID)
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        GeminiModelConstants.supportsVertexNativePDF(modelID)
    }

    // Content translation and stream parsing are in VertexAIContentTranslation.swift

    var baseURL: String {
        if location == "global" {
            return "https://aiplatform.googleapis.com/v1"
        }
        return "https://\(location)-aiplatform.googleapis.com/v1"
    }

    private var cachedContentsCollectionEndpoint: String {
        "\(baseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(location)/cachedContents"
    }

    private func cachedContentEndpoint(for rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("projects/") {
            return "\(baseURL)/\(trimmed)"
        }
        return "\(cachedContentsCollectionEndpoint)/\(trimmed)"
    }

    var location: String {
        serviceAccountJSON.location ?? "global"
    }
}

private enum VertexImageRequestTimeout {
    static let defaultSeconds: TimeInterval = 600
    static let size1KSeconds: TimeInterval = 360
    static let size2KSeconds: TimeInterval = 720
    static let size4KSeconds: TimeInterval = 1_200
}

// JWT types, PEM/DER parsing, and base64URL encoding are in VertexAIJWTSupport.swift
// Response types are defined in VertexAIAdapterResponseTypes.swift
