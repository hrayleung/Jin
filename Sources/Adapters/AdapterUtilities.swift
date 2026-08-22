import Foundation

// MARK: - Shared Constants

let jinUserAgent = "Jin"

// MARK: - URL Validation

/// Constructs a URL from a string, throwing `LLMError.invalidRequest` instead of crashing
/// on malformed input. Use this instead of `URL(string:)!` everywhere a provider base URL
/// or user-configurable endpoint is interpolated.
func validatedURL(_ string: String) throws -> URL {
    guard let url = URL(string: string),
          let scheme = url.scheme?.lowercased(),
          let host = url.host,
          !host.isEmpty else {
        throw LLMError.invalidRequest(
            message: "Invalid URL (must be absolute with http/https/ws/wss): \(string)"
        )
    }

    guard scheme == "http" || scheme == "https" || scheme == "ws" || scheme == "wss" else {
        throw LLMError.invalidRequest(
            message: "Invalid URL scheme '\(scheme)' (expected http/https/ws/wss): \(string)"
        )
    }

    return url
}

// MARK: - String Normalization

/// Returns a trimmed, non-empty string or nil. Used across adapters to normalize
/// optional string fields (cache keys, conversation IDs, etc.) before sending to providers.
func normalizedTrimmedString(_ value: String?) -> String? {
    value?.trimmedNonEmpty
}

/// Returns a trimmed, lowercased MIME type for stable comparisons.
func normalizedMIMEType(_ mimeType: String) -> String {
    mimeType.trimmedLowercased
}

/// Google native grounding tools are handled by Gemini / Vertex internally and
/// should never be re-routed into Jin's MCP or builtin-tool execution pipeline.
func isGoogleProviderNativeToolName(_ name: String) -> Bool {
    let normalized = name.trimmedLowercased
    switch normalized {
    case "google_search", "googlemaps", "google_maps":
        return true
    default:
        return false
    }
}

// MARK: - JSON Encoding / Decoding

/// Encodes a dictionary of `AnyCodable` values to a JSON string.
/// Returns `"{}"` if encoding fails.
func encodeJSONObject(_ object: [String: AnyCodable]) -> String {
    let raw = object.mapValues { $0.value }
    guard JSONSerialization.isValidJSONObject(raw),
          let data = try? JSONSerialization.data(withJSONObject: raw),
          let str = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return str
}

/// Parses a JSON string into a dictionary of `AnyCodable` values.
/// Returns an empty dictionary if parsing fails.
func parseJSONObject(_ jsonString: String) -> [String: AnyCodable] {
    guard let data = jsonString.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return object.mapValues(AnyCodable.init)
}

// MARK: - File Data Resolution

/// Reads file data from a URL, throwing a descriptive `LLMError` on failure.
/// Use this instead of `try? Data(contentsOf: url)` in adapter code paths where
/// a silent failure would cause user-visible data loss (e.g., dropped attachments).
///
/// `.mappedIfSafe`: attachment bytes here feed a single sequential pass
/// (base64 → request body), so a file-backed mapping replaces a full
/// dirty-heap copy per attachment per send. Consume the result within the
/// request build — a mapped `Data` must not be stored anywhere that could
/// outlive the file on disk.
func resolveFileData(from url: URL) throws -> Data {
    do {
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
        throw LLMError.invalidRequest(
            message: "Failed to read attachment \"\(url.lastPathComponent)\": \(error.localizedDescription)"
        )
    }
}

// MARK: - Image MIME Type Inference

/// Infers an image MIME type from the path extension of a URL.
/// Returns nil for unrecognised extensions.
/// Shared by `XAIMediaImageSupport`, `OpenAIChatCompletionsImageSupport`, and
/// `OpenAIAdapter` (image generation outputs).
func inferImageMIMEType(from url: URL) -> String? {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png":         return "image/png"
    case "webp":        return "image/webp"
    case "gif":         return "image/gif"
    default:            return nil
    }
}

// MARK: - Image URL Encoding

/// Converts an `ImageContent` to a data URI or remote URL string.
/// Shared by adapters that support vision (OpenAICompatible, OpenRouter, Fireworks, Perplexity).
func imageToURLString(_ image: ImageContent) throws -> String? {
    if let data = image.data {
        return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
    }
    if let url = image.url {
        if url.isFileURL {
            let data = try resolveFileData(from: url)
            return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
        }
        return url.absoluteString
    }
    return nil
}

// MARK: - Deep Merge

func deepMergeDictionary(into base: inout [String: Any], additional: [String: Any]) {
    for (key, value) in additional {
        if var baseDict = base[key] as? [String: Any],
           let addDict = value as? [String: Any] {
            deepMergeDictionary(into: &baseDict, additional: addDict)
            base[key] = baseDict
            continue
        }
        base[key] = value
    }
}

// MARK: - Unsupported Video Input Notice

/// Human-readable identifier for a video attachment, used in the omission notices.
private func videoAttachmentDetail(_ video: VideoContent) -> String {
    if let url = video.url {
        return url.isFileURL ? url.lastPathComponent : url.absoluteString
    }
    if let data = video.data {
        return "\(data.count) bytes"
    }
    return "no media payload"
}

/// Notice substituted for a `.video` part on an API surface that has no video
/// content block at all (Anthropic Messages, OpenAI/xAI Responses, Meta).
/// The whole *API* is the ceiling here, not the model.
func unsupportedVideoInputNotice(_ video: VideoContent, providerName: String, apiName: String = "chat API") -> String {
    "Video attachment omitted (\(video.mimeType), \(videoAttachmentDetail(video))): "
        + "\(providerName) \(apiName) does not support native video input in Jin yet."
}

/// Notice substituted for a `.video` part on the OpenAI-compatible `/chat/completions`
/// surface, where `video_url` exists as a wire shape but only some models accept it.
///
/// A dropped `.video` part used to be invisible: the model received the prompt text with
/// no hint that anything was attached, so it answered "I don't see anything" and the user
/// blamed Jin. Every caller of `splitContentParts` / `translateUserContentPartsToOpenAIFormat`
/// now substitutes this instead of dropping the part on the floor.
func unsupportedVideoInputNotice(_ video: VideoContent) -> String {
    "Video attachment omitted (\(video.mimeType), \(videoAttachmentDetail(video))): "
        + "the selected model does not accept video input."
}

/// Notice for a video the provider *could* read, but cannot reach: Google's
/// `generateContent` fetches YouTube links itself and refuses every other remote host
/// ("Cannot fetch content from the provided URL"). Saying so beats dropping the link.
func remoteVideoNotFetchableNotice(
    _ video: VideoContent,
    providerName: String,
    acceptedSources: String
) -> String {
    "Video attachment omitted (\(video.mimeType), \(videoAttachmentDetail(video))): "
        + "\(providerName) can only read a video from \(acceptedSources)."
}

// MARK: - Request Builder Helpers

private func makeRequestHeaders(
    authHeader: (key: String, value: String)?,
    accept: String?,
    contentType: String?,
    includeUserAgent: Bool,
    additionalHeaders: [String: String]
) -> [String: String] {
    var headers: [String: String] = [:]

    if let authHeader {
        headers[authHeader.key] = authHeader.value
    }
    if let accept {
        headers["Accept"] = accept
    }
    if let contentType {
        headers["Content-Type"] = contentType
    }
    if includeUserAgent {
        headers["User-Agent"] = jinUserAgent
    }

    for (key, value) in additionalHeaders {
        headers[key] = value
    }

    return headers
}

func makeAuthorizedJSONRequest(
    url: URL,
    method: String = "POST",
    apiKey: String,
    authHeader: (key: String, value: String)? = nil,
    body: [String: Any]? = nil,
    accept: String? = "application/json",
    additionalHeaders: [String: String] = [:],
    includeUserAgent: Bool = true,
    timeoutSeconds: TimeInterval? = nil
) throws -> URLRequest {
    let resolvedAuthHeader = authHeader ?? (key: "Authorization", value: "Bearer \(apiKey)")
    if let body {
        return try NetworkRequestFactory.makeJSONRequest(
            url: url,
            method: method,
            timeoutSeconds: timeoutSeconds,
            headers: makeRequestHeaders(
                authHeader: resolvedAuthHeader,
                accept: accept,
                contentType: nil,
                includeUserAgent: includeUserAgent,
                additionalHeaders: additionalHeaders
            ),
            body: body
        )
    }

    return NetworkRequestFactory.makeRequest(
        url: url,
        method: method,
        timeoutSeconds: timeoutSeconds,
        headers: makeRequestHeaders(
            authHeader: resolvedAuthHeader,
            accept: accept,
            contentType: nil,
            includeUserAgent: includeUserAgent,
            additionalHeaders: additionalHeaders
        )
    )
}

func makeGETRequest(
    url: URL,
    apiKey: String,
    authHeader: (key: String, value: String)? = nil,
    accept: String? = "application/json",
    additionalHeaders: [String: String] = [:],
    includeUserAgent: Bool = true,
    timeoutSeconds: TimeInterval? = nil
) -> URLRequest {
    let resolvedAuthHeader = authHeader ?? (key: "Authorization", value: "Bearer \(apiKey)")
    return NetworkRequestFactory.makeRequest(
        url: url,
        method: "GET",
        timeoutSeconds: timeoutSeconds,
        headers: makeRequestHeaders(
            authHeader: resolvedAuthHeader,
            accept: accept,
            contentType: nil,
            includeUserAgent: includeUserAgent,
            additionalHeaders: additionalHeaders
        )
    )
}

/// Validates an API key by making a GET request to a models endpoint.
/// Used by most adapters that support standard `/models` endpoint validation.
func validateAPIKeyViaGET(
    url: URL,
    apiKey: String,
    networkManager: NetworkManager,
    authHeader: (key: String, value: String)? = nil,
    accept: String? = "application/json",
    additionalHeaders: [String: String] = [:],
    includeUserAgent: Bool = true
) async -> Bool {
    let auth = authHeader ?? (key: "Authorization", value: "Bearer \(apiKey)")
    let request = NetworkRequestFactory.makeRequest(
        url: url,
        method: "GET",
        headers: makeRequestHeaders(
            authHeader: auth,
            accept: accept,
            contentType: nil,
            includeUserAgent: includeUserAgent,
            additionalHeaders: additionalHeaders
        )
    )

    do {
        _ = try await networkManager.sendRequest(request)
        return true
    } catch {
        return false
    }
}

/// Fetches models from a standard OpenAI-compatible `/v1/models` endpoint.
///
/// Used by adapters whose fetch logic is: GET `{baseURLRoot}/v1/models` (default Bearer
/// auth, `Accept: application/json`, `User-Agent: Jin`), decode `OpenAIModelsResponse`,
/// then map each item ID through a per-adapter `makeModelInfo` closure.
///
/// Adapters with custom URL construction, custom headers, custom response shapes, or
/// additional fallback behaviour (Fireworks, Together, Zyphra, OpenAICompatible) should
/// NOT use this helper.
func fetchOpenAICompatibleModels(
    baseURLRoot: String,
    apiKey: String,
    networkManager: NetworkManager,
    makeModelInfo: (String) -> ModelInfo
) async throws -> [ModelInfo] {
    let url = try validatedURL("\(baseURLRoot)/v1/models")
    let request = makeGETRequest(url: url, apiKey: apiKey)
    let (data, _) = try await networkManager.sendRequest(request)
    let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
    return response.data.map { makeModelInfo($0.id) }
}
