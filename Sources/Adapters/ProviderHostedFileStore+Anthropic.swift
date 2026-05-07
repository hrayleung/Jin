import Foundation
import Alamofire

extension ProviderHostedFileStore {
    private struct AnthropicFileResponse: Decodable {
        let id: String
        let filename: String?
        let mimeType: String?
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
}
