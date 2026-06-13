import AppKit
import Foundation

/// Render-time grouping of `NativeMarkdownBlock`s. Created by
/// `NativeMarkdownGroupBuilder` after parsing and consumed by
/// `NativeMarkdownView`.
///
/// The point of grouping is to collapse consecutive prose blocks
/// (paragraph + heading and, eventually, simple lists/blockquotes) into a
/// single `NSAttributedString` rendered by a single `NSTextView`. The
/// per-block-NSTextView architecture from the first cut of the native
/// markdown renderer worked but had Bear/Notes-incompatible scaling: a long
/// conversation kept hundreds of `NSTextView`s alive in `LazyVStack` (which
/// only lazily *initializes* — it doesn't recycle), and the cumulative
/// layer hierarchy was what made scroll stutter compared to the WebView
/// (which is a single GPU-composited surface). Grouping is the path Apple
/// and Bear/Notes/Mail all take: one big text view that handles many
/// paragraphs at once, leaving only inherently widget-shaped content
/// (code blocks, tables, math, mermaid) as separate views.
enum NativeMarkdownGroup: Equatable {
    /// Run of prose blocks rendered as one `NSAttributedString` in one
    /// `NSTextView`. `plainText` matches the attributed string's content —
    /// it's what the selection aggregator reports as the group's
    /// selectable text. `linkURLs` are the link ranges already translated
    /// to be relative to the combined `attributedString`.
    case prose(attributedString: NSAttributedString, plainText: String, linkURLs: [LinkRange], signature: UInt64)

    case codeBlock(language: String?, source: String, isStreamingTail: Bool, signature: UInt64)
    case table(header: [InlineRun], alignments: [TableColumnAlignment], rows: [[InlineRun]], signature: UInt64)
    case math(latex: String, signature: UInt64)
    case mermaid(source: String, signature: UInt64)
    case htmlBlock(text: String, signature: UInt64)
    case thematicBreak(signature: UInt64)
    /// List that couldn't be flattened into a prose group (loose list, or
    /// items containing non-paragraph children). Rendered with the existing
    /// per-item `ListView` path so we don't lose any behavior.
    case complexList(kind: ComplexListKind, start: Int, items: [ListItemContent], tight: Bool, signature: UInt64)
    /// Block quote with non-paragraph children. Same fallback rationale as
    /// `complexList`.
    case complexBlockQuote(children: [NativeMarkdownBlock], signature: UInt64)

    enum ComplexListKind {
        case bullet
        case ordered
    }
}

extension NativeMarkdownGroup {
    /// Content-addressable signature used as the `ForEach` id so SwiftUI
    /// stably re-uses the underlying `NSTextView` when only a sibling
    /// group's content changes during streaming.
    var contentSignature: UInt64 {
        switch self {
        case .prose(_, _, _, let sig),
             .codeBlock(_, _, _, let sig),
             .table(_, _, _, let sig),
             .math(_, let sig),
             .mermaid(_, let sig),
             .htmlBlock(_, let sig),
             .thematicBreak(let sig),
             .complexList(_, _, _, _, let sig),
             .complexBlockQuote(_, let sig):
            return sig
        }
    }

    /// Positional/structural identity tag used (with the group's position) as
    /// the `ForEach` id. Deliberately depends ONLY on the case kind, NOT on the
    /// content — so the trailing prose group's `NSTextView` is REUSED (and
    /// updated in place via `contentSignature`) as text streams in, instead of
    /// being torn down and rebuilt every flush. A genuinely new block opening at
    /// a position (e.g. a code fence after prose) shifts positions / changes the
    /// kind at that slot, which correctly forces a fresh view there.
    var kindTag: UInt64 {
        switch self {
        case .prose: return 1
        case .codeBlock: return 2
        case .table: return 3
        case .math: return 4
        case .mermaid: return 5
        case .htmlBlock: return 6
        case .thematicBreak: return 7
        case .complexList: return 8
        case .complexBlockQuote: return 9
        }
    }
}
