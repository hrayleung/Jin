import Foundation
import Security

actor VertexAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF, .imageGeneration, .videoGeneration]

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
        var request = URLRequest(url: URL(string: cachedContentsCollectionEndpoint)!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(VertexCachedContentsListResponse.self, from: data)
        return response.cachedContents ?? []
    }

    func getCachedContent(named name: String) async throws -> CachedContentResource {
        let token = try await getAccessToken()
        var request = URLRequest(url: URL(string: cachedContentEndpoint(for: name))!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

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
        var request = URLRequest(url: URL(string: cachedContentsCollectionEndpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

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

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CachedContentResource.self, from: data)
    }

    func deleteCachedContent(named name: String) async throws {
        let token = try await getAccessToken()
        var request = URLRequest(url: URL(string: cachedContentEndpoint(for: name))!)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
            Task {
                do {
                    var didStart = false
                    var pendingJSON = ""
                    var pendingUsage: Usage?

                    for try await line in lineStream {
                        guard let data = normalizeVertexStreamLine(line) else { continue }

                        if !didStart {
                            didStart = true
                            continuation.yield(.messageStart(id: UUID().uuidString))
                        }

                        pendingJSON += data
                        pendingJSON += "\n"

                        for jsonObject in extractJSONObjectStrings(from: &pendingJSON) {
                            let parsed = try parseStreamChunk(jsonObject)
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
                                let parsed = try parseStreamChunk(jsonObject)
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
        let token = try await getAccessToken()

        var pageToken: String?
        var models: [ModelInfo] = []
        var seenIDs: Set<String> = []

        while true {
            var components = URLComponents(string: "\(baseURL)/publishers/google/models")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "listAllVersions", value: "true")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw LLMError.invalidRequest(message: "Invalid Vertex models URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            let (data, _) = try await networkManager.sendRequest(request)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(VertexListModelsResponse.self, from: data)

            for model in response.items {
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
        var request = URLRequest(url: URL(string: serviceAccountJSON.tokenURI)!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
        request.httpBody = body.data(using: .utf8)

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
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

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
            "contents": messages.filter { $0.role != .system }.map { translateMessage($0, supportsNativePDF: supportsNativePDF) },
            "generationConfig": buildGenerationConfig(controls, modelID: modelID)
        ]

        let explicitCachedContent = (controls.contextCache?.mode == .explicit)
            ? normalizedContextCacheString(controls.contextCache?.cachedContentName)
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

        if controls.webSearch?.enabled == true, supportsGoogleSearch(modelID) {
            toolArray.append(["googleSearch": [:]])
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

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower.contains("-image")
    }

    private func supportsFunctionCalling(_ modelID: String) -> Bool {
        !isImageGenerationModel(modelID)
    }

    private func supportsGoogleSearch(_ modelID: String) -> Bool {
        // Gemini 2.5 Flash Image does not support grounding with Google Search.
        !modelID.lowercased().contains("gemini-2.5-flash-image")
    }

    private func supportsImageSize(_ modelID: String) -> Bool {
        modelID.lowercased().contains("gemini-3-pro-image")
    }

    private func supportsThinking(_ modelID: String) -> Bool {
        // Gemini 2.5 Flash Image does not support thinking.
        !modelID.lowercased().contains("gemini-2.5-flash-image")
    }

    private func supportsThinkingConfig(_ modelID: String) -> Bool {
        // Gemini 3 Pro Image supports thinking capability but doesn't accept
        // public thinkingConfig controls in generateContent.
        supportsThinking(modelID) && !modelID.lowercased().contains("gemini-3-pro-image")
    }

    private func supportsThinkingLevel(_ modelID: String) -> Bool {
        supportsThinkingConfig(modelID)
    }

    private func makeModelInfo(from model: VertexListModelsResponse.PublisherModel) -> ModelInfo {
        let id = normalizedVertexModelID(from: model.name)
        let lower = id.lowercased()

        let methods = Set((model.supportedGenerationMethods ?? model.supportedActions ?? []).map { $0.lowercased() })
        let supportsGenerateContent = methods.contains("generatecontent") || methods.contains("streamgeneratecontent") || methods.isEmpty
        let supportsStream = methods.contains("streamgeneratecontent") || methods.isEmpty

        var caps: ModelCapability = []

        if supportsStream {
            caps.insert(.streaming)
        }

        let imageModel = isImageGenerationModel(id) || lower.contains("imagen")
        let geminiModel = lower.contains("gemini")

        if supportsGenerateContent && !imageModel {
            caps.insert(.toolCalling)
        }

        if geminiModel || imageModel || lower.contains("vision") || lower.contains("multimodal") {
            caps.insert(.vision)
        }

        if supportsGenerateContent && geminiModel && !imageModel {
            caps.insert(.audio)
        }

        var reasoningConfig: ModelReasoningConfig?
        if supportsThinking(id) && (geminiModel || lower.contains("reason") || lower.contains("thinking")) {
            caps.insert(.reasoning)
            if lower.contains("gemini-2.5") {
                reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: 2048)
            } else if supportsThinkingConfig(id) {
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            } else {
                reasoningConfig = nil
            }
        }

        if supportsNativePDF(id) {
            caps.insert(.nativePDF)
        }

        if !imageModel {
            caps.insert(.promptCaching)
        }

        if imageModel {
            caps.insert(.imageGeneration)
        }

        if GoogleVideoGenerationCore.isVideoGenerationModel(id) {
            caps.insert(.videoGeneration)
        }

        return ModelInfo(
            id: id,
            name: model.displayName ?? id,
            capabilities: caps,
            contextWindow: model.inputTokenLimit ?? 1_048_576,
            reasoningConfig: reasoningConfig,
            isEnabled: true
        )
    }

    private func normalizedVertexModelID(from name: String) -> String {
        let lower = name.lowercased()
        if let range = lower.range(of: "/models/") {
            return String(name[range.upperBound...])
        }
        return name
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
                thinkingConfig["thinkingLevel"] = mapEffortToVertexLevel(effort)
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
            if supportsImageSize(modelID), let imageSize = imageControls?.imageSize {
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

    private func mapEffortToVertexLevel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return "MINIMAL"
        case .minimal:
            return "MINIMAL"
        case .low:
            return "LOW"
        case .medium:
            return "MEDIUM"
        case .high:
            return "HIGH"
        case .xhigh:
            return "HIGH"
        }
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        // Gemini 3 series supports native PDF with free text extraction
        return modelID.lowercased().contains("gemini-3") && !isImageGenerationModel(modelID)
    }

    private func normalizedContextCacheString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func translateMessage(_ message: Message, supportsNativePDF: Bool) -> [String: Any] {
        // Vertex AI Content.role is limited to 'user' or 'model'. System instructions are sent separately.
        let role: String = (message.role == .assistant) ? "model" : "user"

        var parts: [[String: Any]] = []

        if message.role != .tool {
            // Preserve thoughts first for assistant turns.
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

            // User-visible content.
            for part in message.content {
                switch part {
                case .text(let text):
                    parts.append(["text": text])
                case .image(let image):
                    if let data = image.data {
                        parts.append([
                            "inlineData": [
                                "mimeType": image.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    } else if let url = image.url, url.isFileURL, let data = try? Data(contentsOf: url) {
                        parts.append([
                            "inlineData": [
                                "mimeType": image.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    }
                case .video(let video):
                    if let data = video.data {
                        parts.append([
                            "inlineData": [
                                "mimeType": video.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    } else if let url = video.url, url.isFileURL, let data = try? Data(contentsOf: url) {
                        parts.append([
                            "inlineData": [
                                "mimeType": video.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    }
                case .audio(let audio):
                    if let data = audio.data {
                        parts.append([
                            "inlineData": [
                                "mimeType": audio.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    } else if let url = audio.url, url.isFileURL, let data = try? Data(contentsOf: url) {
                        parts.append([
                            "inlineData": [
                                "mimeType": audio.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    }
                case .file(let file):
                    // Native PDF support for Gemini 3+ with free text extraction
                    if supportsNativePDF && file.mimeType == "application/pdf" {
                        // Load PDF data from file URL or use existing data
                        let pdfData: Data?
                        if let data = file.data {
                            pdfData = data
                        } else if let url = file.url, url.isFileURL {
                            pdfData = try? Data(contentsOf: url)
                        } else {
                            pdfData = nil
                        }

                        if let pdfData = pdfData {
                            parts.append([
                                "inlineData": [
                                    "mimeType": "application/pdf",
                                    "data": pdfData.base64EncodedString()
                                ]
                            ])
                            // Skip fallback - PDF uploaded successfully
                            continue
                        }
                    }

                    // Fallback to text extraction for non-Gemini-3 or non-PDF files
                    let text = AttachmentPromptRenderer.fallbackText(for: file)
                    parts.append(["text": text])
                case .thinking, .redactedThinking:
                    break
                }
            }
        }

        // Function calls (model output) are appended to assistant turns.
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

        // Function responses are provided as user turns.
        if message.role == .tool, let toolResults = message.toolResults {
            for result in toolResults {
                guard let toolName = result.toolName else { continue }
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
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return [
            "role": role,
            "parts": parts
        ]
    }

    private func normalizeVertexStreamLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("event:") {
            return nil
        }

        // SSE comment / keepalive lines.
        if trimmed.hasPrefix(":") {
            return nil
        }

        if trimmed.hasPrefix("data:") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 5)
            let data = trimmed[start...].trimmingCharacters(in: .whitespacesAndNewlines)
            return data.isEmpty ? nil : String(data)
        }

        return trimmed
    }

    private func parseStreamChunk(_ data: String) throws -> (events: [StreamEvent], usage: Usage?) {
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = trimmed.data(using: .utf8) else {
            return ([], nil)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if trimmed.hasPrefix("[") {
            let responses = try decoder.decode([GenerateContentResponse].self, from: jsonData)
            var events: [StreamEvent] = []
            var usage: Usage?
            for response in responses {
                events.append(contentsOf: eventsFromVertexResponse(response))
                if let parsed = usageFromVertexResponse(response) {
                    usage = parsed
                }
            }
            return (events, usage)
        }

        let response = try decoder.decode(GenerateContentResponse.self, from: jsonData)
        return (eventsFromVertexResponse(response), usageFromVertexResponse(response))
    }

    private func extractJSONObjectStrings(from buffer: inout String) -> [String] {
        var results: [String] = []
        var braceDepth = 0
        var isInString = false
        var isEscaping = false
        var objectStart: String.Index?
        var lastConsumedEnd: String.Index?

        var index = buffer.startIndex
        while index < buffer.endIndex {
            let ch = buffer[index]

            if isInString {
                if isEscaping {
                    isEscaping = false
                } else if ch == "\\" {
                    isEscaping = true
                } else if ch == "\"" {
                    isInString = false
                }
            } else {
                if ch == "\"" {
                    isInString = true
                } else if ch == "{" {
                    if braceDepth == 0 {
                        objectStart = index
                    }
                    braceDepth += 1
                } else if ch == "}" {
                    if braceDepth > 0 {
                        braceDepth -= 1
                        if braceDepth == 0, let start = objectStart {
                            let end = buffer.index(after: index)
                            results.append(String(buffer[start..<end]))
                            lastConsumedEnd = end
                            objectStart = nil
                        }
                    }
                }
            }

            index = buffer.index(after: index)
        }

        if let end = lastConsumedEnd {
            buffer.removeSubrange(buffer.startIndex..<end)
        }

        // Drop separators between objects / arrays to keep parsing stable.
        while let first = buffer.first,
              first.isWhitespace || first == "," || first == "[" || first == "]" {
            buffer.removeFirst()
        }

        return results
    }

    private func eventsFromVertexResponse(_ response: GenerateContentResponse) -> [StreamEvent] {
        var events: [StreamEvent] = []

        if let candidate = response.candidates?.first,
           let content = candidate.content {
            for part in content.parts ?? [] {
                if let text = part.text {
                    if part.thought == true {
                        events.append(.thinkingDelta(.thinking(textDelta: text, signature: part.thoughtSignature)))
                    } else {
                        events.append(.contentDelta(.text(text)))
                    }
                }

                if let functionCall = part.functionCall {
                    let id = UUID().uuidString
                    let toolCall = ToolCall(
                        id: id,
                        name: functionCall.name,
                        arguments: functionCall.args ?? [:],
                        signature: part.thoughtSignature
                    )
                    events.append(.toolCallStart(toolCall))
                    events.append(.toolCallEnd(toolCall))
                }

                if let inline = part.inlineData,
                   let base64 = inline.data,
                   let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                    let mimeType = inline.mimeType ?? "image/png"
                    if mimeType.lowercased().hasPrefix("image/") {
                        events.append(.contentDelta(.image(ImageContent(mimeType: mimeType, data: data))))
                    }
                }
            }
        }

        return events
    }

    private func usageFromVertexResponse(_ response: GenerateContentResponse) -> Usage? {
        guard let usageMetadata = response.usageMetadata else { return nil }
        guard let input = usageMetadata.promptTokenCount,
              let output = usageMetadata.candidatesTokenCount else {
            return nil
        }

        return Usage(
            inputTokens: input,
            outputTokens: output,
            thinkingTokens: nil,
            cachedTokens: usageMetadata.cachedContentTokenCount
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

private struct VertexListModelsResponse: Codable {
    let publisherModels: [PublisherModel]?
    let models: [PublisherModel]?
    let nextPageToken: String?

    var items: [PublisherModel] {
        if let publisherModels {
            return publisherModels
        }
        return models ?? []
    }

    struct PublisherModel: Codable {
        let name: String
        let displayName: String?
        let supportedActions: [String]?
        let supportedGenerationMethods: [String]?
        let inputTokenLimit: Int?
        let outputTokenLimit: Int?
        let versionID: String?
        let description: String?
    }
}

private struct VertexCachedContentsListResponse: Codable {
    let cachedContents: [VertexAIAdapter.CachedContentResource]?
    let nextPageToken: String?
}

// MARK: - Service Account Types

// MARK: - JWT Types

private struct JWTHeader: Codable {
    let alg: String
    let typ: String
}

private struct JWTClaims: Codable {
    let iss: String
    let scope: String
    let aud: String
    let iat: Int
    let exp: Int
}

private struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Response Types

    private struct GenerateContentResponse: Codable {
        let candidates: [Candidate]?
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

        struct UsageMetadata: Codable {
            let promptTokenCount: Int?
            let candidatesTokenCount: Int?
            let totalTokenCount: Int?
            let cachedContentTokenCount: Int?
        }
    }

// MARK: - Extensions

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - RSA / PEM Helpers

private struct PEMBlock {
    let label: String
    let derBytes: Data

    static func parse(pem: String) throws -> PEMBlock {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMError.invalidRequest(message: "Empty private key")
        }

        let lines = trimmed
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let beginIndex = lines.firstIndex(where: { $0.hasPrefix("-----BEGIN ") }) else {
            guard let der = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters) else {
                throw LLMError.invalidRequest(message: "Invalid private key format (expected PEM)")
            }
            return PEMBlock(label: "UNKNOWN", derBytes: der)
        }

        guard let endIndex = lines[(beginIndex + 1)...].firstIndex(where: { $0.hasPrefix("-----END ") }) else {
            throw LLMError.invalidRequest(message: "Invalid private key format (missing PEM end marker)")
        }

        let beginLine = lines[beginIndex]
        let endLine = lines[endIndex]

        guard let beginLabel = parseLabel(line: beginLine, prefix: "-----BEGIN ") else {
            throw LLMError.invalidRequest(message: "Invalid PEM begin marker")
        }
        guard let endLabel = parseLabel(line: endLine, prefix: "-----END ") else {
            throw LLMError.invalidRequest(message: "Invalid PEM end marker")
        }
        guard beginLabel == endLabel else {
            throw LLMError.invalidRequest(message: "Mismatched PEM markers (\(beginLabel) vs \(endLabel))")
        }

        let base64Content = lines[(beginIndex + 1)..<endIndex].joined()
        guard let der = Data(base64Encoded: base64Content, options: .ignoreUnknownCharacters) else {
            throw LLMError.invalidRequest(message: "Invalid PEM base64 content")
        }

        return PEMBlock(label: beginLabel, derBytes: der)
    }

    private static func parseLabel(line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix), line.hasSuffix("-----") else { return nil }
        let start = line.index(line.startIndex, offsetBy: prefix.count)
        let end = line.index(line.endIndex, offsetBy: -5)
        return String(line[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum PKCS8 {
    private static let rsaAlgorithmOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    static func extractPKCS1RSAPrivateKey(from pkcs8DER: Data) throws -> Data {
        var reader = DERReader(data: pkcs8DER)
        let outer = try reader.readTLV(expectedTag: 0x30)

        var seq = DERReader(data: outer.value)
        _ = try seq.readTLV(expectedTag: 0x02) // version

        let algorithmIdentifier = try seq.readTLV(expectedTag: 0x30)
        var algReader = DERReader(data: algorithmIdentifier.value)
        let oid = try algReader.readTLV(expectedTag: 0x06)
        guard Array(oid.value) == rsaAlgorithmOID else {
            throw LLMError.invalidRequest(message: "Unsupported private key algorithm (expected RSA)")
        }

        // Optional NULL parameters; ignore if present.
        _ = try? algReader.readTLV(expectedTag: 0x05)

        let privateKey = try seq.readTLV(expectedTag: 0x04) // OCTET STRING wrapping RSAPrivateKey (PKCS#1)
        return privateKey.value
    }
}

private enum RSAKeyParsing {
    static func modulusSizeInBits(fromPKCS1RSAPrivateKey pkcs1DER: Data) throws -> Int {
        var reader = DERReader(data: pkcs1DER)
        let outer = try reader.readTLV(expectedTag: 0x30)

        var seq = DERReader(data: outer.value)
        _ = try seq.readTLV(expectedTag: 0x02) // version
        let modulus = try seq.readTLV(expectedTag: 0x02)

        var modulusBytes = [UInt8](modulus.value)
        while modulusBytes.first == 0, modulusBytes.count > 1 {
            modulusBytes.removeFirst()
        }
        guard !modulusBytes.isEmpty else {
            throw LLMError.invalidRequest(message: "Invalid RSA private key (missing modulus)")
        }

        return modulusBytes.count * 8
    }
}

private struct DERReader {
    private let bytes: [UInt8]
    private var index: Int = 0

    init(data: Data) {
        self.bytes = [UInt8](data)
    }

    mutating func readTLV(expectedTag: UInt8? = nil) throws -> (tag: UInt8, value: Data) {
        let tag = try readByte()
        let length = try readLength()
        guard index + length <= bytes.count else {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (length out of bounds)")
        }
        let value = Data(bytes[index..<(index + length)])
        index += length

        if let expectedTag, tag != expectedTag {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (unexpected tag \(tag))")
        }
        return (tag: tag, value: value)
    }

    private mutating func readByte() throws -> UInt8 {
        guard index < bytes.count else {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (unexpected end)")
        }
        let byte = bytes[index]
        index += 1
        return byte
    }

    private mutating func readLength() throws -> Int {
        let first = try readByte()
        if first & 0x80 == 0 {
            return Int(first)
        }

        let lengthByteCount = Int(first & 0x7F)
        guard lengthByteCount > 0 else {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (indefinite length)")
        }
        guard index + lengthByteCount <= bytes.count else {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (length out of bounds)")
        }

        var length = 0
        for _ in 0..<lengthByteCount {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }
}
