import SwiftUI
import Foundation
import AppKit

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

        if !activities.isEmpty {
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
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                if content.presentation.sources.isEmpty {
                    Text("Web search")
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
                Text("Web Search")
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
                    Text(
                        "Browsed \(content.presentation.sources.count) link"
                            + "\(content.presentation.sources.count == 1 ? "" : "s")"
                    )
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

    private func buildContent() -> SearchActivityViewContent {
        let orderedActivities = activities
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
    let queries: [String]
    let sources: [SearchSource]

    init(activities: [SearchActivity]) {
        var collectedQueries: [String] = []
        var querySeen: Set<String> = []
        var sourceByID: [String: SearchSource] = [:]
        var sourceOrder: [String] = []

        func appendQuery(_ raw: String) {
            guard let normalized = raw.trimmedNonEmpty else { return }
            let key = normalized.lowercased()
            guard !querySeen.contains(key) else { return }
            querySeen.insert(key)
            collectedQueries.append(normalized)
        }

        func upsertSource(url: String, title: String?, previewText: String?) {
            guard let source = SearchSource(rawURL: url, title: title, previewText: previewText) else { return }
            if let existing = sourceByID[source.id] {
                sourceByID[source.id] = existing.merged(withTitle: source.title, previewText: source.previewText)
                return
            }
            sourceByID[source.id] = source
            sourceOrder.append(source.id)
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
                    previewText: activity.sourcePreviewArgument
                )
            }

            for sourceArg in activity.sourceArguments {
                upsertSource(url: sourceArg.url, title: sourceArg.title, previewText: sourceArg.previewText)
            }
        }

        queries = collectedQueries
        sources = sourceOrder.compactMap { sourceByID[$0] }
    }
}

private struct SearchSourceCardView: View {
    private enum Layout {
        static let cardWidth: CGFloat = 230
        static let cardHeight: CGFloat = 138
        static let previewLineLimit = 5
    }

    let presentation: SearchSource.RenderPresentation
    @State private var isHovered = false

    var body: some View {
        Group {
            if let destination = presentation.openURL {
                Link(destination: destination) {
                    cardBody
                }
                .buttonStyle(.plain)
            } else {
                cardBody
            }
        }
        .frame(width: Layout.cardWidth, height: Layout.cardHeight, alignment: .topLeading)
        .jinSurface(.neutral, cornerRadius: JinRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .stroke(
                    isHovered ? JinSemanticColor.selectedStroke : JinSemanticColor.separator.opacity(0.42),
                    lineWidth: isHovered ? JinStrokeWidth.regular : JinStrokeWidth.hairline
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1)
        .shadow(color: Color.black.opacity(isHovered ? 0.1 : 0), radius: 10, x: 0, y: 5)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            HStack(alignment: .top, spacing: JinSpacing.xSmall) {
                Text(presentation.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(presentation.previewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(Layout.previewLineLimit)
                .lineSpacing(1)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            HStack(spacing: JinSpacing.xSmall) {
                SearchSourceAvatarView(
                    host: presentation.host,
                    fallbackText: presentation.hostDisplayInitial,
                    size: 16
                )
                Text(presentation.hostDisplay)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("Open")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }
}

private struct SearchSourceAvatarView: View {
    let host: String
    let fallbackText: String
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(JinSemanticColor.surface)

            WebsiteFaviconView(
                host: host,
                fallbackText: fallbackText,
                iconSize: max(12, size - 8)
            )
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(JinSemanticColor.separator.opacity(0.6), lineWidth: JinStrokeWidth.hairline)
        )
    }
}

private struct WebsiteFaviconView: View {
    let host: String
    let fallbackText: String
    let iconSize: CGFloat
    @State private var faviconImage: NSImage?

    var body: some View {
        Group {
            if let faviconImage {
                Image(nsImage: faviconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            } else {
                fallbackBadge
            }
        }
        .task(id: host) {
            await resolveFavicon(for: host)
        }
    }

    private func resolveFavicon(for host: String) async {
        await MainActor.run {
            faviconImage = nil
        }

        let faviconData = await WebsiteFaviconRepository.shared.faviconData(for: host)
        guard !Task.isCancelled else { return }

        let image = faviconData.flatMap(NSImage.init(data:))
        guard !Task.isCancelled else { return }

        await MainActor.run {
            faviconImage = image
        }
    }

    private var fallbackBadge: some View {
        let hue = stableHue(for: host)
        let color = Color(hue: hue, saturation: 0.4, brightness: 0.9)
        return Text(fallbackText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.primary)
            .frame(width: iconSize, height: iconSize)
            .background(
                Circle()
                    .fill(color.opacity(0.85))
            )
    }

    private func stableHue(for input: String) -> Double {
        var hash: UInt32 = 5381
        for byte in input.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        return Double(hash % 360) / 360.0
    }
}

private struct SearchSource: Identifiable, Hashable {
    let id: String
    let canonicalURLString: String
    let title: String?
    let previewText: String?
    let host: String
    let hostDisplay: String
    let usesGoogleGroundingRedirect: Bool

    struct RenderPresentation: Hashable {
        let urlString: String
        let openURL: URL?
        let displayTitle: String
        let previewText: String
        let host: String
        let hostDisplay: String
        let hostDisplayInitial: String
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
                hostDisplay: resolvedHostDisplay,
                hostDisplayInitial: resolvedHostDisplay.first.map { String($0).uppercased() } ?? "W"
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
            hostDisplayInitial: hostDisplay.first.map { String($0).uppercased() } ?? "W"
        )
    }

    init?(rawURL: String, title: String?, previewText: String?) {
        guard let normalizedURL = SearchSource.normalizeURLString(rawURL) else { return nil }
        guard let rawHost = URL(string: normalizedURL)?.host?.trimmedNonEmpty else { return nil }

        let redirectHost = SearchSource.googleGroundingRedirectHost
        let isGoogleGroundingRedirect = rawHost.lowercased() == redirectHost
        let resolvedHost = if isGoogleGroundingRedirect {
            SearchSource.domainCandidate(from: title) ?? rawHost
        } else {
            rawHost
        }
        let hostDisplay = resolvedHost.replacingOccurrences(of: "www.", with: "")

        self.id = normalizedURL.lowercased()
        self.canonicalURLString = normalizedURL
        self.title = title?.trimmedNonEmpty
        self.previewText = SearchSource.normalizeSnippet(previewText)
        self.host = resolvedHost
        self.hostDisplay = hostDisplay
        self.usesGoogleGroundingRedirect = isGoogleGroundingRedirect
    }

    func merged(withTitle newerTitle: String?, previewText newerPreviewText: String?) -> SearchSource {
        let normalizedNewPreview = SearchSource.normalizeSnippet(newerPreviewText)
        return SearchSource(
            id: id,
            canonicalURLString: canonicalURLString,
            title: newerTitle?.trimmedNonEmpty ?? title,
            previewText: SearchSource.preferredSnippet(existing: previewText, candidate: normalizedNewPreview),
            host: host,
            hostDisplay: hostDisplay,
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
        usesGoogleGroundingRedirect: Bool
    ) {
        self.id = id
        self.canonicalURLString = canonicalURLString
        self.title = title
        self.previewText = previewText
        self.host = host
        self.hostDisplay = hostDisplay
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

private struct SearchSourceArgument {
    let url: String
    let title: String?
    let previewText: String?
}

private extension SearchActivity {
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
            return SearchSourceArgument(url: url, title: title, previewText: previewText)
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

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
