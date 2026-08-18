import SwiftUI

private enum SearchActivityWebTimelinePanelConfig {
    static let maxVisibleAvatars = 4
}

enum SearchActivityCollapsedSourceSupport {
    static func distinctPresentations(
        _ presentations: [SearchSource.RenderPresentation]
    ) -> [SearchSource.RenderPresentation] {
        var seenKeys = Set<String>()
        return presentations.filter { presentation in
            let key = "\(presentation.kind.rawValue)|\(presentation.hostDisplay.lowercased())"
            return seenKeys.insert(key).inserted
        }
    }
}

struct SearchActivityWebTimelineCollapsedSummaryRow: View {
    let content: SearchActivityTimelineSupport.ViewContent
    let isStreaming: Bool
    let sourceEnrichmentState: SearchSourceEnrichmentState
    let isExpanded: Bool
    /// Parent owns the expand transaction (including the first-expand
    /// lazy-mount dance). The row just fires the request.
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            summaryRowContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(content.presentation.sectionTitle))
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Hides search sources" : "Shows search sources"))
    }

    private var summaryRowContent: some View {
        HStack(spacing: JinSpacing.small) {
            disclosureIndicator

            summaryIcon
            summaryTitleContent

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var summaryIcon: some View {
        Image(systemName: content.presentation.summarySystemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(JinSemanticColor.textSecondary)
            .frame(width: 16, height: 16)
    }

    private var summaryTitleContent: some View {
        HStack(spacing: JinSpacing.small - 2) {
            Text(content.presentation.sectionTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(JinSemanticColor.textSecondary)
                .lineLimit(1)

            if !content.presentation.sources.isEmpty {
                SearchActivityWebTimelineSourceAvatarStrip(
                    sources: content.presentation.sources,
                    sourceEnrichmentState: sourceEnrichmentState
                )
            }
        }
    }

    private var disclosureIndicator: some View {
        JinDisclosureChevron(
            isExpanded: isExpanded,
            font: .caption2.weight(.semibold),
            foregroundStyle: Color.secondary
        )
    }
}

struct SearchActivityWebTimelineExpandedPanel: View {
    let content: SearchActivityTimelineSupport.ViewContent
    let contextLabel: String?
    let sourceEnrichmentState: SearchSourceEnrichmentState

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            panelHeader

            if !content.presentation.queries.isEmpty {
                SearchActivityWebTimelineQueryChipRow(queries: content.presentation.queries)
            }

            sourcesSection
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, 2)
        .padding(.bottom, JinSpacing.xSmall)
    }

    private var panelHeader: some View {
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
    }

    @ViewBuilder
    private var sourcesSection: some View {
        if !content.presentation.sources.isEmpty {
            sourceSummaryRow

            SearchActivityWebTimelineSourceCardsRow(
                sources: content.presentation.sources,
                sourceEnrichmentState: sourceEnrichmentState
            )
        } else {
            SearchActivityWebTimelineNoSourcesNotice()
        }
    }

    private var sourceSummaryRow: some View {
        HStack(spacing: JinSpacing.small) {
            Text(content.presentation.sourceSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

            CopyToPasteboardButton(
                text: sourceEnrichmentState.preferredURLStrings(for: content.presentation.sources).joined(separator: "\n"),
                helpText: "Copy links",
                copiedHelpText: "Copied links",
                useProminentStyle: false
            )
            .frame(width: 16, height: 16)
        }
    }
}

private struct SearchActivityWebTimelineSourceAvatarStrip: View {
    let sources: [SearchSource]
    let sourceEnrichmentState: SearchSourceEnrichmentState

    var body: some View {
        let presentations = SearchActivityCollapsedSourceSupport.distinctPresentations(
            sources.map(sourceEnrichmentState.renderPresentation(for:))
        )

        HStack(spacing: -3) {
            ForEach(
                Array(presentations.prefix(SearchActivityWebTimelinePanelConfig.maxVisibleAvatars)),
                id: \.self
            ) { sourcePresentation in
                SearchSourceAvatarView(
                    host: sourcePresentation.host,
                    fallbackText: sourcePresentation.hostDisplayInitial,
                    kind: sourcePresentation.kind,
                    size: 20
                )
            }

            if presentations.count > SearchActivityWebTimelinePanelConfig.maxVisibleAvatars {
                Text("+\(presentations.count - SearchActivityWebTimelinePanelConfig.maxVisibleAvatars)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(JinSemanticColor.subtleSurface))
                    .overlay(
                        Circle()
                            .stroke(JinSemanticColor.separator.opacity(0.6), lineWidth: JinStrokeWidth.hairline)
                    )
            }
        }
    }
}

private struct SearchActivityWebTimelineQueryChipRow: View {
    let queries: [String]

    var body: some View {
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
}

private struct SearchActivityWebTimelineSourceCardsRow: View {
    let sources: [SearchSource]
    let sourceEnrichmentState: SearchSourceEnrichmentState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: JinSpacing.xSmall + 1) {
                ForEach(sources) { source in
                    SearchSourceCardView(presentation: sourceEnrichmentState.renderPresentation(for: source))
                }
            }
            .padding(.horizontal, JinStrokeWidth.emphasized)
            .padding(.vertical, JinStrokeWidth.emphasized)
        }
    }
}

private struct SearchActivityWebTimelineNoSourcesNotice: View {
    var body: some View {
        Text("This response does not include source URLs.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }
}
