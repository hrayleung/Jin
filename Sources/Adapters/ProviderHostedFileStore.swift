import Foundation
import CryptoKit
import Alamofire

struct HostedProviderFileReference: Sendable {
    let id: String
    let uri: String?
    let mimeType: String
    let displayName: String
}

let anthropicHostedDocumentMIMETypes: Set<String> = [
    "application/pdf",
    "text/plain",
    "text/markdown",
    "text/html",
    "text/csv",
    "text/tab-separated-values",
    "application/json",
    "application/xml"
]

let anthropicCodeExecutionUploadMIMETypes: Set<String> = [
    "text/plain",
    "text/markdown",
    "text/csv",
    "text/tab-separated-values",
    "application/json",
    "application/xml",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-excel"
]

let anthropicFilesAPIBetaHeader = "files-api-2025-04-14"

let googleHostedPromptFileMIMETypes: Set<String> = [
    "application/pdf",
    "text/plain",
    "text/markdown",
    "text/html",
    "text/csv",
    "text/tab-separated-values",
    "application/json",
    "application/xml"
]

func shouldFallbackFromHostedFileUpload(_ error: Error) -> Bool {
    guard let llmError = error as? LLMError,
          case .providerError(let code, _) = llmError else {
        return false
    }

    switch code {
    case "404", "405", "415", "501":
        return true
    default:
        return false
    }
}

actor ProviderHostedFileStore {
    static let shared = ProviderHostedFileStore()

    private struct UploadCacheKey: Hashable {
        let providerType: ProviderType
        let providerScope: String
        let filename: String
        let mimeType: String
        let digest: String
    }

    private struct FilePayload: Sendable {
        let filename: String
        let mimeType: String
        let data: Data
    }

    private struct OpenAIFileResponse: Decodable {
        let id: String
        let filename: String?
    }

    private struct AnthropicFileResponse: Decodable {
        let id: String
        let filename: String?
        let mimeType: String?
    }

    private struct GeminiFileEnvelope: Decodable {
        let file: GeminiFileResource
    }

    private struct GeminiFileResource: Decodable {
        let name: String
        let uri: String?
        let mimeType: String?
        let displayName: String?
        let state: String?
    }

    private var cache: [UploadCacheKey: HostedProviderFileReference] = [:]
    private var inFlight: [UploadCacheKey: Task<HostedProviderFileReference, Error>] = [:]

    func uploadOpenAIFile(
        file: FileContent,
        baseURL: String,
        apiKey: String,
        networkManager: NetworkManager
    ) async throws -> HostedProviderFileReference? {
        guard let payload = try payload(for: file) else { return nil }
        let key = makeCacheKey(
            providerType: .openai,
            providerScope: providerScope(
                providerType: .openai,
                baseURL: baseURL,
                credential: apiKey
            ),
            payload: payload
        )

        return try await cachedUpload(for: key) {
            let request = try NetworkRequestFactory.makeMultipartRequest(
                url: validatedURL("\(baseURL)/files"),
                headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey)
            ) { formData in
                formData.append(Data("user_data".utf8), withName: "purpose")
                formData.append(
                    payload.data,
                    withName: "file",
                    fileName: payload.filename,
                    mimeType: payload.mimeType
                )
            }

            let (data, _) = try await networkManager.sendRequest(request)
            let response = try JSONDecoder().decode(OpenAIFileResponse.self, from: data)

            return HostedProviderFileReference(
                id: response.id,
                uri: nil,
                mimeType: payload.mimeType,
                displayName: response.filename ?? payload.filename
            )
        }
    }

    func uploadAnthropicFile(
        file: FileContent,
        baseURL: String,
        apiKey: String,
        anthropicVersion: String,
        networkManager: NetworkManager
    ) async throws -> HostedProviderFileReference? {
        guard let payload = try payload(for: file) else { return nil }
        let key = makeCacheKey(
            providerType: .anthropic,
            providerScope: providerScope(
                providerType: .anthropic,
                baseURL: baseURL,
                credential: apiKey
            ),
            payload: payload
        )

        return try await cachedUpload(for: key) {
            let request = try NetworkRequestFactory.makeMultipartRequest(
                url: validatedURL("\(baseURL)/files"),
                headers: HTTPHeaders([
                    HTTPHeader(name: "x-api-key", value: apiKey),
                    HTTPHeader(name: "anthropic-version", value: anthropicVersion),
                    HTTPHeader(name: "anthropic-beta", value: anthropicFilesAPIBetaHeader)
                ])
            ) { formData in
                formData.append(Data("user_data".utf8), withName: "purpose")
                formData.append(
                    payload.data,
                    withName: "file",
                    fileName: payload.filename,
                    mimeType: payload.mimeType
                )
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let (data, _) = try await networkManager.sendRequest(request)
            let response = try decoder.decode(AnthropicFileResponse.self, from: data)

            return HostedProviderFileReference(
                id: response.id,
                uri: nil,
                mimeType: response.mimeType ?? payload.mimeType,
                displayName: response.filename ?? payload.filename
            )
        }
    }

    func uploadGeminiFile(
        file: FileContent,
        baseURL: String,
        apiKey: String,
        networkManager: NetworkManager
    ) async throws -> HostedProviderFileReference? {
        guard let payload = try payload(for: file) else { return nil }
        let key = makeCacheKey(
            providerType: .gemini,
            providerScope: providerScope(
                providerType: .gemini,
                baseURL: baseURL,
                credential: apiKey
            ),
            payload: payload
        )

        return try await cachedUpload(for: key) {
            let startRequest = try NetworkRequestFactory.makeJSONRequest(
                url: try Self.geminiUploadURL(from: baseURL),
                headers: [
                    "x-goog-api-key": apiKey,
                    "X-Goog-Upload-Protocol": "resumable",
                    "X-Goog-Upload-Command": "start",
                    "X-Goog-Upload-Header-Content-Length": "\(payload.data.count)",
                    "X-Goog-Upload-Header-Content-Type": payload.mimeType
                ],
                body: [
                    "file": [
                        "display_name": payload.filename
                    ]
                ]
            )

            let (_, startResponse) = try await networkManager.sendRequest(startRequest)
            guard let uploadURLString = startResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
                  let uploadURL = URL(string: uploadURLString) else {
                throw LLMError.invalidRequest(message: "Gemini upload session URL missing from Files API response.")
            }

            let uploadRequest = NetworkRequestFactory.makeRequest(
                url: uploadURL,
                method: "POST",
                headers: [
                    "Content-Length": "\(payload.data.count)",
                    "X-Goog-Upload-Offset": "0",
                    "X-Goog-Upload-Command": "upload, finalize"
                ],
                body: payload.data
            )

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let (data, _) = try await networkManager.sendRequest(uploadRequest)
            let response = try decoder.decode(GeminiFileEnvelope.self, from: data)
            let readyFile = try await self.waitForGeminiFileToBecomeActive(
                response.file,
                baseURL: baseURL,
                apiKey: apiKey,
                networkManager: networkManager,
                decoder: decoder
            )

            return HostedProviderFileReference(
                id: readyFile.name,
                uri: readyFile.uri,
                mimeType: readyFile.mimeType ?? payload.mimeType,
                displayName: readyFile.displayName ?? payload.filename
            )
        }
    }

    // MARK: - Private

    private func cachedUpload(
        for key: UploadCacheKey,
        operation: @escaping @Sendable () async throws -> HostedProviderFileReference
    ) async throws -> HostedProviderFileReference {
        if let cached = cache[key] {
            return cached
        }

        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task {
            try await operation()
        }
        inFlight[key] = task

        do {
            let uploaded = try await task.value
            cache[key] = uploaded
            inFlight.removeValue(forKey: key)
            return uploaded
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }

    private func payload(for file: FileContent) throws -> FilePayload? {
        let trimmedFilename = file.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = trimmedFilename.isEmpty
            ? "Attachment"
            : trimmedFilename

        if let data = file.data {
            return FilePayload(
                filename: filename,
                mimeType: normalizedMIMEType(file.mimeType),
                data: data
            )
        }

        guard let url = file.url, url.isFileURL else {
            return nil
        }

        return FilePayload(
            filename: filename,
            mimeType: normalizedMIMEType(file.mimeType),
            data: try resolveFileData(from: url)
        )
    }

    private func makeCacheKey(
        providerType: ProviderType,
        providerScope: String,
        payload: FilePayload
    ) -> UploadCacheKey {
        UploadCacheKey(
            providerType: providerType,
            providerScope: providerScope,
            filename: payload.filename,
            mimeType: payload.mimeType,
            digest: sha256Hex(of: payload.data)
        )
    }

    private func providerScope(
        providerType: ProviderType,
        baseURL: String,
        credential: String
    ) -> String {
        "\(providerType.rawValue)|\(baseURL)|\(sha256Hex(of: Data(credential.utf8)))"
    }

    private func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func geminiUploadURL(from baseURL: String) throws -> URL {
        let base = try validatedURL(baseURL)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw LLMError.invalidRequest(message: "Invalid Gemini upload URL: \(baseURL)")
        }

        let path = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = "/upload\(path)/files"
        components.query = nil

        guard let url = components.url else {
            throw LLMError.invalidRequest(message: "Invalid Gemini upload URL: \(baseURL)")
        }
        return url
    }

    private func waitForGeminiFileToBecomeActive(
        _ file: GeminiFileResource,
        baseURL: String,
        apiKey: String,
        networkManager: NetworkManager,
        decoder: JSONDecoder
    ) async throws -> GeminiFileResource {
        guard let initialState = normalizedGeminiFileState(file.state),
              initialState == "PROCESSING" else {
            return file
        }

        var current = file
        let maxAttempts = 12

        for attempt in 0..<maxAttempts {
            current = try await fetchGeminiFile(
                named: current.name,
                baseURL: baseURL,
                apiKey: apiKey,
                networkManager: networkManager,
                decoder: decoder
            )

            let state = normalizedGeminiFileState(current.state)
            if state == "ACTIVE" {
                return current
            }
            if state == "FAILED" {
                throw LLMError.providerError(
                    code: "gemini_file_processing_failed",
                    message: "Gemini Files API failed to process \"\(current.displayName ?? current.name)\"."
                )
            }

            if attempt < maxAttempts - 1 {
                let backoffMillis = min(250 * (attempt + 1), 1_000)
                try await Task.sleep(nanoseconds: UInt64(backoffMillis) * 1_000_000)
            }
        }

        throw LLMError.providerError(
            code: "gemini_file_processing_timeout",
            message: "Gemini Files API did not finish processing \"\(current.displayName ?? current.name)\" in time."
        )
    }

    private func fetchGeminiFile(
        named name: String,
        baseURL: String,
        apiKey: String,
        networkManager: NetworkManager,
        decoder: JSONDecoder
    ) async throws -> GeminiFileResource {
        let request = NetworkRequestFactory.makeRequest(
            url: try geminiFileURL(from: baseURL, fileName: name),
            headers: ["x-goog-api-key": apiKey]
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let envelope = try decoder.decode(GeminiFileEnvelope.self, from: data)
        return envelope.file
    }

    private nonisolated func geminiFileURL(from baseURL: String, fileName: String) throws -> URL {
        let normalizedName = fileName.lowercased().hasPrefix("files/")
            ? fileName
            : "files/\(fileName)"
        return try validatedURL("\(baseURL)/\(normalizedName)")
    }

    private func normalizedGeminiFileState(_ state: String?) -> String? {
        state?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}
