import SwiftUI

struct SearchActivityWebTimelinePanel: View {
    let content: SearchActivityTimelineSupport.ViewContent
    let isStreaming: Bool
    let contextLabel: String?

    @State private var isExpanded = false
    @State private var sourceEnrichmentState = SearchSourceEnrichmentState()
    private let sourceEnrichmentResolver = SearchSourceEnrichmentResolver.live

    var body: some View {
        if hasRenderableContent {
            VStack(alignment: .leading, spacing: isExpanded ? JinSpacing.small : 0) {
                SearchActivityWebTimelineCollapsedSummaryRow(
                    content: content,
                    isStreaming: isStreaming,
                    sourceEnrichmentState: sourceEnrichmentState,
                    isExpanded: $isExpanded
                )

                if isExpanded {
                    SearchActivityWebTimelineExpandedPanel(
                        content: content,
                        contextLabel: contextLabel,
                        sourceEnrichmentState: sourceEnrichmentState
                    )
                        .padding(.top, 2)
                        .transition(.opacity)
                }
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
            .task(id: SearchSourceEnrichmentState.taskKey(for: content.presentation.sources)) {
                sourceEnrichmentState = await sourceEnrichmentResolver.resolve(
                    sources: content.presentation.sources,
                    state: sourceEnrichmentState
                )
            }
        }
    }

    private var hasRenderableContent: Bool {
        !content.presentation.sources.isEmpty || !content.presentation.queries.isEmpty
    }
}
