import AppKit
import SwiftUI

struct BulletListView: View {
    let items: [ListItemContent]
    let tight: Bool
    let path: [Int]
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: tight ? 2 : 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                ListItemRow(marker: .bullet, item: item, tight: tight, path: path + [offset])
            }
        }
        .padding(.vertical, 2)
    }
}

struct OrderedListView: View {
    let start: Int
    let items: [ListItemContent]
    let tight: Bool
    let path: [Int]
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: tight ? 2 : 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                ListItemRow(marker: .ordered(start + offset), item: item, tight: tight, path: path + [offset])
            }
        }
        .padding(.vertical, 2)
    }
}

enum ListMarker {
    case bullet
    case ordered(Int)
    case task(Bool)
}

struct ListItemRow: View {
    let marker: ListMarker
    let item: ListItemContent
    let tight: Bool
    let path: [Int]

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            markerView
                .frame(width: markerWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: tight ? 2 : 6) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { offset, block in
                    NativeBlockView(block: block, path: path + [offset])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var markerView: some View {
        switch effectiveMarker {
        case .bullet:
            // Geometry-centered dot instead of `Text("•")`. SF Pro's
            // bullet glyph (U+2022) sits near the cap-height of the
            // capital letters, so under `.firstTextBaseline` alignment
            // it visually floated above bold body text.
            //
            // Math: SwiftUI's HStack aligns every child's `firstTextBaseline`
            // alignment-guide value onto a shared y line. Our prose
            // (NSTextView wrapped in NSViewRepresentable) reports its
            // baseline via `MarkdownTheme.firstLineBaselineFromTop`.
            // For the dot to look "on the same line as the prose", its
            // geometric center should sit on the prose's x-height
            // midline — i.e., `xHeight/2` ABOVE the prose baseline.
            //
            // The alignment-guide value is the *distance from this view's
            // top edge to where its baseline sits in its own coordinate
            // space*. With a `width × height` Circle frame, the circle's
            // center is at `height/2` from the top. We want that center
            // to land `xHeight/2` above the shared baseline line, so we
            // report `center + xHeight/2 = height/2 + xHeight/2`.
            //
            // (The earlier `dim[.bottom] + xHeight/2` was off by half the
            // circle diameter — `bottom = height`, not `height/2` — which
            // pushed the dot 2pt too high.)
            Circle()
                .fill(Color(nsColor: theme.secondaryColor))
                .frame(width: 4, height: 4)
                .alignmentGuide(.firstTextBaseline) { dim in
                    dim.height * 0.5 + theme.bodyFont.xHeight * 0.5
                }
        case .ordered(let n):
            // Same point size as the body font — using `0.92 *` (the
            // previous value) gave the number a smaller ascent, which
            // shifted its baseline ~1pt up relative to the prose. Keeping
            // both at the same size lets SwiftUI's implicit baseline
            // alignment do the right thing.
            Text("\(n).")
                .font(.system(size: theme.bodyFont.pointSize, weight: .regular, design: .default))
                .foregroundStyle(Color(nsColor: theme.secondaryColor))
        case .task(let checked):
            // SF Symbols ship with their own internal baseline; for a
            // square checkbox we want the visual center on the prose
            // x-height midline, same as the bullet. Use the same
            // height/2 + xHeight/2 formula.
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: theme.bodyFont.pointSize, weight: .regular))
                .foregroundStyle(checked ? Color.accentColor : Color(nsColor: theme.secondaryColor))
                .alignmentGuide(.firstTextBaseline) { dim in
                    dim.height * 0.5 + theme.bodyFont.xHeight * 0.5
                }
        }
    }

    private var effectiveMarker: ListMarker {
        if let checked = item.checkbox {
            return .task(checked)
        }
        return marker
    }

    private var markerWidth: CGFloat {
        switch effectiveMarker {
        case .bullet: return 12
        case .ordered: return 22
        case .task: return 16
        }
    }
}
