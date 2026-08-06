import Foundation
import Alamofire

extension ProviderHostedFileStore {
    private struct MetaFileResponse: Decodable {
        let id: String
        let filename: String?
    }

    /// Upload media to Meta Model API Files (`POST /v1/files`, purpose=`user_data`).
    /// Same purpose string OpenAI uses for user attachments; Meta accepts images, video, PDF, audio.
    func uploadMetaFile(
        data: Data,
        filename: String,
        mimeType: String,
        baseURL: String,
        apiKey: String,
        networkManager: NetworkManager
    ) async throws -> HostedProviderFileReference {
        let payload = FilePayload(
            filename: filename.trimmedNonEmpty ?? "Attachment",
            mimeType: normalizedMIMEType(mimeType),
            data: data
        )
        let key = makeCacheKey(
            providerType: .meta,
            providerScope: providerScope(
                providerType: .meta,
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

            let (responseData, _) = try await networkManager.sendRequest(request)
            let response = try JSONDecoder().decode(MetaFileResponse.self, from: responseData)

            return HostedProviderFileReference(
                id: response.id,
                uri: nil,
                mimeType: payload.mimeType,
                displayName: response.filename ?? payload.filename
            )
        }
    }
}
