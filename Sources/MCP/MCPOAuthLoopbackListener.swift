import Foundation
import Darwin

/// Helpers for the OAuth 2.1 loopback redirect that the MCP Swift SDK requires.
///
/// Custom URL schemes (`jin-mcp://…`) are rejected by `OAuthURLValidator`.
enum MCPOAuthLoopbackListener {
    /// Picks an ephemeral port for the OAuth loopback redirect, retrying if the
    /// first candidate is already in use.
    static func makeRedirectURI() -> URL {
        for _ in 0..<10 {
            let port = Int.random(in: 49_152...65_535)
            if isPortAvailable(UInt16(port)) {
                return URL(string: "http://127.0.0.1:\(port)/callback")!
            }
        }
        // Fallback: return a random port and let the caller handle bind failure.
        let port = Int.random(in: 49_152...65_535)
        return URL(string: "http://127.0.0.1:\(port)/callback")!
    }

    private static func isPortAvailable(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        // Do not set SO_REUSEADDR here. That flag can make bind succeed on a
        // port that already has a listener, so the later loopback server
        // would pick a busy redirect port.
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    static func redirectURI(fromAuthorizationURL url: URL) -> URL? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let raw = items.first(where: { $0.name == "redirect_uri" })?.value else {
            return nil
        }
        return URL(string: raw)
    }

    /// Parses a raw HTTP/1.1 request and, if the path matches `redirectURI`,
    /// returns the reconstructed callback URL (including query).
    static func callbackURL(fromHTTPRequest request: String, redirectURI: URL) -> URL? {
        let firstLine = request
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLine else { return nil }

        let parts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }

        let target = String(parts[1])
        guard let targetComponents = URLComponents(string: target) else { return nil }

        let expectedPath = normalizedPath(redirectURI.path)
        let actualPath = normalizedPath(targetComponents.path)
        guard actualPath == expectedPath else { return nil }

        var result = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)
        result?.query = targetComponents.query
        result?.fragment = nil
        return result?.url
    }

    static func errorMessage(fromCallback url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var values: [String: String] = [:]
        for item in items {
            guard let value = item.value else { continue }
            values[item.name] = value
        }
        guard let error = values["error"], !error.isEmpty else { return nil }
        if let description = values["error_description"], !description.isEmpty {
            return description
        }
        return error
    }

    private static func normalizedPath(_ path: String) -> String {
        if path.isEmpty { return "/" }
        return path
    }
}
