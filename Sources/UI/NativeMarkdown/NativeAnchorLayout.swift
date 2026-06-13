import Foundation

/// Pre-walked layout for the markdown groups of a single anchor (one `.text`
/// `ContentPart`). Produces a flat selectable-text concatenation matching
/// the legacy JS DOM walk's contract, plus per-group / per-leaf
/// `BlockOffsetInfo` so the renderer can register the right view with
/// `SelectionAggregator`.
///
/// After the v2 refactor each contiguous prose run is one `NSTextView` (a
/// `prose` group), so the most common selectable thing is the *group*, not
/// the individual paragraph. `groupInfos` holds the offsets for those
/// aggregated text views. `paragraphInfos` / `headingInfos` still exist —
/// they're populated only by the legacy code path inside complex lists and
/// blockquotes, where individual paragraphs/headings still get their own
/// `ParagraphView` / `HeadingView`.
struct NativeAnchorLayout {
    let flatText: String
    let groupInfos: [BlockHash: SelectionAggregator.BlockOffsetInfo]
    let paragraphInfos: [BlockHash: SelectionAggregator.BlockOffsetInfo]
    let headingInfos: [BlockHash: SelectionAggregator.BlockOffsetInfo]
    let aggregatorBlocks: [SelectionAggregator.BlockOffsetInfo]

    /// Stable identifier for one leaf block based on its tree path. We use a
    /// path of indices through the block tree because SwiftUI views are
    /// value types and we need a deterministic key.
    struct BlockHash: Hashable {
        let path: [Int]
    }
}

enum NativeAnchorLayoutBuilder {
    /// Deterministic per-path block ID. A fresh `UUID()` here would defeat
    /// `SelectionAggregator.update`'s `blocks ==` gate on every streaming
    /// flush (forcing a full highlight re-walk) and grow its
    /// `blockTextViews` registration dictionary without bound — the same
    /// path must yield the same ID across rebuilds. Content changes are
    /// still detected: `BlockOffsetInfo == ` compares `plainText` and
    /// `offsetInAnchor`.
    static func deterministicBlockID(path: [Int]) -> UUID {
        let key = path.map(String.init).joined(separator: ".")
        var high = FNVHasher()
        high.combine("A:" + key)
        var low = FNVHasher()
        low.combine("B:" + key)
        var bytes = [UInt8](repeating: 0, count: 16)
        for offset in 0..<8 {
            bytes[offset] = UInt8(truncatingIfNeeded: high.value >> (8 * UInt64(7 - offset)))
            bytes[8 + offset] = UInt8(truncatingIfNeeded: low.value >> (8 * UInt64(7 - offset)))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40 // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func build(groups: [NativeMarkdownGroup]) -> NativeAnchorLayout {
        var state = State()
        for (groupIndex, group) in groups.enumerated() {
            visit(group: group, path: [groupIndex], state: &state)
        }
        return NativeAnchorLayout(
            flatText: state.flatText,
            groupInfos: state.groupInfos,
            paragraphInfos: state.paragraphInfos,
            headingInfos: state.headingInfos,
            aggregatorBlocks: state.aggregatorBlocks
        )
    }

    private struct State {
        var flatText: String = ""
        var groupInfos: [NativeAnchorLayout.BlockHash: SelectionAggregator.BlockOffsetInfo] = [:]
        var paragraphInfos: [NativeAnchorLayout.BlockHash: SelectionAggregator.BlockOffsetInfo] = [:]
        var headingInfos: [NativeAnchorLayout.BlockHash: SelectionAggregator.BlockOffsetInfo] = [:]
        var aggregatorBlocks: [SelectionAggregator.BlockOffsetInfo] = []

        mutating func appendLineSeparator() {
            if !flatText.isEmpty { flatText.append("\n") }
        }
    }

    private static func visit(group: NativeMarkdownGroup, path: [Int], state: inout State) {
        switch group {
        case .prose(_, let plainText, _, _):
            let id = NativeAnchorLayout.BlockHash(path: path)
            let info = SelectionAggregator.BlockOffsetInfo(
                id: deterministicBlockID(path: path),
                offsetInAnchor: state.flatText.utf16.count,
                plainText: plainText
            )
            state.groupInfos[id] = info
            state.aggregatorBlocks.append(info)
            state.flatText.append(plainText)
            state.appendLineSeparator()

        case .codeBlock(_, let source, _, _):
            state.flatText.append(source)
            state.appendLineSeparator()

        case .table(let header, _, let rows, _):
            for cell in header {
                state.flatText.append(cell.plainText)
                state.flatText.append("\t")
            }
            state.appendLineSeparator()
            for row in rows {
                for cell in row {
                    state.flatText.append(cell.plainText)
                    state.flatText.append("\t")
                }
                state.appendLineSeparator()
            }

        case .math(let latex, _):
            state.flatText.append(latex)
            state.appendLineSeparator()

        case .mermaid:
            break

        case .htmlBlock(let text, _):
            state.flatText.append(text)
            state.appendLineSeparator()

        case .thematicBreak:
            break

        case .complexList(_, _, let items, _, _):
            for (itemIndex, item) in items.enumerated() {
                visitLegacyBlocks(blocks: item.children, path: path + [itemIndex], state: &state)
            }

        case .complexBlockQuote(let children, _):
            // BlockQuoteView preserves the parent path (it does not append
            // its own index) — match it so children's paths line up with
            // what the view dispatches.
            visitLegacyBlocks(blocks: children, path: path, state: &state)
        }
    }

    /// Legacy walker for blocks rendered through `ListView` / `BlockQuoteView`
    /// — individual paragraph/heading registrations populate
    /// `paragraphInfos` / `headingInfos`.
    private static func visitLegacyBlocks(blocks: [NativeMarkdownBlock], path: [Int], state: inout State) {
        for (index, block) in blocks.enumerated() {
            visitLegacyBlock(block: block, path: path + [index], state: &state)
        }
    }

    private static func visitLegacyBlock(block: NativeMarkdownBlock, path: [Int], state: inout State) {
        switch block {
        case .paragraph(let run):
            let id = NativeAnchorLayout.BlockHash(path: path)
            let info = SelectionAggregator.BlockOffsetInfo(
                id: deterministicBlockID(path: path),
                offsetInAnchor: state.flatText.utf16.count,
                plainText: run.plainText
            )
            state.paragraphInfos[id] = info
            state.aggregatorBlocks.append(info)
            state.flatText.append(run.plainText)
            state.appendLineSeparator()

        case .heading(_, let content):
            let id = NativeAnchorLayout.BlockHash(path: path)
            let info = SelectionAggregator.BlockOffsetInfo(
                id: deterministicBlockID(path: path),
                offsetInAnchor: state.flatText.utf16.count,
                plainText: content.plainText
            )
            state.headingInfos[id] = info
            state.aggregatorBlocks.append(info)
            state.flatText.append(content.plainText)
            state.appendLineSeparator()

        case .bulletList(let items, _), .orderedList(_, let items, _):
            for (itemIndex, item) in items.enumerated() {
                visitLegacyBlocks(blocks: item.children, path: path + [itemIndex], state: &state)
            }

        case .blockQuote(let children):
            visitLegacyBlocks(blocks: children, path: path, state: &state)

        case .codeBlock(_, let source, _):
            state.flatText.append(source)
            state.appendLineSeparator()

        case .table(let header, _, let rows):
            for cell in header {
                state.flatText.append(cell.plainText)
                state.flatText.append("\t")
            }
            state.appendLineSeparator()
            for row in rows {
                for cell in row {
                    state.flatText.append(cell.plainText)
                    state.flatText.append("\t")
                }
                state.appendLineSeparator()
            }

        case .thematicBreak:
            break

        case .mathBlock(let latex):
            state.flatText.append(latex)
            state.appendLineSeparator()

        case .mermaidBlock:
            break

        case .htmlBlock(let text):
            state.flatText.append(text)
            state.appendLineSeparator()
        }
    }
}
