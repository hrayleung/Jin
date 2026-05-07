import Foundation

enum SearchSourceURLPreviewSupport {
    private static let googleRedirectTargetURLKeys = SearchRedirectQueryParameterSupport.targetURLKeys
    private static let googleRedirectSearchKeys = SearchRedirectQueryParameterSupport.searchHintKeys

    static func previewText(
        snippet: String?,
        url: URL?,
        fallbackURLString: String,
        usesGoogleGroundingRedirect: Bool
    ) -> String {
        let pathOrQueryPreview = compactPreviewFromURL(
            url,
            usesGoogleGroundingRedirect: usesGoogleGroundingRedirect
        )

        if let snippet {
            return previewText(snippet: snippet, pathOrQueryPreview: pathOrQueryPreview)
        }

        return pathOrQueryPreview ?? fallbackURLString
    }

    private static func compactPreviewFromURL(
        _ url: URL?,
        usesGoogleGroundingRedirect: Bool
    ) -> String? {
        guard let url else { return nil }

        if usesGoogleGroundingRedirect,
           let redirectHint = googleRedirectPreviewHint(from: url) {
            return redirectHint
        }

        if let path = pathPreview(for: url) {
            return path
        }

        return queryPreview(for: url)
    }

    private static func pathPreview(for url: URL) -> String? {
        guard let readablePath = readablePath(for: url) else { return nil }

        if let query = queryPreview(for: url) {
            return "\(readablePath) · \(query)"
        }
        return readablePath
    }

    private static func readablePath(for url: URL) -> String? {
        let rawPath = (url.path.removingPercentEncoding ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rawPath.trimmedNonEmpty?
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func queryPreview(for url: URL) -> String? {
        url.query?.trimmedNonEmpty
    }

    private static func previewText(
        snippet: String,
        pathOrQueryPreview: String?
    ) -> String {
        guard let pathOrQueryPreview,
              !snippet.localizedCaseInsensitiveContains(pathOrQueryPreview) else {
            return snippet
        }

        return "\(snippet) · \(pathOrQueryPreview)"
    }

    private static func googleRedirectPreviewHint(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return nil
        }

        if let targetPreview = googleRedirectTargetPreview(from: queryItems) {
            return targetPreview
        }

        return SearchRedirectQueryParameterSupport.firstDecodedNonEmptyValue(
            from: queryItems,
            matchingAnyOf: googleRedirectSearchKeys
        )
    }

    private static func googleRedirectTargetPreview(from queryItems: [URLQueryItem]) -> String? {
        guard let targetURL = SearchRedirectQueryParameterSupport.firstDecodedURL(
            from: queryItems,
            matchingAnyOf: googleRedirectTargetURLKeys
        ) else {
            return nil
        }

        return pathPreview(for: targetURL) ?? targetURL.absoluteString
    }
}
