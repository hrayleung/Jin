import Foundation

enum OpenRouterProviderSupport {
    static let defaultBaseURL = ProviderType.openrouter.defaultBaseURL ?? "https://openrouter.ai/api/v1"
    static let defaultBaseEndpoint = URL(string: defaultBaseURL)!
    static let appIdentityHeaders = [
        "HTTP-Referer": "https://jin.app",
        "X-Title": "Jin"
    ]

    static func normalizedBaseURL(_ baseURL: String?) -> String {
        let raw = baseURL?.trimmedNonEmpty ?? defaultBaseURL
        let trimmed = removingTrailingSlashes(from: raw)
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            return trimmed
        }

        if lower.hasSuffix("/api") {
            return "\(trimmed)/v1"
        }

        if let url = URL(string: trimmed),
           url.host?.lowercased().contains("openrouter.ai") == true,
           (url.path.isEmpty || url.path == "/") {
            return "\(trimmed)/api/v1"
        }

        return trimmed
    }

    static func authorizedHeaders(apiKey: String) -> [String: String] {
        var headers = appIdentityHeaders
        headers["Authorization"] = "Bearer \(apiKey)"
        headers["Accept"] = "application/json"
        return headers
    }

    static func isTrustedURL(_ url: URL, forBaseURL baseURL: String) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              isSupportedHTTPScheme(scheme),
              let trustedBaseURL = URL(string: baseURL),
              let trustedScheme = trustedBaseURL.scheme?.lowercased(),
              let trustedHost = trustedBaseURL.host?.lowercased(),
              isSupportedHTTPScheme(trustedScheme) else {
            return false
        }

        return scheme == trustedScheme
            && host == trustedHost
            && normalizedHTTPPort(for: url) == normalizedHTTPPort(for: trustedBaseURL)
    }

    static func normalizedHTTPPort(for url: URL) -> Int? {
        if let port = url.port {
            return port
        }

        switch url.scheme?.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }

    private static func removingTrailingSlashes(from value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private static func isSupportedHTTPScheme(_ scheme: String) -> Bool {
        scheme == "http" || scheme == "https"
    }
}
