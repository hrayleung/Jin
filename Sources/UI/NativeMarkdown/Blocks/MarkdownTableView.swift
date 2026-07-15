import AppKit
import SwiftUI

/// GFM table renderer — row/column layout of selectable `AttributedTextBlock`
/// cells. Each cell re-uses the standard inline rendering pipeline.
/// Cross-row+prose selection is intentionally not supported (tables are an
/// out-of-flow block; cells pass no `SelectionAggregator`).
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
        .contextMenu { tableContextMenu }
    }

    @ViewBuilder
    private var tableContextMenu: some View {
        Button("Copy as Markdown") {
            PasteboardSupport.writeString(markdownPlainText(columnCount: max(header.count, rows.map(\.count).max() ?? 0)))
        }
        Button("Copy as TSV") {
            PasteboardSupport.writeString(tsvPlainText())
        }
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
        // Tables historically used SwiftUI Text, which never saw
        // `JinMarkdownLayoutManager`. Round-trip custom inline-code
        // attributes to plain `.backgroundColor` so code still gets a
        // tinted background whether Text or NSTextView draws the cell.
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

        let paragraphStyle = NSMutableParagraphStyle()
        switch alignment {
        case .center:
            paragraphStyle.alignment = .center
        case .right:
            paragraphStyle.alignment = .right
        case .left, .default:
            paragraphStyle.alignment = .left
        }
        if baseAttrs.length > 0 {
            baseAttrs.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: 0, length: baseAttrs.length)
            )
        }

        // Selectable NSTextView cells (no selection aggregator — table text
        // stays out of cross-prose quote/highlight). Native right-click Copy
        // and drag selection work per cell.
        return AttributedTextBlock(
            attributedString: baseAttrs,
            links: cell.linkURLs
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func frameAlignment(for alignment: TableColumnAlignment) -> Alignment {
        switch alignment {
        case .center: return .center
        case .right: return .trailing
        case .left, .default: return .leading
        }
    }

    // MARK: - Plain-text export

    private func markdownPlainText(columnCount: Int) -> String {
        var lines: [String] = []
        lines.append(markdownRow(cells: header, columnCount: columnCount))
        lines.append(markdownSeparator(columnCount: columnCount))
        for row in rows {
            lines.append(markdownRow(cells: row, columnCount: columnCount))
        }
        return lines.joined(separator: "\n")
    }

    private func markdownRow(cells: [InlineRun], columnCount: Int) -> String {
        var parts: [String] = [""]
        for col in 0..<columnCount {
            let text = col < cells.count ? escapeMarkdownCell(cells[col].plainText) : ""
            parts.append(" \(text) ")
        }
        parts.append("")
        return parts.joined(separator: "|")
    }

    private func markdownSeparator(columnCount: Int) -> String {
        var parts: [String] = [""]
        for col in 0..<columnCount {
            let alignment = col < alignments.count ? alignments[col] : .default
            switch alignment {
            case .left:
                parts.append(" :--- ")
            case .center:
                parts.append(" :---: ")
            case .right:
                parts.append(" ---: ")
            case .default:
                parts.append(" --- ")
            }
        }
        parts.append("")
        return parts.joined(separator: "|")
    }

    private func escapeMarkdownCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private func tsvPlainText() -> String {
        var lines: [String] = []
        lines.append(tsvRow(cells: header))
        for row in rows {
            lines.append(tsvRow(cells: row))
        }
        return lines.joined(separator: "\n")
    }

    private func tsvRow(cells: [InlineRun]) -> String {
        cells
            .map { cell in
                cell.plainText
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
            }
            .joined(separator: "\t")
    }
}
