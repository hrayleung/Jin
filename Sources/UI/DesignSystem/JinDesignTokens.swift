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

    // MARK: - Surface system (4 distinct levels, each with a single purpose)
    //
    // Design philosophy:
    //
    //   1. ONE content surface. Chat content, top bar, sheets, detail panes —
    //      everything that's a "work surface" uses `surface`. Feels like one
    //      coherent canvas, not a patchwork of greys.
    //   2. SIDEBAR recedes. `canvas` is the only place that's distinctly
    //      dimmer. Hierarchy felt at a glance.
    //   3. INLINE tints for islands. `subtleSurface` for pills, code blocks,
    //      search field. Small "different element" cues, not whole panels.
    //   4. ONE anchor card. `raisedSurface` (pure white in light) is reserved
    //      for the composer — the single element that visibly *lifts* off the
    //      page with a defined border and soft shadow. Nothing else uses it.
    //
    // Anything that previously needed `panelSurface` / `textSurface` /
    // `detailSurface` collapses into these 4 — those names live on as
    // aliases for migration but resolve to the same value as one of the four.

    /// Sidebar / global window chrome that should visually recede.
    static let canvas = Color(
        light: Color(sRGB: 0xECECF0),
        dark: Color(sRGB: 0x18181A)
    )

    /// The single "content surface" — chat content, top bar, sheets, detail
    /// panes all share this. Forms the visual baseline of the app.
    static let surface = Color(
        light: Color(sRGB: 0xFBFBFC),
        dark: Color(sRGB: 0x1E1E20)
    )

    /// Inline tinted island — pills, code-block bgs, search field,
    /// inline "this is a different region" cues. Never a whole panel.
    static let subtleSurface = Color(
        light: Color(sRGB: 0xF4F4F7),
        dark: Color(sRGB: 0x2A2A2D)
    )

    /// The single anchor card (composer). Pairs with `borderEmphasized` +
    /// `shadowSubtle` to literally lift off the page. Don't use elsewhere.
    static let raisedSurface = Color(
        light: Color(sRGB: 0xFFFFFF),
        dark: Color(sRGB: 0x28282B)
    )

    // MARK: - Aliases for legacy call sites

    /// Was a separate "secondary panel" tone; now collapses to the inline
    /// tinted island. Keep using `subtleSurface` directly in new code.
    static let panelSurface = subtleSurface

    /// Was a separate "text field" tone; now collapses to the anchor surface
    /// for dedicated text input fields. New code can use `raisedSurface`.
    static let textSurface = raisedSurface

    /// Deprecated — kept only for the dark-mode strong variant of subtle.
    /// In light, identical to `subtleSurface`.
    static let subtleSurfaceStrong = subtleSurface

    // MARK: - Borders (opacity-on-axis so they adapt to any surface)

    static let borderSubtle = Color(
        light: Color(sRGB: 0x000000, opacity: 0.06),
        dark: Color(sRGB: 0xFFFFFF, opacity: 0.08)
    )

    static let borderEmphasized = Color(
        light: Color(sRGB: 0x000000, opacity: 0.14),
        dark: Color(sRGB: 0xFFFFFF, opacity: 0.16)
    )

    // MARK: - Shadows

    static let shadowSubtle = Color(
        light: Color(sRGB: 0x000000, opacity: 0.04),
        dark: Color(sRGB: 0x000000, opacity: 0.30)
    )

    static let shadowElevated = Color(
        light: Color(sRGB: 0x000000, opacity: 0.08),
        dark: Color(sRGB: 0x000000, opacity: 0.45)
    )

    // MARK: - Accent / Selected (tinted, never filled)

    static let selectedSurface = Color(
        light: Color.accentColor.opacity(0.10),
        dark: Color.accentColor.opacity(0.18)
    )

    static let selectedStroke = Color(
        light: Color.accentColor.opacity(0.35),
        dark: Color.accentColor.opacity(0.40)
    )

    static let accentSurface = Color(
        light: Color.accentColor.opacity(0.10),
        dark: Color.accentColor.opacity(0.16)
    )

    static let quoteAccent = Color.accentColor.opacity(0.88)

    // MARK: - Text

    /// Fixed-contrast secondary text. Use for labels and headings that need
    /// to remain readable across any surface.
    static let textSecondary = Color(
        light: Color(sRGB: 0x000000, opacity: 0.55),
        dark: Color(sRGB: 0xFFFFFF, opacity: 0.62)
    )

    /// Tertiary text/icon. System `.tertiary` resolves to ~26% black in light
    /// mode — readable in theory, painful in practice for small fonts and
    /// chevron glyphs. This token is the design system's deliberately bumped
    /// tertiary: still clearly subordinate to `.secondary` (read as "metadata"
    /// not content), but actually legible. Use for timestamps, disclosure
    /// chevrons, hint text, line numbers.
    static let textTertiary = Color(
        light: Color(sRGB: 0x000000, opacity: 0.42),
        dark: Color(sRGB: 0xFFFFFF, opacity: 0.55)
    )

    // MARK: - Reader

    static let quoteSurface = Color(
        light: Color(sRGB: 0xF4F4F7),
        dark: Color(sRGB: 0xFFFFFF, opacity: 0.04)
    )

    static let quoteSurfaceStrong = Color(
        light: Color(sRGB: 0xEAEAEE),
        dark: Color(sRGB: 0xFFFFFF, opacity: 0.08)
    )

    static let readerHighlight = Color(
        light: Color(.sRGB, red: 0.98, green: 0.93, blue: 0.60, opacity: 0.72),
        dark: Color(.sRGB, red: 0.86, green: 0.68, blue: 0.16, opacity: 0.34)
    )

    // MARK: - Backwards-compatible aliases

    /// Migration alias. Prefer `canvas`.
    static let sidebarSurface = canvas

    /// Migration alias. Sheets and detail panes share the main content
    /// `surface`. They ARE the work surface, not raised cards. Reserve
    /// `raisedSurface` for the composer anchor.
    static let detailSurface = surface

    /// Migration alias. Legacy call sites that re-apply `.opacity(0.3–0.7)`
    /// now produce a clearly visible hairline because the base is already an
    /// opaque-equivalent token (rather than the near-invisible system color).
    static let separator = borderEmphasized
}

extension Color {
    init(sRGB hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    fileprivate init(light: Color, dark: Color) {
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
