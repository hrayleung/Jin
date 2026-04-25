import Foundation

extension SearchSourcePreviewResolver {
    static func canonicalXStatusURLIfNeeded(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isXHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let statusPath: String

        if parts.count >= 4,
                  parts[0].caseInsensitiveCompare("i") == .orderedSame,
                  parts[1].caseInsensitiveCompare("web") == .orderedSame,
                  isStatusPathToken(parts[2]),
                  isDecimalString(parts[3]) {
            statusPath = "/i/web/status/\(parts[3])"
        } else if parts.count >= 3,
                  parts[0].caseInsensitiveCompare("i") == .orderedSame,
                  isStatusPathToken(parts[1]),
                  isDecimalString(parts[2]) {
            statusPath = "/i/web/status/\(parts[2])"
        } else if parts.count >= 3,
                  isStatusPathToken(parts[1]),
                  isDecimalString(parts[2]) {
            statusPath = "/\(parts[0])/status/\(parts[2])"
        } else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "x.com"
        components.path = statusPath
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
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
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
}
