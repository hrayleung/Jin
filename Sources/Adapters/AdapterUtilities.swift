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
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Returns a trimmed, lowercased MIME type for stable comparisons.
func normalizedMIMEType(_ mimeType: String) -> String {
    mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

/// Google native grounding tools are handled by Gemini / Vertex internally and
/// should never be re-routed into Jin's MCP or builtin-tool execution pipeline.
func isGoogleProviderNativeToolName(_ name: String) -> Bool {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
func resolveFileData(from url: URL) throws -> Data {
    do {
        return try Data(contentsOf: url)
    } catch {
        throw LLMError.invalidRequest(
            message: "Failed to read attachment \"\(url.lastPathComponent)\": \(error.localizedDescription)"
        )
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

func unsupportedVideoInputNotice(_ video: VideoContent, providerName: String, apiName: String = "chat API") -> String {
    let detail: String
    if let url = video.url {
        detail = url.isFileURL ? url.lastPathComponent : url.absoluteString
    } else if let data = video.data {
        detail = "\(data.count) bytes"
    } else {
        detail = "no media payload"
    }
    return "Video attachment omitted (\(video.mimeType), \(detail)): \(providerName) \(apiName) does not support native video input in Jin yet."
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
    body: [String: Any]? = nil,
    accept: String? = "application/json",
    additionalHeaders: [String: String] = [:],
    includeUserAgent: Bool = true,
    timeoutSeconds: TimeInterval? = nil
) throws -> URLRequest {
    if let body {
        return try NetworkRequestFactory.makeJSONRequest(
            url: url,
            method: method,
            timeoutSeconds: timeoutSeconds,
            headers: makeRequestHeaders(
                authHeader: (key: "Authorization", value: "Bearer \(apiKey)"),
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
            authHeader: (key: "Authorization", value: "Bearer \(apiKey)"),
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
    accept: String? = "application/json",
    additionalHeaders: [String: String] = [:],
    includeUserAgent: Bool = true,
    timeoutSeconds: TimeInterval? = nil
) -> URLRequest {
    NetworkRequestFactory.makeRequest(
        url: url,
        method: "GET",
        timeoutSeconds: timeoutSeconds,
        headers: makeRequestHeaders(
            authHeader: (key: "Authorization", value: "Bearer \(apiKey)"),
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
