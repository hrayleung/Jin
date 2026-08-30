import Foundation

/// Parallel Search MCP advertises OAuth only on `/mcp-oauth`.
/// `/mcp` is the anonymous / API-key endpoint and has no authorization-server metadata.
enum MCPParallelSearchEndpoint {
    static let host = "search.parallel.ai"
    static let anonymousPath = "/mcp"
    static let oauthPath = "/mcp-oauth"

    static let anonymousURL = "https://\(host)\(anonymousPath)"
    static let oauthURL = "https://\(host)\(oauthPath)"

    static func isSearchMCP(_ endpoint: String) -> Bool {
        guard let url = parsedURL(endpoint) else { return false }
        return isSearchMCP(url)
    }

    static func isSearchMCP(_ url: URL) -> Bool {
        url.host?.lowercased() == host && isManagedPath(url.path)
    }

    static func aligned(_ endpoint: String, to kind: MCPHTTPAuthentication.FormKind) -> String {
        aligned(endpoint, usesOAuth: kind == .oauth)
    }

    static func aligned(_ endpoint: String, authentication: MCPHTTPAuthentication) -> String {
        if case .oauth = authentication {
            return aligned(endpoint, usesOAuth: true)
        }
        return aligned(endpoint, usesOAuth: false)
    }

    static func aligned(_ endpoint: URL, authentication: MCPHTTPAuthentication) -> URL {
        let alignedString = aligned(endpoint.absoluteString, authentication: authentication)
        return URL(string: alignedString) ?? endpoint
    }

    static func aligned(_ endpoint: String, usesOAuth: Bool) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.host?.lowercased() == host else {
            return endpoint
        }

        let path = normalizedPath(components.path)
        guard isManagedPath(path) else { return endpoint }

        let target = usesOAuth ? oauthPath : anonymousPath
        guard path != target else { return endpoint }

        components.path = target
        return components.string ?? endpoint
    }

    private static func parsedURL(_ endpoint: String) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private static func normalizedPath(_ path: String) -> String {
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }

    private static func isManagedPath(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return normalized == anonymousPath || normalized == oauthPath
    }
}
