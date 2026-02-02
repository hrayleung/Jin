import Foundation
import Security

actor VertexAIAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

    private let networkManager: NetworkManager
    private let serviceAccountJSON: ServiceAccountCredentials
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

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let token = try await getAccessToken()
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

                    for try await line in lineStream {
                        guard let data = normalizeVertexStreamLine(line) else { continue }

                        if !didStart {
                            didStart = true
                            continuation.yield(.messageStart(id: UUID().uuidString))
                        }

                        pendingJSON += data
                        pendingJSON += "\n"

                        for jsonObject in extractJSONObjectStrings(from: &pendingJSON) {
                            for streamEvent in try parseStreamEvents(jsonObject) {
                                continuation.yield(streamEvent)
                            }
                        }

                        if pendingJSON.count > 1_000_000 {
                            pendingJSON = String(pendingJSON.suffix(32_768))
                        }
                    }
                    if didStart {
                        if !pendingJSON.isEmpty {
                            for jsonObject in extractJSONObjectStrings(from: &pendingJSON) {
                                for streamEvent in try parseStreamEvents(jsonObject) {
                                    continuation.yield(streamEvent)
                                }
                            }
                        }
                        continuation.yield(.messageEnd(usage: nil))
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
        [
            ModelInfo(
                id: "gemini-3-pro-preview",
                name: "Gemini 3 Pro (Preview)",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(
                    type: .effort,
                    defaultEffort: .medium
                )
            ),
            ModelInfo(
                id: "gemini-3-flash-preview",
                name: "Gemini 3 Flash (Preview)",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(
                    type: .effort,
                    defaultEffort: .medium
                )
            ),
            ModelInfo(
                id: "gemini-2.5-pro",
                name: "Gemini 2.5 Pro",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 1_048_576,
                reasoningConfig: ModelReasoningConfig(
                    type: .budget,
                    defaultBudget: 2048
                )
            )
        ]
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        return tools.map(translateSingleTool)
    }

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        // Vertex AI function declarations accept JSON schema via parametersJsonSchema.
        var properties: [String: Any] = [:]
        for (key, prop) in tool.parameters.properties {
            properties[key] = prop.toDictionary()
        }

        return [
            "name": tool.name,
            "description": tool.description,
            "parametersJsonSchema": [
                "type": tool.parameters.type,
                "properties": properties,
                "required": tool.parameters.required
            ]
        ]
    }

    // MARK: - Private

    private func getAccessToken() async throws -> String {
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
        let endpoint = "\(baseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(location)/publishers/google/models/\(modelID):streamGenerateContent"
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

        var body: [String: Any] = [
            "contents": messages.filter { $0.role != .system }.map(translateMessage),
            "generationConfig": buildGenerationConfig(controls)
        ]

        if let systemText, !systemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["systemInstruction"] = [
                "parts": [
                    ["text": systemText]
                ]
            ]
        }

        var toolArray: [[String: Any]] = []

        if controls.webSearch?.enabled == true {
            toolArray.append(["googleSearch": [:]])
        }

        if !tools.isEmpty, let functionDeclarations = translateTools(tools) as? [[String: Any]] {
            toolArray.append(["functionDeclarations": functionDeclarations])
        }

        if !toolArray.isEmpty {
            body["tools"] = toolArray
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildGenerationConfig(_ controls: GenerationControls) -> [String: Any] {
        var config: [String: Any] = [:]

        if let temperature = controls.temperature {
            config["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            config["maxOutputTokens"] = maxTokens
        }
        if let topP = controls.topP {
            config["topP"] = topP
        }

        if let reasoning = controls.reasoning, reasoning.enabled {
            var thinkingConfig: [String: Any] = [
                "includeThoughts": true
            ]

            if let effort = reasoning.effort {
                thinkingConfig["thinkingLevel"] = mapEffortToVertexLevel(effort)
            } else if let budget = reasoning.budgetTokens {
                thinkingConfig["thinkingBudget"] = budget
            }

            config["thinkingConfig"] = thinkingConfig
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

    private func translateMessage(_ message: Message) -> [String: Any] {
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
                case .file(let file):
                    let extracted = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let text: String
                    if let extracted, !extracted.isEmpty {
                        text = "Attachment: \(file.filename) (\(file.mimeType))\n\n\(extracted)"
                    } else {
                        text = "Attachment: \(file.filename) (\(file.mimeType))"
                    }
                    parts.append(["text": text])
                case .thinking, .redactedThinking, .audio:
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

    private func parseStreamEvents(_ data: String) throws -> [StreamEvent] {
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = trimmed.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if trimmed.hasPrefix("[") {
            let responses = try decoder.decode([GenerateContentResponse].self, from: jsonData)
            return responses.flatMap(eventsFromVertexResponse)
        }

        let response = try decoder.decode(GenerateContentResponse.self, from: jsonData)
        return eventsFromVertexResponse(response)
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
            }
        }

        return events
    }

    private var baseURL: String {
        if location == "global" {
            return "https://aiplatform.googleapis.com/v1"
        }
        return "https://\(location)-aiplatform.googleapis.com/v1"
    }

    private var location: String {
        serviceAccountJSON.location ?? "global"
    }
}

// MARK: - Service Account Types

struct ServiceAccountCredentials: Codable {
    let type: String
    let projectID: String
    let privateKeyID: String
    let privateKey: String
    let clientEmail: String
    let clientID: String
    let authURI: String
    let tokenURI: String
    let authProviderX509CertURL: String
    let clientX509CertURL: String
    let location: String?

    enum CodingKeys: String, CodingKey {
        case type
        case projectID = "project_id"
        case privateKeyID = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientID = "client_id"
        case authURI = "auth_uri"
        case tokenURI = "token_uri"
        case authProviderX509CertURL = "auth_provider_x509_cert_url"
        case clientX509CertURL = "client_x509_cert_url"
        case location
    }
}

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
