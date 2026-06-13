import AppKit
import SwiftUI

struct ParagraphView: View {
    let run: InlineRun
    let path: [Int]

    @Environment(\.markdownTheme) private var theme
    @Environment(\.nativeMarkdownAnchor) private var anchor

    var body: some View {
        let info = anchor?.layout.paragraphInfos[NativeAnchorLayout.BlockHash(path: path)]
        let baseline = theme.firstLineBaselineFromTop
        AttributedTextBlock(
            attributedString: NativeMarkdownAttributedStringStyling.applyParagraphStyle(
                to: run.attributedString,
                style: theme.bodyParagraphStyle
            ),
            links: run.linkURLs,
            blockID: info?.id,
            aggregator: anchor?.aggregator
        )
        // Expose the first line's baseline so HStacks with
        // `.firstTextBaseline` alignment (list rows, etc.) line up the
        // bullet / number marker with the prose's first line instead of
        // defaulting to the view's bottom edge. The value MUST be
        // `ascender + leading` (see `MarkdownTheme.firstLineBaselineFromTop`)
        // — `ascender` alone underestimates the real baseline by the
        // font's leading and was the cause of list markers floating high.
        .alignmentGuide(.firstTextBaseline) { _ in baseline }
        .padding(.bottom, 6)
    }
}

/// Small helper used by every block renderer to bake a paragraph style into
/// an already-built attributed string. Kept here so the call sites stay terse
/// and the policy lives in one place.
enum NativeMarkdownAttributedStringStyling {
    static func applyParagraphStyle(to attributed: NSAttributedString, style: NSParagraphStyle) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
    }
}
