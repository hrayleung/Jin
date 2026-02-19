import SwiftUI
import Foundation

struct SearchActivityTimelineView: View {
    let activities: [SearchActivity]
    let isStreaming: Bool
    let providerLabel: String?
    let modelLabel: String?

    @State private var isExpanded = false
    @State private var resolvedRedirectURLByCanonicalSource: [String: String] = [:]

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
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: isExpanded ? JinSpacing.small : 0) {
                collapsedSummaryRow

                if isExpanded {
                    expandedPanel
                        .padding(.top, 2)
                        .transition(.opacity)
                }
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
            .task(id: redirectResolutionTaskKey) {
                await resolveRedirectTargetsIfNeeded()
            }
        }
    }

    private var collapsedSummaryRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                if presentation.sources.isEmpty {
                    Text("Web search")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    sourceAvatarStrip
                }

                Spacer(minLength: 0)

                if isStreaming && hasRunningActivity {
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

    private var sourceAvatarStrip: some View {
        HStack(spacing: -4) {
            ForEach(Array(presentation.sources.prefix(10).enumerated()), id: \.offset) { _, source in
                let sourcePresentation = renderPresentation(for: source)
                SearchSourceAvatarView(
                    host: sourcePresentation.host,
                    fallbackText: sourcePresentation.hostDisplayInitial,
                    size: 24
                )
            }

            if presentation.sources.count > 10 {
                Text("+\(presentation.sources.count - 10)")
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

    private var expandedPanel: some View {
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

            if !presentation.queries.isEmpty {
                queryChipRow
            }

            if !presentation.sources.isEmpty {
                HStack(spacing: JinSpacing.small) {
                    Text("Browsed \(presentation.sources.count) link\(presentation.sources.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CopyToPasteboardButton(
                        text: preferredURLStrings.joined(separator: "\n"),
                        helpText: "Copy links",
                        copiedHelpText: "Copied links",
                        useProminentStyle: false
                    )
                    .frame(width: 16, height: 16)
                }

                sourceCardsRow
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

    private var queryChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JinSpacing.small - 2) {
                ForEach(Array(presentation.queries.enumerated()), id: \.offset) { _, query in
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

    private var sourceCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JinSpacing.small) {
                ForEach(presentation.sources) { source in
                    SearchSourceCardView(presentation: renderPresentation(for: source))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var orderedActivities: [SearchActivity] {
        activities
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
    }

    private var presentation: SearchActivityPresentation {
        SearchActivityPresentation(activities: orderedActivities)
    }

    private var hasRunningActivity: Bool {
        orderedActivities.contains { activity in
            switch activity.status {
            case .inProgress, .searching:
                return true
            case .completed, .failed, .unknown:
                return false
            }
        }
    }

    private var contextLabel: String? {
        let provider = providerLabel?.trimmedNonEmpty
        let model = modelLabel?.trimmedNonEmpty

        if let provider, let model {
            return "\(provider) / \(model)"
        }
        return model
    }

    private var redirectResolutionTaskKey: String {
        presentation.sources
            .filter(\.usesGoogleGroundingRedirect)
            .map { $0.canonicalURLString.lowercased() }
            .sorted()
            .joined(separator: "|")
    }

    private var preferredURLStrings: [String] {
        presentation.sources.map { source in
            renderPresentation(for: source).urlString
        }
    }

    private func renderPresentation(for source: SearchSource) -> SearchSource.RenderPresentation {
        source.renderPresentation(
            resolvedURLString: resolvedRedirectURLByCanonicalSource[source.canonicalURLString]
        )
    }

    private func resolveRedirectTargetsIfNeeded() async {
        let targets = presentation.sources.filter(\.usesGoogleGroundingRedirect)
        guard !targets.isEmpty else { return }

        for source in targets {
            if resolvedRedirectURLByCanonicalSource[source.canonicalURLString] != nil {
                continue
            }

            guard let resolvedURL = await SearchRedirectURLResolver.shared.resolveIfNeeded(rawURL: source.canonicalURLString) else {
                continue
            }

            resolvedRedirectURLByCanonicalSource[source.canonicalURLString] = resolvedURL
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

        func upsertSource(url: String, title: String?) {
            guard let source = SearchSource(rawURL: url, title: title) else { return }
            if let existing = sourceByID[source.id] {
                sourceByID[source.id] = existing.merged(withTitle: source.title)
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
                upsertSource(url: url, title: activity.stringArgument("title"))
            }

            for sourceArg in activity.sourceArguments {
                upsertSource(url: sourceArg.url, title: sourceArg.title)
            }
        }

        queries = collectedQueries
        sources = sourceOrder.compactMap { sourceByID[$0] }
    }
}

private struct SearchSourceCardView: View {
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
        .frame(width: 294, height: 184, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(alignment: .top, spacing: JinSpacing.small) {
                Text(presentation.displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text(presentation.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            HStack(spacing: JinSpacing.small) {
                SearchSourceAvatarView(
                    host: presentation.host,
                    fallbackText: presentation.hostDisplayInitial,
                    size: 22
                )
                Text(presentation.hostDisplay)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("Open")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
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

    var body: some View {
        Group {
            if let faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)
                    case .empty, .failure:
                        fallbackBadge
                    @unknown default:
                        fallbackBadge
                    }
                }
            } else {
                fallbackBadge
            }
        }
    }

    private var faviconURL: URL? {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "64")
        ]
        return components?.url
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

    func renderPresentation(resolvedURLString: String?) -> RenderPresentation {
        if let resolvedURLString,
           let normalizedResolvedURL = SearchSource.normalizeURLString(resolvedURLString),
           let resolvedURL = URL(string: normalizedResolvedURL),
           let resolvedHost = resolvedURL.host?.trimmedNonEmpty {
            let resolvedHostDisplay = resolvedHost.replacingOccurrences(of: "www.", with: "")
            let resolvedTitle = title?.trimmedNonEmpty ?? resolvedHostDisplay
            let resolvedPreview = SearchSource.pathPreview(for: resolvedURL) ?? normalizedResolvedURL

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

        let defaultTitle = title?.trimmedNonEmpty ?? hostDisplay
        let defaultPreview: String
        if usesGoogleGroundingRedirect {
            defaultPreview = "Google grounded source"
        } else if let canonicalURL = URL(string: canonicalURLString),
                  let compactPath = SearchSource.pathPreview(for: canonicalURL) {
            defaultPreview = compactPath
        } else {
            defaultPreview = canonicalURLString
        }

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

    init?(rawURL: String, title: String?) {
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
        self.host = resolvedHost
        self.hostDisplay = hostDisplay
        self.usesGoogleGroundingRedirect = isGoogleGroundingRedirect
    }

    func merged(withTitle newerTitle: String?) -> SearchSource {
        SearchSource(
            id: id,
            canonicalURLString: canonicalURLString,
            title: newerTitle?.trimmedNonEmpty ?? title,
            host: host,
            hostDisplay: hostDisplay,
            usesGoogleGroundingRedirect: usesGoogleGroundingRedirect
        )
    }

    private init(
        id: String,
        canonicalURLString: String,
        title: String?,
        host: String,
        hostDisplay: String,
        usesGoogleGroundingRedirect: Bool
    ) {
        self.id = id
        self.canonicalURLString = canonicalURLString
        self.title = title
        self.host = host
        self.hostDisplay = hostDisplay
        self.usesGoogleGroundingRedirect = usesGoogleGroundingRedirect
    }

    private static func normalizeURLString(_ rawURL: String) -> String? {
        guard let trimmed = rawURL.trimmedNonEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url.absoluteString
        }
        if let url = URL(string: "https://\(trimmed)"), url.scheme != nil {
            return url.absoluteString
        }
        return nil
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
            guard let url = (item["url"] as? String)?.trimmedNonEmpty else { return nil }
            let title = (item["title"] as? String)?.trimmedNonEmpty
            return SearchSourceArgument(url: url, title: title)
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
