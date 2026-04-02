import SwiftUI

enum JinSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
}

enum JinRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 18
}

enum JinStrokeWidth {
    static let hairline: CGFloat = 0.5
    static let regular: CGFloat = 1
    static let emphasized: CGFloat = 2
}

enum JinControlMetrics {
    static let iconButtonHitSize: CGFloat = 28
    static let iconButtonGlyphSize: CGFloat = 12
    static let assistantGlyphSize: CGFloat = 18
    static let assistantLargeGlyphSize: CGFloat = 28
}

enum JinSemanticColor {
    static let sidebarSurface = Color(nsColor: .windowBackgroundColor)
    static let panelSurface = Color(nsColor: .controlBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let detailSurface = Color(nsColor: .textBackgroundColor)
    static let textSurface = Color(nsColor: .textBackgroundColor)
    static let raisedSurface = Color(nsColor: .textBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let subtleSurface = Color.primary.opacity(0.055)
    static let subtleSurfaceStrong = Color.primary.opacity(0.085)
    static let selectedSurface = Color.accentColor.opacity(0.14)
    static let selectedStroke = Color.accentColor.opacity(0.35)
    static let accentSurface = Color.accentColor.opacity(0.1)
    static let quoteAccent = Color.accentColor.opacity(0.88)
    static let quoteSurface = Color(
        light: Color(red: 0.155, green: 0.155, blue: 0.155).opacity(0.055),
        dark: Color.white.opacity(0.04)
    )
    static let quoteSurfaceStrong = Color(
        light: Color.black.opacity(0.08),
        dark: Color.white.opacity(0.08)
    )
    static let readerHighlight = Color(
        light: Color(red: 0.98, green: 0.93, blue: 0.60).opacity(0.72),
        dark: Color(red: 0.86, green: 0.68, blue: 0.16).opacity(0.34)
    )
}

private extension Color {
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }
}
