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
        let ascender = theme.headingFont(forLevel: level).ascender
        AttributedTextBlock(
            attributedString: applyHeadingFont(to: run.attributedString),
            links: run.linkURLs,
            blockID: info?.id,
            aggregator: anchor?.aggregator
        )
        .alignmentGuide(.firstTextBaseline) { _ in ascender }
        .padding(.top, level <= 2 ? 12 : 8)
        .padding(.bottom, 4)
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
