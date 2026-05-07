import Foundation

enum SearchSourcePresentationSupport {
    static func renderPresentation(
        for source: SearchSource,
        resolvedURLString: String?,
        resolvedPreviewText: String?
    ) -> SearchSource.RenderPresentation {
        let normalizedSnippet = preferredRenderSnippet(
            providerSnippet: source.previewText,
            resolvedSnippet: resolvedPreviewText
        )

        if let resolved = resolvedRenderPresentation(
            for: source,
            resolvedURLString: resolvedURLString,
            normalizedSnippet: normalizedSnippet
        ) {
            return resolved
        }

        return canonicalRenderPresentation(for: source, normalizedSnippet: normalizedSnippet)
    }

    private static func resolvedRenderPresentation(
        for source: SearchSource,
        resolvedURLString: String?,
        normalizedSnippet: String?
    ) -> SearchSource.RenderPresentation? {
        guard let resolvedURLString,
              let normalizedResolvedURL = SearchURLNormalizer.normalize(resolvedURLString),
              let resolvedURL = URL(string: normalizedResolvedURL),
              let resolvedHost = resolvedURL.host?.trimmedNonEmpty else {
            return nil
        }

        let resolvedHostDisplay = resolvedHost.replacingOccurrences(of: "www.", with: "")
        let resolvedTitle = source.title?.trimmedNonEmpty ?? resolvedHostDisplay
        let resolvedPreview = SearchSourceURLPreviewSupport.previewText(
            snippet: normalizedSnippet,
            url: resolvedURL,
            fallbackURLString: normalizedResolvedURL,
            usesGoogleGroundingRedirect: source.usesGoogleGroundingRedirect
        )

        return makeRenderPresentation(
            urlString: normalizedResolvedURL,
            openURL: resolvedURL,
            displayTitle: resolvedTitle,
            previewText: resolvedPreview,
            host: resolvedHost,
            hostDisplay: source.kind.isGoogleMaps ? "Google Maps" : resolvedHostDisplay,
            kind: source.kind
        )
    }

    private static func canonicalRenderPresentation(
        for source: SearchSource,
        normalizedSnippet: String?
    ) -> SearchSource.RenderPresentation {
        let canonicalURL = URL(string: source.canonicalURLString)
        let defaultTitle = source.title?.trimmedNonEmpty ?? source.hostDisplay
        let defaultPreview = SearchSourceURLPreviewSupport.previewText(
            snippet: normalizedSnippet,
            url: canonicalURL,
            fallbackURLString: source.canonicalURLString,
            usesGoogleGroundingRedirect: source.usesGoogleGroundingRedirect
        )

        return makeRenderPresentation(
            urlString: source.canonicalURLString,
            openURL: canonicalURL,
            displayTitle: defaultTitle,
            previewText: defaultPreview,
            host: source.host,
            hostDisplay: source.hostDisplay,
            kind: source.kind
        )
    }

    static func normalizeSnippet(_ raw: String?) -> String? {
        guard let raw else { return nil }
        guard let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmedNonEmpty else { return nil }
        if collapsed.count <= 420 {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 420)
        return String(collapsed[..<endIndex]) + "…"
    }

    static func preferredSnippet(existing: String?, candidate: String?) -> String? {
        guard let candidate else { return existing }
        guard let existing else { return candidate }
        return candidate.count > existing.count ? candidate : existing
    }

    static func preferredRenderSnippet(
        providerSnippet: String?,
        resolvedSnippet: String?
    ) -> String? {
        if let resolved = normalizeSnippet(resolvedSnippet) {
            return resolved
        }
        return normalizeSnippet(providerSnippet)
    }

    private static func hostDisplayInitial(for hostDisplay: String, kind: SearchSourceKind) -> String {
        if kind.isGoogleMaps {
            return "M"
        }
        return hostDisplay.first.map { String($0).uppercased() } ?? "W"
    }

    private static func makeRenderPresentation(
        urlString: String,
        openURL: URL?,
        displayTitle: String,
        previewText: String,
        host: String,
        hostDisplay: String,
        kind: SearchSourceKind
    ) -> SearchSource.RenderPresentation {
        SearchSource.RenderPresentation(
            urlString: urlString,
            openURL: openURL,
            displayTitle: displayTitle,
            previewText: previewText,
            host: host,
            hostDisplay: hostDisplay,
            hostDisplayInitial: hostDisplayInitial(for: hostDisplay, kind: kind),
            kind: kind
        )
    }
}
