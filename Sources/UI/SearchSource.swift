import Foundation

enum SearchSourceKind: String, Hashable {
    case web
    case googleMaps = "google_maps"

    var isGoogleMaps: Bool {
        self == .googleMaps
    }

    init(rawValueOrDefault rawValue: String?) {
        self = SearchSourceKind(rawValue: rawValue?.lowercased() ?? "") ?? .web
    }
}

struct SearchSource: Identifiable, Hashable {
    let id: String
    let canonicalURLString: String
    let title: String?
    let previewText: String?
    let host: String
    let hostDisplay: String
    let kind: SearchSourceKind
    let mapsPlaceID: String?
    let usesGoogleGroundingRedirect: Bool

    struct RenderPresentation: Hashable {
        let urlString: String
        let openURL: URL?
        let displayTitle: String
        let previewText: String
        let host: String
        let hostDisplay: String
        let hostDisplayInitial: String
        let kind: SearchSourceKind
    }

    func renderPresentation(resolvedURLString: String?, resolvedPreviewText: String?) -> RenderPresentation {
        let normalizedSnippet = SearchSource.preferredRenderSnippet(
            providerSnippet: previewText,
            resolvedSnippet: resolvedPreviewText
        )

        if let resolvedURLString,
           let normalizedResolvedURL = SearchSource.normalizeURLString(resolvedURLString),
           let resolvedURL = URL(string: normalizedResolvedURL),
           let resolvedHost = resolvedURL.host?.trimmedNonEmpty {
            let resolvedHostDisplay = resolvedHost.replacingOccurrences(of: "www.", with: "")
            let resolvedTitle = title?.trimmedNonEmpty ?? resolvedHostDisplay
            let resolvedPreview = SearchSource.previewText(
                snippet: normalizedSnippet,
                url: resolvedURL,
                fallbackURLString: normalizedResolvedURL,
                usesGoogleGroundingRedirect: usesGoogleGroundingRedirect
            )

            return RenderPresentation(
                urlString: normalizedResolvedURL,
                openURL: resolvedURL,
                displayTitle: resolvedTitle,
                previewText: resolvedPreview,
                host: resolvedHost,
                hostDisplay: kind.isGoogleMaps ? "Google Maps" : resolvedHostDisplay,
                hostDisplayInitial: kind.isGoogleMaps ? "M" : (resolvedHostDisplay.first.map { String($0).uppercased() } ?? "W"),
                kind: kind
            )
        }

        let canonicalURL = URL(string: canonicalURLString)
        let defaultTitle = title?.trimmedNonEmpty ?? hostDisplay
        let defaultPreview = SearchSource.previewText(
            snippet: normalizedSnippet,
            url: canonicalURL,
            fallbackURLString: canonicalURLString,
            usesGoogleGroundingRedirect: usesGoogleGroundingRedirect
        )

        return RenderPresentation(
            urlString: canonicalURLString,
            openURL: URL(string: canonicalURLString),
            displayTitle: defaultTitle,
            previewText: defaultPreview,
            host: host,
            hostDisplay: hostDisplay,
            hostDisplayInitial: kind.isGoogleMaps ? "M" : (hostDisplay.first.map { String($0).uppercased() } ?? "W"),
            kind: kind
        )
    }

    init?(
        rawURL: String,
        title: String?,
        previewText: String?,
        kind: SearchSourceKind = .web,
        mapsPlaceID: String? = nil
    ) {
        guard let normalizedURL = SearchSource.normalizeURLString(rawURL) else { return nil }
        guard let rawHost = URL(string: normalizedURL)?.host?.trimmedNonEmpty else { return nil }

        let redirectHost = SearchSource.googleGroundingRedirectHost
        let isGoogleGroundingRedirect = rawHost.lowercased() == redirectHost
        let resolvedHost = if isGoogleGroundingRedirect {
            SearchSource.domainCandidate(from: title) ?? rawHost
        } else {
            rawHost
        }
        let hostDisplay = kind.isGoogleMaps ? "Google Maps" : resolvedHost.replacingOccurrences(of: "www.", with: "")

        self.id = normalizedURL.lowercased()
        self.canonicalURLString = normalizedURL
        self.title = title?.trimmedNonEmpty
        self.previewText = SearchSource.normalizeSnippet(previewText)
        self.host = resolvedHost
        self.hostDisplay = hostDisplay
        self.kind = kind
        self.mapsPlaceID = mapsPlaceID?.trimmedNonEmpty
        self.usesGoogleGroundingRedirect = isGoogleGroundingRedirect
    }

    func merged(
        withTitle newerTitle: String?,
        previewText newerPreviewText: String?,
        kind newerKind: SearchSourceKind,
        mapsPlaceID newerMapsPlaceID: String?
    ) -> SearchSource {
        let normalizedNewPreview = SearchSource.normalizeSnippet(newerPreviewText)
        return SearchSource(
            id: id,
            canonicalURLString: canonicalURLString,
            title: newerTitle?.trimmedNonEmpty ?? title,
            previewText: SearchSource.preferredSnippet(existing: previewText, candidate: normalizedNewPreview),
            host: host,
            hostDisplay: newerKind.isGoogleMaps ? "Google Maps" : hostDisplay,
            kind: newerKind.isGoogleMaps ? newerKind : kind,
            mapsPlaceID: newerMapsPlaceID?.trimmedNonEmpty ?? mapsPlaceID,
            usesGoogleGroundingRedirect: usesGoogleGroundingRedirect
        )
    }

    private init(
        id: String,
        canonicalURLString: String,
        title: String?,
        previewText: String?,
        host: String,
        hostDisplay: String,
        kind: SearchSourceKind,
        mapsPlaceID: String?,
        usesGoogleGroundingRedirect: Bool
    ) {
        self.id = id
        self.canonicalURLString = canonicalURLString
        self.title = title
        self.previewText = previewText
        self.host = host
        self.hostDisplay = hostDisplay
        self.kind = kind
        self.mapsPlaceID = mapsPlaceID
        self.usesGoogleGroundingRedirect = usesGoogleGroundingRedirect
    }

    private static func normalizeURLString(_ rawURL: String) -> String? {
        SearchURLNormalizer.normalize(rawURL)
    }

    private static func pathPreview(for url: URL) -> String? {
        let rawPath = (url.path.removingPercentEncoding ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let compactPath = rawPath.trimmedNonEmpty else {
            return nil
        }

        let readable = compactPath
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        if let query = url.query?.trimmedNonEmpty {
            return "\(readable) · \(query)"
        }
        return readable
    }

    private static func previewText(
        snippet: String?,
        url: URL?,
        fallbackURLString: String,
        usesGoogleGroundingRedirect: Bool
    ) -> String {
        let pathOrQueryPreview = compactPreviewFromURL(url, usesGoogleGroundingRedirect: usesGoogleGroundingRedirect)

        if let snippet {
            if let pathOrQueryPreview,
               !snippet.localizedCaseInsensitiveContains(pathOrQueryPreview) {
                return "\(snippet) · \(pathOrQueryPreview)"
            }
            return snippet
        }

        if let pathOrQueryPreview {
            return pathOrQueryPreview
        }

        return fallbackURLString
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

        guard let query = url.query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return nil
        }
        return query
    }

    private static func googleRedirectPreviewHint(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return nil
        }

        let targetURLKeys = ["url", "u", "target", "dest", "redirect", "adurl"]
        for key in targetURLKeys {
            guard let rawValue = queryItems.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value,
                  let targetURL = URL(string: rawValue.removingPercentEncoding ?? rawValue) else {
                continue
            }

            if let path = pathPreview(for: targetURL) {
                return path
            }
            return targetURL.absoluteString
        }

        let searchKeys = ["q", "query", "search", "search_term"]
        for key in searchKeys {
            guard let rawValue = queryItems.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value,
                  let decodedValue = (rawValue.removingPercentEncoding ?? rawValue).trimmedNonEmpty else {
                continue
            }
            return decodedValue
        }

        return nil
    }

    private static func normalizeSnippet(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= 420 {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 420)
        return String(collapsed[..<endIndex]) + "…"
    }

    private static func preferredSnippet(existing: String?, candidate: String?) -> String? {
        guard let candidate else { return existing }
        guard let existing else { return candidate }
        return candidate.count > existing.count ? candidate : existing
    }

    private static func preferredRenderSnippet(
        providerSnippet: String?,
        resolvedSnippet: String?
    ) -> String? {
        if let resolved = normalizeSnippet(resolvedSnippet) {
            return resolved
        }
        return normalizeSnippet(providerSnippet)
    }

    private static let googleGroundingRedirectHost = "vertexaisearch.cloud.google.com"

    private static func domainCandidate(from title: String?) -> String? {
        guard let title = title?.trimmedNonEmpty else { return nil }

        if let url = URL(string: title), let host = url.host?.trimmedNonEmpty {
            return host
        }

        guard !title.contains(" "), title.contains(".") else { return nil }
        return URL(string: "https://\(title)")?.host?.trimmedNonEmpty
    }
}

struct SearchSourceArgument {
    let url: String
    let title: String?
    let previewText: String?
    let kind: SearchSourceKind
    let mapsPlaceID: String?
}

extension SearchActivity {
    func stringArgument(_ key: String) -> String? {
        guard let value = arguments[key]?.value as? String else { return nil }
        return value.trimmedNonEmpty
    }

    func stringArrayArgument(_ key: String) -> [String] {
        if let values = arguments[key]?.value as? [String] {
            return values.compactMap { $0.trimmedNonEmpty }
        }

        if let values = arguments[key]?.value as? [Any] {
            return values.compactMap { ($0 as? String)?.trimmedNonEmpty }
        }

        return []
    }

    var sourcePreviewArgument: String? {
        preferredPreviewValue(in: arguments.mapValues(\.value))
    }

    var sourceKindArgument: SearchSourceKind {
        SearchSourceKind(rawValueOrDefault: stringArgument("sourceKind"))
    }

    var sourceArguments: [SearchSourceArgument] {
        guard let value = arguments["sources"]?.value else { return [] }

        let dictionaries: [[String: Any]]
        if let direct = value as? [[String: Any]] {
            dictionaries = direct
        } else if let array = value as? [Any] {
            dictionaries = array.compactMap { $0 as? [String: Any] }
        } else {
            dictionaries = []
        }

        return dictionaries.compactMap { item in
            let nestedSource = item["source"] as? [String: Any]
            let url = (item["url"] as? String)?.trimmedNonEmpty
                ?? (nestedSource?["url"] as? String)?.trimmedNonEmpty
            guard let url else { return nil }

            let title = (item["title"] as? String)?.trimmedNonEmpty
                ?? (nestedSource?["title"] as? String)?.trimmedNonEmpty
            let previewText = preferredPreviewValue(in: item)
                ?? nestedSource.flatMap { preferredPreviewValue(in: $0) }
            let sourceKind = SearchSourceKind(rawValueOrDefault:
                (item["sourceKind"] as? String)
                ?? (item["type"] as? String)
                ?? (nestedSource?["sourceKind"] as? String)
                ?? (nestedSource?["type"] as? String)
            )
            let mapsPlaceID = (item["mapsPlaceID"] as? String)?.trimmedNonEmpty
                ?? (item["placeId"] as? String)?.trimmedNonEmpty
                ?? (item["place_id"] as? String)?.trimmedNonEmpty
                ?? (nestedSource?["mapsPlaceID"] as? String)?.trimmedNonEmpty
                ?? (nestedSource?["placeId"] as? String)?.trimmedNonEmpty
                ?? (nestedSource?["place_id"] as? String)?.trimmedNonEmpty
            return SearchSourceArgument(
                url: url,
                title: title,
                previewText: previewText,
                kind: sourceKind,
                mapsPlaceID: mapsPlaceID
            )
        }
    }

    private func preferredPreviewValue(in dictionary: [String: Any]) -> String? {
        let candidateKeys = [
            "snippet",
            "summary",
            "description",
            "preview",
            "excerpt",
            "cited_text",
            "citedText",
            "quote",
            "abstract"
        ]

        for key in candidateKeys {
            if let value = (dictionary[key] as? String)?.trimmedNonEmpty {
                return value
            }
        }

        return nil
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
