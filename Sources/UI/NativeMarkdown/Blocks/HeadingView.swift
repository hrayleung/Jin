import AppKit
import SwiftUI

struct HeadingView: View {
    let level: Int
    let run: InlineRun
    let path: [Int]

    @Environment(\.markdownTheme) private var theme
    @Environment(\.nativeMarkdownAnchor) private var anchor

    var body: some View {
        let info = anchor?.layout.headingInfos[NativeAnchorLayout.BlockHash(path: path)]
        // See `MarkdownTheme.firstLineBaselineFromTop` — the formula
        // includes `lineHeightMultiple`, contrary to one round of
        // research findings. Heading paragraphs use a different
        // `lineHeightMultiple` from body, so we route through the
        // heading-specific helper.
        let topPadding: CGFloat = level <= 2 ? 12 : 8
        let baseline = theme.firstLineBaselineFromTop(forHeading: level) + topPadding
        AttributedTextBlock(
            attributedString: applyHeadingFont(to: run.attributedString),
            links: run.linkURLs,
            blockID: info?.id,
            aggregator: anchor?.aggregator
        )
        .padding(.top, topPadding)
        .padding(.bottom, 4)
        .alignmentGuide(.firstTextBaseline) { _ in baseline }
    }

    private func applyHeadingFont(to attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let headingFont = theme.headingFont(forLevel: level)
        let range = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.font, value: headingFont, range: range)
        mutable.addAttribute(
            .paragraphStyle,
            value: theme.headingParagraphStyle(forLevel: level),
            range: range
        )
        return mutable
    }
}
