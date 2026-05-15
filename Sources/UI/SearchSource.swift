import Foundation

enum SearchSourceKind: String, Hashable {
    case web
    case x
    case googleMaps = "google_maps"

    var isGoogleMaps: Bool {
        self == .googleMaps
    }

    var isXTwitter: Bool {
        self == .x
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
        SearchSourcePresentationSupport.renderPresentation(
            for: self,
            resolvedURLString: resolvedURLString,
            resolvedPreviewText: resolvedPreviewText
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

        let resolvedKind: SearchSourceKind = (kind == .web && SearchSource.isXTwitterHost(rawHost)) ? .x : kind
        let identity = SearchSourceIdentitySupport.identity(rawHost: rawHost, title: title, kind: resolvedKind)

        self.id = normalizedURL.lowercased()
        self.canonicalURLString = normalizedURL
        self.title = title?.trimmedNonEmpty
        self.previewText = SearchSourcePresentationSupport.normalizeSnippet(previewText)
        self.host = identity.host
        self.hostDisplay = identity.hostDisplay
        self.kind = resolvedKind
        self.mapsPlaceID = mapsPlaceID?.trimmedNonEmpty
        self.usesGoogleGroundingRedirect = identity.usesGoogleGroundingRedirect
    }

    private static func isXTwitterHost(_ rawHost: String) -> Bool {
        let normalized = rawHost.lowercased()
        let stripped = normalized.hasPrefix("www.") ? String(normalized.dropFirst(4)) : normalized
        let roots: Set<String> = ["x.com", "twitter.com"]
        if roots.contains(stripped) { return true }
        for root in roots {
            if stripped == "mobile.\(root)" || stripped == "m.\(root)" {
                return true
            }
        }
        return false
    }

    func merged(
        withTitle newerTitle: String?,
        previewText newerPreviewText: String?,
        kind newerKind: SearchSourceKind,
        mapsPlaceID newerMapsPlaceID: String?
    ) -> SearchSource {
        let normalizedNewPreview = SearchSourcePresentationSupport.normalizeSnippet(newerPreviewText)
        let mergedPreviewText = SearchSourcePresentationSupport.preferredSnippet(
            existing: previewText,
            candidate: normalizedNewPreview
        )
        let resolvedKind: SearchSourceKind = {
            if newerKind.isGoogleMaps { return newerKind }
            if newerKind == .x && kind == .web { return .x }
            return kind
        }()
        let mergedHostDisplay = resolvedKind.isGoogleMaps
            ? SearchSourceIdentitySupport.hostDisplay(for: host, kind: resolvedKind)
            : hostDisplay

        return SearchSource(
            id: id,
            canonicalURLString: canonicalURLString,
            title: newerTitle?.trimmedNonEmpty ?? title,
            previewText: mergedPreviewText,
            host: host,
            hostDisplay: mergedHostDisplay,
            kind: resolvedKind,
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
}
