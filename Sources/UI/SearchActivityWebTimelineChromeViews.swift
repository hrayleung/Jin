import SwiftUI

private enum SearchActivityWebTimelinePanelConfig {
    static let maxVisibleAvatars = 10
}

struct SearchActivityWebTimelineCollapsedSummaryRow: View {
    let content: SearchActivityTimelineSupport.ViewContent
    let isStreaming: Bool
    let sourceEnrichmentState: SearchSourceEnrichmentState
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            summaryRowContent
        }
        .buttonStyle(.plain)
    }

    private var summaryRowContent: some View {
        HStack(spacing: JinSpacing.small) {
            disclosureIndicator

            summaryIcon
            summaryTitleContent

            streamingIndicator

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var summaryIcon: some View {
        Image(systemName: content.presentation.summarySystemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var summaryTitleContent: some View {
        if content.presentation.sources.isEmpty {
            Text(content.presentation.sectionTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            SearchActivityWebTimelineSourceAvatarStrip(
                sources: content.presentation.sources,
                sourceEnrichmentState: sourceEnrichmentState
            )
        }
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        if isStreaming && content.hasRunningActivity {
            ProgressView()
                .scaleEffect(0.5)
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
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
        HStack(spacing: -4) {
            ForEach(Array(sources.prefix(SearchActivityWebTimelinePanelConfig.maxVisibleAvatars)), id: \.id) { source in
                let sourcePresentation = sourceEnrichmentState.renderPresentation(for: source)
                SearchSourceAvatarView(
                    host: sourcePresentation.host,
                    fallbackText: sourcePresentation.hostDisplayInitial,
                    kind: sourcePresentation.kind,
                    size: 24
                )
            }

            if sources.count > SearchActivityWebTimelinePanelConfig.maxVisibleAvatars {
                Text("+\(sources.count - SearchActivityWebTimelinePanelConfig.maxVisibleAvatars)")
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
