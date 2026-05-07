import Foundation

extension ProviderHostedFileStore {
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
        state?.trimmed.uppercased()
    }
}
