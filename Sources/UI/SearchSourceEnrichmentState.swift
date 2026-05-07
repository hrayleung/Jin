import Foundation

struct SearchSourceEnrichmentState: Equatable {
    static let previewFetchLimit = 24

    struct PreviewFetchRequest: Equatable {
        let source: SearchSource
        let urlString: String
    }

    private(set) var resolvedRedirectURLByCanonicalSource: [String: String] = [:]
    private(set) var resolvedPreviewTextByCanonicalSource: [String: String] = [:]

    mutating func pruneStaleResolvedSourceData(for sources: [SearchSource]) {
        let activeCanonicalURLs = Self.activeCanonicalURLSet(for: sources)
        resolvedRedirectURLByCanonicalSource = Self.prunedResolvedSourceData(
            resolvedRedirectURLByCanonicalSource,
            keeping: activeCanonicalURLs
        )
        resolvedPreviewTextByCanonicalSource = Self.prunedResolvedSourceData(
            resolvedPreviewTextByCanonicalSource,
            keeping: activeCanonicalURLs
        )
    }

    func renderPresentation(for source: SearchSource) -> SearchSource.RenderPresentation {
        source.renderPresentation(
            resolvedURLString: resolvedRedirectURL(for: source),
            resolvedPreviewText: resolvedPreviewText(for: source)
        )
    }

    func preferredURLStrings(for sources: [SearchSource]) -> [String] {
        sources.map { source in
            renderPresentation(for: source).urlString
        }
    }

    static func taskKey(for sources: [SearchSource]) -> String {
        sources
            .map(taskKeyComponent)
            .sorted()
            .joined(separator: "|")
    }

    func sourcesNeedingRedirectResolution(from sources: [SearchSource]) -> [SearchSource] {
        sources.filter { source in
            source.usesGoogleGroundingRedirect && !hasResolvedRedirectURL(for: source)
        }
    }

    func shouldStopPreviewFetching(successfulFetchCount: Int) -> Bool {
        successfulFetchCount >= Self.previewFetchLimit
    }

    func previewFetchRequest(for source: SearchSource) -> PreviewFetchRequest? {
        guard canFetchPreview(for: source) else { return nil }
        guard let previewURL = previewURL(for: source) else { return nil }
        return PreviewFetchRequest(source: source, urlString: previewURL)
    }

    func previewURL(for source: SearchSource) -> String? {
        if source.usesGoogleGroundingRedirect && !hasResolvedRedirectURL(for: source) {
            return nil
        }
        return resolvedRedirectURL(for: source) ?? source.canonicalURLString
    }

    func hasResolvedRedirectURL(for source: SearchSource) -> Bool {
        resolvedRedirectURL(for: source) != nil
    }

    func hasResolvedPreviewText(for source: SearchSource) -> Bool {
        resolvedPreviewText(for: source) != nil
    }

    mutating func setResolvedRedirectURL(_ resolvedURL: String, for source: SearchSource) {
        resolvedRedirectURLByCanonicalSource[source.canonicalURLString] = resolvedURL
    }

    mutating func setResolvedPreviewText(_ previewText: String, for source: SearchSource) {
        resolvedPreviewTextByCanonicalSource[source.canonicalURLString] = previewText
    }

    private func resolvedRedirectURL(for source: SearchSource) -> String? {
        resolvedRedirectURLByCanonicalSource[source.canonicalURLString]
    }

    private func resolvedPreviewText(for source: SearchSource) -> String? {
        resolvedPreviewTextByCanonicalSource[source.canonicalURLString]
    }

    private static func activeCanonicalURLSet(for sources: [SearchSource]) -> Set<String> {
        Set(sources.map(\.canonicalURLString))
    }

    private static func prunedResolvedSourceData(
        _ data: [String: String],
        keeping activeCanonicalURLs: Set<String>
    ) -> [String: String] {
        data.filter { activeCanonicalURLs.contains($0.key) }
    }

    private static func taskKeyComponent(for source: SearchSource) -> String {
        let hasProviderSnippet = source.previewText == nil ? "0" : "1"
        return "\(source.canonicalURLString.lowercased())|\(hasProviderSnippet)"
    }

    private func canFetchPreview(for source: SearchSource) -> Bool {
        !hasResolvedPreviewText(for: source) && !source.kind.isGoogleMaps
    }
}
