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
            // **Performance-critical layout structure**. The previous version
            // had two compounding problems:
            //
            // 1. `spacing: isExpanded ? small : 0` made the VStack's spacing
            //    itself part of the animation, which forces SwiftUI to
            //    re-measure the entire stack on every animation frame
            //    instead of just animating one subview's insertion.
            // 2. `.animation(.easeInOut, value: isExpanded)` on the VStack
            //    AND `withAnimation` inside the collapsed row's button
            //    (see `SearchActivityWebTimelineCollapsedSummaryRow`) both
            //    fire on the same state change — two competing transactions
            //    for the same `isExpanded` toggle, which SwiftUI resolves
            //    by waiting for the full new subtree (sources, favicons,
            //    etc.) to construct before either animation can start.
            //    That construction wait is what users perceive as "click
            //    then pause then animate".
            //
            // Now: fixed spacing, no implicit `.animation`, expanded panel
            // expresses its appear/disappear with a single `.transition`
            // driven by the explicit `withAnimation` in the toggle button.
            // `compositingGroup()` wraps the animated subtree so SwiftUI
            // composites it as one CALayer during the animation instead
            // of re-blending every descendant per frame.
            VStack(alignment: .leading, spacing: JinSpacing.small) {
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
                        .compositingGroup()
                }
            }
            .clipped()
            .task(id: SearchSourceEnrichmentState.taskKey(for: content.presentation.sources)) {
                sourceEnrichmentState = await sourceEnrichmentResolver.resolve(
                    sources: content.presentation.sources,
                    state: sourceEnrichmentState
                )
            }
        }
    }

    private var hasRenderableContent: Bool {
        !content.presentation.sources.isEmpty
            || !content.presentation.queries.isEmpty
            || (isStreaming && content.hasRunningActivity)
    }
}
