import AppKit

extension MessageHighlightColorStyle {
    /// `NSColor` swatch used to paint persisted highlights inside the native
    /// renderer. Mirrors the `--reader-highlight-bg` CSS variable in
    /// `markdown-template.html` (rounded-rect polish via a custom layout
    /// manager arrives in Phase 8).
    var color: NSColor {
        switch self {
        case .readerYellow:
            return NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
                case .darkAqua:
                    return NSColor(srgbRed: 0.84, green: 0.63, blue: 0.13, alpha: 0.34)
                default:
                    return NSColor(srgbRed: 0.98, green: 0.91, blue: 0.52, alpha: 0.78)
                }
            }
        }
    }
}
