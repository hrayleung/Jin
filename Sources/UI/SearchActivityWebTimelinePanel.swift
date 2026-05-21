import SwiftUI

struct SearchActivityWebTimelinePanel: View {
    let content: SearchActivityTimelineSupport.ViewContent
    let isStreaming: Bool
    let contextLabel: String?

    @State private var isExpanded = false
    /// Latched to `true` the first time the user expands. After that the
    /// expanded panel stays mounted in the view tree forever — see the
    /// long comment on `body`.
    @State private var hasEverExpanded = false
    @State private var sourceEnrichmentState = SearchSourceEnrichmentState()
    private let sourceEnrichmentResolver = SearchSourceEnrichmentResolver.live

    var body: some View {
        if hasRenderableContent {
            // **Lazy-mount-then-hide** expand pattern. The earlier
            // versions of this view all destroyed and rebuilt the
            // expanded panel on every collapse/expand cycle. That
            // synchronous reconstruction — 6-10 source cards, each
            // hosting a `WebsiteFaviconView` whose `.task(id: host)`
            // fires the moment it mounts — is what users perceived as
            // "click, pause, then animate": SwiftUI evaluates the new
            // subtree's body on the same frame the animation transaction
            // starts, the body work is in the tens of ms, and the
            // animation can't draw its first frame until that work
            // completes.
            //
            // Thinking blocks don't have this problem because their
            // expanded subtree is just a Text view with no .task; their
            // body work is essentially free.
            //
            // Fix: latch `hasEverExpanded` on first expand, then keep
            // the panel mounted permanently and hide it via
            // `frame(maxHeight: 0).opacity(0).allowsHitTesting(false)`.
            // SwiftUI animates the opacity/frame on a stable identity —
            // no destroy/rebuild, the favicon `@State` survives, and
            // `compositingGroup()` lets the entire subtree fade as one
            // CALayer.
            // Outer spacing is 0 — once `hasEverExpanded` flips, the
            // collapsed panel is still a child of this VStack even when
            // its frame collapses to 0pt, so a non-zero stack spacing
            // would leave a permanent strip of empty space underneath
            // the summary row. The gap that the expanded state needs is
            // applied directly on the panel via animated top padding.
            VStack(alignment: .leading, spacing: 0) {
                SearchActivityWebTimelineCollapsedSummaryRow(
                    content: content,
                    isStreaming: isStreaming,
                    sourceEnrichmentState: sourceEnrichmentState,
                    isExpanded: $isExpanded,
                    onWillExpand: { hasEverExpanded = true }
                )

                if hasEverExpanded {
                    SearchActivityWebTimelineExpandedPanel(
                        content: content,
                        contextLabel: contextLabel,
                        sourceEnrichmentState: sourceEnrichmentState
                    )
                        .padding(.top, isExpanded ? JinSpacing.small + 2 : 0)
                        .frame(maxHeight: isExpanded ? .infinity : 0, alignment: .top)
                        .opacity(isExpanded ? 1 : 0)
                        .clipped()
                        .allowsHitTesting(isExpanded)
                        .accessibilityHidden(!isExpanded)
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
