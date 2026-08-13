import Foundation

enum MCPOAuthDiscovery {
    static func protectedResourceMetadataURLs(for endpoint: URL) -> [URL] {
        var urls: [URL] = []
        let origin = endpoint.originURL

        if let inserted = insertingWellKnown(hostURL: origin, wellKnown: "/.well-known/oauth-protected-resource", path: endpoint.path) {
            urls.append(inserted)
        }
        if let root = URL(string: "/.well-known/oauth-protected-resource", relativeTo: origin)?.absoluteURL {
            urls.append(root)
        }
        return uniqueURLs(urls)
    }

    static func authorizationServerMetadataURLs(for issuer: URL) -> [URL] {
        var urls: [URL] = []
        let origin = issuer.originURL
        if let oauth = insertingWellKnown(hostURL: origin, wellKnown: "/.well-known/oauth-authorization-server", path: issuer.path) {
            urls.append(oauth)
        }
        if let oidc = insertingWellKnown(hostURL: origin, wellKnown: "/.well-known/openid-configuration", path: issuer.path) {
            urls.append(oidc)
        }
        if let rootOAuth = URL(string: "/.well-known/oauth-authorization-server", relativeTo: origin)?.absoluteURL {
            urls.append(rootOAuth)
        }
        if let rootOIDC = URL(string: "/.well-known/openid-configuration", relativeTo: origin)?.absoluteURL {
            urls.append(rootOIDC)
        }
        return uniqueURLs(urls)
    }

    static func resourceMetadataURL(fromWWWAuthenticate header: String) -> URL? {
        let pattern = #"resource_metadata\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let match = regex.firstMatch(in: header, options: [], range: range),
              let urlRange = Range(match.range(at: 1), in: header) else {
            return nil
        }
        return URL(string: String(header[urlRange]))
    }

    static func canonicalResource(for endpoint: URL) -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.query = nil
        let value = components?.string ?? endpoint.absoluteString
        if value.count > 1, value.hasSuffix("/") {
            return String(value.dropLast())
        }
        return value
    }

    private static func insertingWellKnown(hostURL: URL, wellKnown: String, path: String) -> URL? {
        let trimmedPath = path == "/" ? "" : path
        let combined = wellKnown + trimmedPath
        return URL(string: combined, relativeTo: hostURL)?.absoluteURL
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }
}

private extension URL {
    var originURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url ?? self
    }
}
