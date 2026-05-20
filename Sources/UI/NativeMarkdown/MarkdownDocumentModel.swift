import AppKit
import Foundation

/// Content-hash + positional identity for `NativeMarkdownBlock`. Used as the
/// `ForEach` ID so SwiftUI reuses stable views when streaming.
struct NativeMarkdownBlockID: Hashable {
    let position: Int
    let signature: UInt64
}

/// Result of `MarkdownInlineRenderer` for one block's inline content.
struct InlineRun: Equatable {
    let attributedString: NSAttributedString
    /// Concatenation of inline `Text` runs only — used for selection offset
    /// bookkeeping. Must match what the JS DOM walk produces for the same
    /// markdown so persisted highlight offsets line up.
    let plainText: String
    let linkURLs: [LinkRange]

    static let empty = InlineRun(
        attributedString: NSAttributedString(),
        plainText: "",
        linkURLs: []
    )

    static func == (lhs: InlineRun, rhs: InlineRun) -> Bool {
        lhs.plainText == rhs.plainText
            && lhs.attributedString.isEqual(to: rhs.attributedString)
            && lhs.linkURLs == rhs.linkURLs
    }
}

struct LinkRange: Equatable {
    let range: NSRange
    let url: URL
}

/// One list item — `nil` checkbox means "not a GFM task list item".
struct ListItemContent: Equatable {
    let checkbox: Bool?
    let children: [NativeMarkdownBlock]
}

enum TableColumnAlignment: Equatable {
    case `default`
    case left
    case center
    case right
}

/// One unit of rendered markdown content. Mapped 1:1 from `swift-markdown`
/// block nodes by `MarkdownASTWalker`.
enum NativeMarkdownBlock: Equatable {
    case paragraph(InlineRun)
    case heading(level: Int, content: InlineRun)
    case bulletList(items: [ListItemContent], tight: Bool)
    case orderedList(start: Int, items: [ListItemContent], tight: Bool)
    case blockQuote(children: [NativeMarkdownBlock])
    case codeBlock(language: String?, source: String, isStreamingTail: Bool)
    case table(header: [InlineRun], alignments: [TableColumnAlignment], rows: [[InlineRun]])
    case thematicBreak
    case mathBlock(latex: String)
    case mermaidBlock(source: String)
    case htmlBlock(text: String)
}

extension NativeMarkdownBlock {
    /// FNV-1a content hash used for `NativeMarkdownBlockID.signature`.
    var contentSignature: UInt64 {
        var hasher = FNVHasher()
        switch self {
        case .paragraph(let run):
            hasher.combine("p")
            hasher.combine(run.plainText)
        case .heading(let level, let run):
            hasher.combine("h\(level)")
            hasher.combine(run.plainText)
        case .bulletList(let items, _):
            hasher.combine("ul")
            for item in items {
                hasher.combine(itemSignature(item))
            }
        case .orderedList(let start, let items, _):
            hasher.combine("ol-\(start)")
            for item in items {
                hasher.combine(itemSignature(item))
            }
        case .blockQuote(let children):
            hasher.combine("bq")
            for child in children {
                hasher.combine(String(child.contentSignature))
            }
        case .codeBlock(let language, let source, let streaming):
            hasher.combine("code-\(language ?? "")-\(streaming)")
            hasher.combine(source)
        case .table(let header, _, let rows):
            hasher.combine("table")
            for cell in header { hasher.combine(cell.plainText) }
            for row in rows {
                for cell in row { hasher.combine(cell.plainText) }
            }
        case .thematicBreak:
            hasher.combine("hr")
        case .mathBlock(let latex):
            hasher.combine("math")
            hasher.combine(latex)
        case .mermaidBlock(let source):
            hasher.combine("mermaid")
            hasher.combine(source)
        case .htmlBlock(let text):
            hasher.combine("html")
            hasher.combine(text)
        }
        return hasher.value
    }

    private func itemSignature(_ item: ListItemContent) -> String {
        var combined = item.checkbox.map { $0 ? "[x]" : "[ ]" } ?? "[-]"
        for child in item.children {
            combined.append("|\(child.contentSignature)")
        }
        return combined
    }
}

/// FNV-1a 64-bit hash. Stable across process restarts (unlike Swift's hasher).
struct FNVHasher {
    private(set) var value: UInt64 = 0xcbf29ce484222325
    private static let prime: UInt64 = 0x100000001b3

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value &*= Self.prime
        }
        // Field separator so "ab"+"c" hashes differently from "a"+"bc".
        value ^= 0
        value &*= Self.prime
    }
}
