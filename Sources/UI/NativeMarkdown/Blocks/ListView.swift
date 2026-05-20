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
                .padding(.top, 1)

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
            Text("•")
                .font(.system(size: theme.bodyFont.pointSize, weight: .regular))
                .foregroundStyle(Color(nsColor: theme.secondaryColor))
        case .ordered(let n):
            Text("\(n).")
                .font(.system(size: theme.bodyFont.pointSize * 0.92, weight: .regular, design: .default))
                .foregroundStyle(Color(nsColor: theme.secondaryColor))
        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: theme.bodyFont.pointSize, weight: .regular))
                .foregroundStyle(checked ? Color.accentColor : Color(nsColor: theme.secondaryColor))
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
