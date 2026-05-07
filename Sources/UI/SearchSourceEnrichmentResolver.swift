import Foundation

struct SearchSourceEnrichmentResolver {
    typealias RedirectURLResolver = (String) async -> String?
    typealias PreviewTextResolver = (String) async -> String?

    private struct PreviewFetchResult {
        let source: SearchSource
        let text: String
    }

    static let live = SearchSourceEnrichmentResolver(
        redirectURL: { rawURL in
            await SearchRedirectURLResolver.shared.resolveIfNeeded(rawURL: rawURL)
        },
        previewText: { rawURL in
            await SearchSourcePreviewResolver.shared.resolvePreviewIfNeeded(rawURL: rawURL)
        }
    )

    private let redirectURL: RedirectURLResolver
    private let previewText: PreviewTextResolver

    init(
        redirectURL: @escaping RedirectURLResolver,
        previewText: @escaping PreviewTextResolver
    ) {
        self.redirectURL = redirectURL
        self.previewText = previewText
    }

    func resolve(
        sources: [SearchSource],
        state initialState: SearchSourceEnrichmentState
    ) async -> SearchSourceEnrichmentState {
        var state = initialState
        state.pruneStaleResolvedSourceData(for: sources)
        state = await resolvingRedirectTargets(for: sources, in: state)
        state = await resolvingMissingPreviewText(for: sources, in: state)
        return state
    }

    private func resolvingRedirectTargets(
        for sources: [SearchSource],
        in initialState: SearchSourceEnrichmentState
    ) async -> SearchSourceEnrichmentState {
        var state = initialState

        for source in state.sourcesNeedingRedirectResolution(from: sources) {
            guard let resolvedURL = await redirectURL(source.canonicalURLString) else {
                continue
            }

            state.setResolvedRedirectURL(resolvedURL, for: source)
        }

        return state
    }

    private func resolvingMissingPreviewText(
        for sources: [SearchSource],
        in initialState: SearchSourceEnrichmentState
    ) async -> SearchSourceEnrichmentState {
        var state = initialState
        var fetchedPreviewCount = 0

        for source in sources {
            guard !Task.isCancelled else { break }
            guard !state.shouldStopPreviewFetching(successfulFetchCount: fetchedPreviewCount) else { break }
            guard let resolvedPreview = await previewFetchResult(for: source, in: state) else { continue }

            state.setResolvedPreviewText(resolvedPreview.text, for: resolvedPreview.source)
            fetchedPreviewCount += 1
        }

        return state
    }

    private func previewFetchResult(
        for source: SearchSource,
        in state: SearchSourceEnrichmentState
    ) async -> PreviewFetchResult? {
        guard let fetchRequest = state.previewFetchRequest(for: source) else { return nil }
        guard let preview = await previewText(fetchRequest.urlString) else { return nil }
        return PreviewFetchResult(source: fetchRequest.source, text: preview)
    }
}
