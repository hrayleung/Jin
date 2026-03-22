import Collections
import SwiftUI
import Foundation

private enum SearchActivityTimelineConfig {
    static let maxVisibleAvatars = 10
    static let previewFetchLimit = 24
}

private struct SearchActivityViewContent {
    let presentation: SearchActivityPresentation
    let hasRunningActivity: Bool
}

struct SearchActivityTimelineView: View {
    let activities: [SearchActivity]
    let isStreaming: Bool
    let providerLabel: String?
    let modelLabel: String?

    @State private var isExpanded = false
    @State private var resolvedRedirectURLByCanonicalSource: [String: String] = [:]
    @State private var resolvedPreviewTextByCanonicalSource: [String: String] = [:]

    init(
        activities: [SearchActivity],
        isStreaming: Bool,
        providerLabel: String? = nil,
        modelLabel: String? = nil
    ) {
        self.activities = activities
        self.isStreaming = isStreaming
        self.providerLabel = providerLabel
        self.modelLabel = modelLabel
    }

    var body: some View {
        let content = buildContent()
        let hasMaps = content.presentation.sources.contains { $0.kind.isGoogleMaps }
        let hasWeb = content.presentation.sources.contains { !$0.kind.isGoogleMaps }

        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                if hasMaps {
                    GoogleMapsResultsView(
                        activities: activities,
                        isStreaming: isStreaming,
                        providerLabel: providerLabel,
                        modelLabel: modelLabel
                    )
                }

                if hasWeb {
                    let webContent = hasMaps
                        ? buildContent(from: activities.filter { !isMapsOpenPage($0) && !isSearchActivity($0) })
                        : content
                    webTimelinePanel(content: webContent)
                } else if !hasMaps {
                    webTimelinePanel(content: content)
                }
            }
        }
    }

    @ViewBuilder
    private func webTimelinePanel(content: SearchActivityViewContent) -> some View {
        if !content.presentation.sources.isEmpty || !content.presentation.queries.isEmpty {
            VStack(alignment: .leading, spacing: isExpanded ? JinSpacing.small : 0) {
                collapsedSummaryRow(content: content)

                if isExpanded {
                    expandedPanel(content: content)
                        .padding(.top, 2)
                        .transition(.opacity)
                }
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
            .task(id: sourceEnrichmentTaskKey(for: content.presentation.sources)) {
                await resolveSourceDetailsIfNeeded(for: content.presentation.sources)
            }
        }
    }

    // MARK: - Subviews

    private func collapsedSummaryRow(content: SearchActivityViewContent) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: content.presentation.summarySystemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                if content.presentation.sources.isEmpty {
                    Text(content.presentation.sectionTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    sourceAvatarStrip(sources: content.presentation.sources)
                }

                Spacer(minLength: 0)

                if isStreaming && content.hasRunningActivity {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sourceAvatarStrip(sources: [SearchSource]) -> some View {
        HStack(spacing: -4) {
            ForEach(Array(sources.prefix(SearchActivityTimelineConfig.maxVisibleAvatars)), id: \.id) { source in
                let sourcePresentation = renderPresentation(for: source)
                SearchSourceAvatarView(
                    host: sourcePresentation.host,
                    fallbackText: sourcePresentation.hostDisplayInitial,
                    kind: sourcePresentation.kind,
                    size: 24
                )
            }

            if sources.count > SearchActivityTimelineConfig.maxVisibleAvatars {
                Text("+\(sources.count - SearchActivityTimelineConfig.maxVisibleAvatars)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(JinSemanticColor.subtleSurface))
                    .overlay(
                        Circle()
                            .stroke(JinSemanticColor.separator.opacity(0.6), lineWidth: JinStrokeWidth.hairline)
                    )
            }
        }
    }

    private func expandedPanel(content: SearchActivityViewContent) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small - 2) {
                Text(content.presentation.sectionTitle)
                    .font(.headline)

                if let contextLabel {
                    Text("(\(contextLabel))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if !content.presentation.queries.isEmpty {
                queryChipRow(queries: content.presentation.queries)
            }

            if !content.presentation.sources.isEmpty {
                HStack(spacing: JinSpacing.small) {
                    Text(content.presentation.sourceSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CopyToPasteboardButton(
                        text: preferredURLStrings(for: content.presentation.sources).joined(separator: "\n"),
                        helpText: "Copy links",
                        copiedHelpText: "Copied links",
                        useProminentStyle: false
                    )
                    .frame(width: 16, height: 16)
                }

                sourceCardsRow(sources: content.presentation.sources)
            } else {
                Text("This response does not include source URLs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JinSpacing.small)
                    .padding(.vertical, 6)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, 2)
        .padding(.bottom, JinSpacing.xSmall)
    }

    private func queryChipRow(queries: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JinSpacing.small - 2) {
                ForEach(Array(queries.enumerated()), id: \.offset) { _, query in
                    HStack(spacing: JinSpacing.xSmall) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(query)
                            .font(.subheadline)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, JinSpacing.small)
                    .padding(.vertical, 5)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sourceCardsRow(sources: [SearchSource]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: JinSpacing.xSmall + 1) {
                ForEach(sources) { source in
                    SearchSourceCardView(presentation: renderPresentation(for: source))
                }
            }
            .padding(.horizontal, JinStrokeWidth.emphasized)
            .padding(.vertical, JinStrokeWidth.emphasized)
        }
    }

    // MARK: - Derived Content

    private func buildContent(from sourceActivities: [SearchActivity]? = nil) -> SearchActivityViewContent {
        let activitiesToProcess = sourceActivities ?? activities
        let orderedActivities = activitiesToProcess
            .enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element
                let right = rhs.element

                if left.sequenceNumber != right.sequenceNumber {
                    return (left.sequenceNumber ?? Int.max) < (right.sequenceNumber ?? Int.max)
                }
                if left.outputIndex != right.outputIndex {
                    return (left.outputIndex ?? Int.max) < (right.outputIndex ?? Int.max)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        let hasRunningActivity = orderedActivities.contains { activity in
            switch activity.status {
            case .inProgress, .searching:
                return true
            case .completed, .failed, .unknown:
                return false
            }
        }

        return SearchActivityViewContent(
            presentation: SearchActivityPresentation(activities: orderedActivities),
            hasRunningActivity: hasRunningActivity
        )
    }

    private func isMapsOpenPage(_ activity: SearchActivity) -> Bool {
        guard activity.type == "open_page" else { return false }
        let sourceKind = (activity.arguments["sourceKind"]?.value as? String)?.lowercased()
        return sourceKind == "google_maps"
    }

    private func isSearchActivity(_ activity: SearchActivity) -> Bool {
        activity.type == "search" || activity.type == "searching"
    }

    private var contextLabel: String? {
        let provider = providerLabel?.trimmedNonEmpty
        let model = modelLabel?.trimmedNonEmpty

        if let provider, let model {
            return "\(provider) / \(model)"
        }
        return model
    }

    private func sourceEnrichmentTaskKey(for sources: [SearchSource]) -> String {
        sources
            .map { source in
                let hasProviderSnippet = source.previewText == nil ? "0" : "1"
                return "\(source.canonicalURLString.lowercased())|\(hasProviderSnippet)"
            }
            .sorted()
            .joined(separator: "|")
    }

    private func preferredURLStrings(for sources: [SearchSource]) -> [String] {
        sources.map { source in
            renderPresentation(for: source).urlString
        }
    }

    // MARK: - Source Enrichment

    private func renderPresentation(for source: SearchSource) -> SearchSource.RenderPresentation {
        source.renderPresentation(
            resolvedURLString: resolvedRedirectURLByCanonicalSource[source.canonicalURLString],
            resolvedPreviewText: resolvedPreviewTextByCanonicalSource[source.canonicalURLString]
        )
    }

    private func resolveSourceDetailsIfNeeded(for sources: [SearchSource]) async {
        pruneStaleResolvedSourceData(for: sources)
        await resolveRedirectTargetsIfNeeded(for: sources)
        await resolveMissingPreviewTextIfNeeded(for: sources)
    }

    private func pruneStaleResolvedSourceData(for sources: [SearchSource]) {
        let activeCanonicalURLs = Set(sources.map(\.canonicalURLString))
        resolvedRedirectURLByCanonicalSource = resolvedRedirectURLByCanonicalSource.filter { activeCanonicalURLs.contains($0.key) }
        resolvedPreviewTextByCanonicalSource = resolvedPreviewTextByCanonicalSource.filter { activeCanonicalURLs.contains($0.key) }
    }

    private func resolveRedirectTargetsIfNeeded(for sources: [SearchSource]) async {
        for source in sources where source.usesGoogleGroundingRedirect {
            if resolvedRedirectURLByCanonicalSource[source.canonicalURLString] != nil {
                continue
            }

            guard let resolvedURL = await SearchRedirectURLResolver.shared.resolveIfNeeded(rawURL: source.canonicalURLString) else {
                continue
            }

            resolvedRedirectURLByCanonicalSource[source.canonicalURLString] = resolvedURL
        }
    }

    private func resolveMissingPreviewTextIfNeeded(for sources: [SearchSource]) async {
        var fetchedPreviewCount = 0

        for source in sources {
            guard !Task.isCancelled else { break }
            guard resolvedPreviewTextByCanonicalSource[source.canonicalURLString] == nil else { continue }
            guard fetchedPreviewCount < SearchActivityTimelineConfig.previewFetchLimit else { break }
            guard !source.kind.isGoogleMaps else { continue }

            if source.usesGoogleGroundingRedirect,
               resolvedRedirectURLByCanonicalSource[source.canonicalURLString] == nil {
                continue
            }

            let previewURL = resolvedRedirectURLByCanonicalSource[source.canonicalURLString] ?? source.canonicalURLString
            guard let preview = await SearchSourcePreviewResolver.shared.resolvePreviewIfNeeded(rawURL: previewURL) else {
                continue
            }

            resolvedPreviewTextByCanonicalSource[source.canonicalURLString] = preview
            fetchedPreviewCount += 1
        }
    }
}

private struct SearchActivityPresentation {
    enum DisplayKind {
        case web
        case maps
        case mixed

        var sectionTitle: String {
            switch self {
            case .web:
                return "Web Search"
            case .maps:
                return "Google Maps"
            case .mixed:
                return "Search & Maps"
            }
        }

        var summarySystemImage: String {
            switch self {
            case .web:
                return "magnifyingglass"
            case .maps:
                return "map"
            case .mixed:
                return "map.circle"
            }
        }

        func sourceSummaryText(count: Int) -> String {
            switch self {
            case .web:
                return "Browsed \(count) link" + (count == 1 ? "" : "s")
            case .maps:
                return "Cited \(count) place source" + (count == 1 ? "" : "s")
            case .mixed:
                return "Browsed \(count) grounded source" + (count == 1 ? "" : "s")
            }
        }
    }

    let queries: [String]
    let sources: [SearchSource]
    let displayKind: DisplayKind

    var sectionTitle: String { displayKind.sectionTitle }
    var summarySystemImage: String { displayKind.summarySystemImage }
    var sourceSummaryText: String { displayKind.sourceSummaryText(count: sources.count) }

    init(activities: [SearchActivity]) {
        var queriesByKey: OrderedDictionary<String, String> = [:]
        var sourceByID: OrderedDictionary<String, SearchSource> = [:]

        func appendQuery(_ raw: String) {
            guard let normalized = raw.trimmedNonEmpty else { return }
            let key = normalized.lowercased()
            if queriesByKey[key] == nil {
                queriesByKey[key] = normalized
            }
        }

        func upsertSource(
            url: String,
            title: String?,
            previewText: String?,
            sourceKind: SearchSourceKind,
            mapsPlaceID: String?
        ) {
            guard let source = SearchSource(
                rawURL: url,
                title: title,
                previewText: previewText,
                kind: sourceKind,
                mapsPlaceID: mapsPlaceID
            ) else {
                return
            }
            if let existing = sourceByID[source.id] {
                sourceByID[source.id] = existing.merged(
                    withTitle: source.title,
                    previewText: source.previewText,
                    kind: source.kind,
                    mapsPlaceID: source.mapsPlaceID
                )
                return
            }
            sourceByID[source.id] = source
        }

        for activity in activities {
            for query in activity.stringArrayArgument("queries") {
                appendQuery(query)
            }
            if let query = activity.stringArgument("query") {
                appendQuery(query)
            }

            if let url = activity.stringArgument("url") {
                upsertSource(
                    url: url,
                    title: activity.stringArgument("title"),
                    previewText: activity.sourcePreviewArgument,
                    sourceKind: activity.sourceKindArgument,
                    mapsPlaceID: activity.stringArgument("mapsPlaceID")
                )
            }

            for sourceArg in activity.sourceArguments {
                upsertSource(
                    url: sourceArg.url,
                    title: sourceArg.title,
                    previewText: sourceArg.previewText,
                    sourceKind: sourceArg.kind,
                    mapsPlaceID: sourceArg.mapsPlaceID
                )
            }
        }

        queries = Array(queriesByKey.values)
        sources = Array(sourceByID.values)

        let hasMapsSources = sources.contains(where: { $0.kind.isGoogleMaps })
        let hasWebSources = sources.contains(where: { !$0.kind.isGoogleMaps })
        switch (hasMapsSources, hasWebSources) {
        case (true, true):
            displayKind = .mixed
        case (true, false):
            displayKind = .maps
        default:
            displayKind = .web
        }
    }
}
