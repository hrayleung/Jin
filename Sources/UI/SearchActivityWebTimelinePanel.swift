import SwiftUI

struct SearchActivityWebTimelinePanel: View {
    let content: SearchActivityTimelineSupport.ViewContent
    let isStreaming: Bool
    let contextLabel: String?
    var onExpansionChanged: () -> Void = {}

    @State private var isExpanded = false
    /// Latched to `true` the first time the user expands. After that the
    /// expanded panel stays mounted in the view tree forever — see the
    /// long comment on `body`.
    @State private var hasEverExpanded = false
    /// Bumped on every toggle so a deferred first-expand `Task` cannot
    /// reopen the panel after the user has already collapsed it.
    @State private var expandGeneration = 0
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
            // Fix: latch `hasEverExpanded` on first expand, then keep
            // the panel mounted and drive open/close through
            // `JinCollapsibleContent` (animatable finite height, not
            // `maxHeight: .infinity`). Favicon `@State` survives, and
            // every spring frame reports a real height to the timeline
            // table so the row grows with the panel instead of snapping.
            //
            // Outer spacing is 0 — once `hasEverExpanded` flips, the
            // collapsed panel is still a child of this VStack even when
            // its frame collapses to 0pt, so a non-zero stack spacing
            // would leave a permanent strip of empty space underneath
            // the summary row. The gap that the expanded state needs is
            // applied as top padding inside the collapsible content.
            VStack(alignment: .leading, spacing: 0) {
                SearchActivityWebTimelineCollapsedSummaryRow(
                    content: content,
                    isStreaming: isStreaming,
                    sourceEnrichmentState: sourceEnrichmentState,
                    isExpanded: isExpanded,
                    onToggle: toggleExpanded
                )

                if hasEverExpanded {
                    JinCollapsibleContent(isExpanded: isExpanded) {
                        SearchActivityWebTimelineExpandedPanel(
                            content: content,
                            contextLabel: contextLabel,
                            sourceEnrichmentState: sourceEnrichmentState
                        )
                        .padding(.top, JinSpacing.small + 2)
                    }
                }
            }
            .clipped()
            .onChange(of: isExpanded) { _, _ in
                onExpansionChanged()
            }
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

    /// First expand mounts collapsed so the height probe can capture a finite
    /// target, then springs open. Subsequent toggles animate height in place
    /// (expand and collapse share the same clip spring — no staged snap).
    private func toggleExpanded() {
        expandGeneration &+= 1
        let generation = expandGeneration

        if isExpanded {
            withAnimation(JinMotion.disclosure(expanding: false)) {
                isExpanded = false
            }
            return
        }

        if hasEverExpanded {
            withAnimation(JinMotion.disclosure(expanding: true)) {
                isExpanded = true
            }
            return
        }

        // Mount collapsed first so `JinCollapsibleContent` measures a solid
        // height target before the spring runs.
        hasEverExpanded = true
        Task { @MainActor in
            await Task.yield()
            guard generation == expandGeneration else { return }
            withAnimation(JinMotion.disclosure(expanding: true)) {
                isExpanded = true
            }
        }
    }
}
