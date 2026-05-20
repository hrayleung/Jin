import AppKit
import SwiftUI

/// Renders a `NativeMarkdownGroup.prose` payload as a single `NSTextView`.
///
/// Hosts every paragraph/heading in the group inside one text-storage; this
/// is the per-message NSTextView collapse that's the central perf win over
/// the original block-per-view design — fewer views in the SwiftUI tree,
/// fewer CALayers, fewer NSHostingView bridges, and TextKit gets to do its
/// paragraph-style identity caching across the whole run.
struct ProseGroupView: View {
    let attributedString: NSAttributedString
    let plainText: String
    let linkURLs: [LinkRange]
    let path: [Int]

    @Environment(\.markdownTheme) private var theme
    @Environment(\.nativeMarkdownAnchor) private var anchor

    var body: some View {
        let info = anchor?.layout.groupInfos[NativeAnchorLayout.BlockHash(path: path)]
        AttributedTextBlock(
            attributedString: attributedString,
            links: linkURLs,
            blockID: info?.id,
            aggregator: anchor?.aggregator
        )
        // Align first-text baseline with the first line of the prose group's
        // first paragraph. Same `ascender + leading` formula as
        // `ParagraphView` — see `MarkdownTheme.firstLineBaselineFromTop`
        // for the reason `lineHeightMultiple` is *not* part of this value.
        .alignmentGuide(.firstTextBaseline) { _ in theme.firstLineBaselineFromTop }
        .padding(.bottom, 4)
    }
}
