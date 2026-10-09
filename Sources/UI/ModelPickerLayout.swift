import SwiftUI

/// Shared columns for search, section headings, model rows, and agent rows.
enum ModelPickerLayout {
    static let width: CGFloat = 340
    static let height: CGFloat = 440
    // macOS plain List already contributes this outer cell gutter. Keep its
    // row insets at zero so search and list content share the same columns.
    static let rowInset: CGFloat = 8
    static let contentInset: CGFloat = 6
    static let symbolWidth: CGFloat = 14
    static let labelSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 28

    static let searchInset = rowInset + contentInset
    static let headingInset = contentInset + symbolWidth + labelSpacing
}
