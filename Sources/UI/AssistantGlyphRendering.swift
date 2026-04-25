import AppKit
import SwiftUI

/// Shared rules for assistant icons: SF Symbol names, emoji / arbitrary glyphs, or placeholders.
enum AssistantGlyphRendering {
    static func isSFSymbolName(_ s: String) -> Bool {
        NSImage(systemSymbolName: s, accessibilityDescription: nil) != nil
    }

    @ViewBuilder
    static func coreGlyph(
        trimmed: String,
        pointSize: CGFloat,
        weight: Font.Weight = .semibold,
        emptySystemImage: String = "person.crop.circle"
    ) -> some View {
        if trimmed.isEmpty {
            Image(systemName: emptySystemImage)
                .font(.system(size: pointSize, weight: weight))
        } else if isSFSymbolName(trimmed) {
            Image(systemName: trimmed)
                .font(.system(size: pointSize, weight: weight))
        } else {
            Text(trimmed)
                .font(.system(size: pointSize, weight: weight))
        }
    }
}
