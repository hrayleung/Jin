import AppKit
import SwiftUI

/// GFM table renderer — SwiftUI Grid of `AttributedTextBlock` cells. Each cell
/// re-uses the standard inline rendering pipeline. Cross-row+prose selection
/// is intentionally not supported (tables are an out-of-flow block).
struct MarkdownTableView: View {
    let header: [InlineRun]
    let alignments: [TableColumnAlignment]
    let rows: [[InlineRun]]
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        VStack(spacing: 0) {
            tableRow(cells: header, isHeader: true, columnCount: columnCount)
                .background(JinSemanticColor.subtleSurface)
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                tableRow(cells: row, isHeader: false, columnCount: columnCount)
                Divider().opacity(0.4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.small)
                .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.regular)
        )
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.small))
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tableRow(cells: [InlineRun], isHeader: Bool, columnCount: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { col in
                let cell = col < cells.count ? cells[col] : InlineRun.empty
                let alignment = col < alignments.count ? alignments[col] : .default
                cellView(cell: cell, alignment: alignment, isHeader: isHeader)
                if col < columnCount - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func cellView(cell: InlineRun, alignment: TableColumnAlignment, isHeader: Bool) -> some View {
        let baseAttrs = NSMutableAttributedString(attributedString: cell.attributedString)
        // Tables use SwiftUI Text under the hood, which doesn't go through
        // `JinMarkdownLayoutManager`, so it never sees `.jinInlineCodeBackground`.
        // Round-trip the custom attribute back to plain `.backgroundColor`
        // so inline code at least gets a flat tinted background inside cells.
        baseAttrs.enumerateAttribute(
            .jinInlineCodeBackground,
            in: NSRange(location: 0, length: baseAttrs.length),
            options: []
        ) { value, range, _ in
            guard let color = value as? NSColor else { return }
            baseAttrs.addAttribute(.backgroundColor, value: color, range: range)
        }
        if isHeader {
            let bold = theme.boldFont()
            baseAttrs.enumerateAttribute(.font, in: NSRange(location: 0, length: baseAttrs.length), options: []) { value, range, _ in
                let originalFont = (value as? NSFont) ?? theme.bodyFont
                let traits = originalFont.fontDescriptor.symbolicTraits.union(.bold)
                let descriptor = originalFont.fontDescriptor.withSymbolicTraits(traits)
                let resolved = NSFont(descriptor: descriptor, size: originalFont.pointSize) ?? bold
                baseAttrs.addAttribute(.font, value: resolved, range: range)
            }
        }
        let textAlignment: TextAlignment
        let frameAlignment: Alignment
        switch alignment {
        case .center:
            textAlignment = .center; frameAlignment = .center
        case .right:
            textAlignment = .trailing; frameAlignment = .trailing
        case .left, .default:
            textAlignment = .leading; frameAlignment = .leading
        }

        // SwiftUI Text — table cells don't need NSTextView selection
        // coordination (selection across cells doesn't behave like prose
        // anywhere), and a 10×5 table previously allocated 50 TextKit
        // stacks. Switching to Text saves the bulk of that memory.
        let swiftAttr = (try? AttributedString(baseAttrs, including: \.swiftUI))
            ?? AttributedString(baseAttrs)
        return Text(swiftAttr)
            .multilineTextAlignment(textAlignment)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}
