import Foundation

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
let anthropicFastModeBetaHeader = "fast-mode-2026-02-01"

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

    struct UploadCacheKey: Hashable {
        let providerType: ProviderType
        let providerScope: String
        let filename: String
        let mimeType: String
        let digest: String
    }

    struct FilePayload: Sendable {
        let filename: String
        let mimeType: String
        let data: Data
    }

    private var cache: [UploadCacheKey: HostedProviderFileReference] = [:]
    private var inFlight: [UploadCacheKey: Task<HostedProviderFileReference, Error>] = [:]

    func cachedUpload(
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

    func payload(for file: FileContent) throws -> FilePayload? {
        let filename = file.filename.trimmedNonEmpty ?? "Attachment"

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

    func makeCacheKey(
        providerType: ProviderType,
        providerScope: String,
        payload: FilePayload
    ) -> UploadCacheKey {
        UploadCacheKey(
            providerType: providerType,
            providerScope: providerScope,
            filename: payload.filename,
            mimeType: payload.mimeType,
            digest: SHA256HexDigest.data(payload.data)
        )
    }

    func providerScope(
        providerType: ProviderType,
        baseURL: String,
        credential: String
    ) -> String {
        "\(providerType.rawValue)|\(baseURL)|\(SHA256HexDigest.string(credential))"
    }

}
