import Foundation

extension SearchSourcePreviewResolver {
    static func canonicalXStatusURLIfNeeded(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isXHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let route = XStatusRoute(pathParts: parts) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "x.com"
        components.path = route.canonicalPath
        return components.url
    }

    static func extractXPostPreview(fromOEmbedPayload data: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let html = payload["html"] as? String,
           let preview = SearchSourcePreviewHTMLParser.extractPreview(from: html) {
            return preview
        }

        guard let title = payload["title"] as? String else {
            return nil
        }
        let collapsed = title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmedNonEmpty
        return collapsed
    }

    private static func isXHost(_ host: String) -> Bool {
        host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
    }

    private static func isStatusPathToken(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered == "status" || lowered == "statuses"
    }

    private static func isDecimalString(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private enum XStatusRoute {
        case iWebStatus(id: String)
        case iStatus(id: String)
        case profileStatus(profile: String, id: String)

        init?(pathParts parts: [String]) {
            if parts.count >= 4,
               parts[0].caseInsensitiveCompare("i") == .orderedSame,
               parts[1].caseInsensitiveCompare("web") == .orderedSame,
               isStatusPathToken(parts[2]),
               isDecimalString(parts[3]) {
                self = .iWebStatus(id: parts[3])
            } else if parts.count >= 3,
                      parts[0].caseInsensitiveCompare("i") == .orderedSame,
                      isStatusPathToken(parts[1]),
                      isDecimalString(parts[2]) {
                self = .iStatus(id: parts[2])
            } else if parts.count >= 3,
                      isStatusPathToken(parts[1]),
                      isDecimalString(parts[2]) {
                self = .profileStatus(profile: parts[0], id: parts[2])
            } else {
                return nil
            }
        }

        var canonicalPath: String {
            switch self {
            case .iWebStatus(let id), .iStatus(let id):
                return "/i/web/status/\(id)"
            case .profileStatus(let profile, let id):
                return "/\(profile)/status/\(id)"
            }
        }
    }
}
