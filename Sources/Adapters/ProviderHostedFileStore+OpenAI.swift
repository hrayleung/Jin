import Foundation
import Alamofire

extension ProviderHostedFileStore {
    private struct OpenAIFileResponse: Decodable {
        let id: String
        let filename: String?
    }

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
}
