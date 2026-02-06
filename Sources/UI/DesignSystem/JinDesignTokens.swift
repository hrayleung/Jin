import SwiftUI

enum JinSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
}

enum JinRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
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
    static let subtleSurface = Color.secondary.opacity(0.08)
    static let subtleSurfaceStrong = Color.secondary.opacity(0.1)
    static let selectedSurface = Color.accentColor.opacity(0.14)
    static let selectedStroke = Color.accentColor.opacity(0.35)
    static let accentSurface = Color.accentColor.opacity(0.1)
}
