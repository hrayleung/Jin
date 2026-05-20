import AppKit
import SwiftUI

/// Resolved palette + fonts for the native markdown renderer. Mirrors the CSS
/// custom properties in the old `markdown-template.html`. Re-resolved when
/// font preferences or color scheme change.
struct MarkdownTheme: Equatable {
    let bodyFont: NSFont
    let codeFont: NSFont
    let baseColor: NSColor
    let secondaryColor: NSColor
    let linkColor: NSColor
    let inlineCodeBackground: NSColor
    let inlineCodeBorder: NSColor
    let blockQuoteBorder: NSColor
    let blockQuoteText: NSColor
    let strikethroughLineColor: NSColor

    /// Heading size multipliers relative to `bodyFont.pointSize`.
    static let headingSizeMultipliers: [Int: CGFloat] = [
        1: 1.6,
        2: 1.4,
        3: 1.2,
        4: 1.1,
        5: 1.0,
        6: 1.0,
    ]

    static let inlineCodeSizeMultiplier: CGFloat = 0.88

    static func resolved(
        appFontFamily: String,
        codeFontFamily: String
    ) -> MarkdownTheme {
        let bodySize = JinTypography.chatBodyPointSize(scale: JinTypography.defaultChatMessageScale)
        let body = nsFont(
            familyPreference: appFontFamily,
            size: bodySize,
            fallback: .systemFont(ofSize: bodySize)
        )
        let codeSize = bodySize * inlineCodeSizeMultiplier
        let code = nsFont(
            familyPreference: codeFontFamily,
            size: codeSize,
            fallback: .monospacedSystemFont(ofSize: codeSize, weight: .regular)
        )

        return MarkdownTheme(
            bodyFont: body,
            codeFont: code,
            baseColor: Self.baseColor,
            secondaryColor: Self.secondaryColor,
            linkColor: Self.linkColor,
            inlineCodeBackground: Self.inlineCodeBackground,
            inlineCodeBorder: Self.inlineCodeBorder,
            blockQuoteBorder: Self.blockQuoteBorder,
            blockQuoteText: Self.blockQuoteText,
            strikethroughLineColor: Self.baseColor
        )
    }

    private static func nsFont(
        familyPreference: String,
        size: CGFloat,
        fallback: NSFont
    ) -> NSFont {
        let trimmed = familyPreference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if let font = NSFontManager.shared.font(withFamily: trimmed, traits: [], weight: 5, size: size) {
            return font
        }
        if let font = NSFont(name: trimmed, size: size) {
            return font
        }
        return fallback
    }
}

extension MarkdownTheme {
    /// Body-line-height multiplier roughly matching the WebView template's
    /// `body { line-height: 1.6 }` once you account for the difference between
    /// CSS `line-height` (line-box height) and NSAttributedString's
    /// `lineHeightMultiple` (multiplier on the font's natural leading).
    static let bodyLineHeightMultiple: CGFloat = 1.3
    /// Headings use the same multiplier; CSS inherits the body value so the
    /// WebView did too. Kept as a separate constant so we can tighten later.
    static let headingLineHeightMultiple: CGFloat = 1.2
    static let codeLineHeightMultiple: CGFloat = 1.3

    // Cached, immutable `NSParagraphStyle` singletons. Allocating a new style
    // on every render disables `NSLayoutManager`'s paragraph-style identity
    // caching (it can no longer detect that adjacent paragraphs share a
    // style), which forces redundant glyph layout. Sharing one instance per
    // block kind across the whole process is both cheaper and identity-safe.
    static let cachedBodyParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = bodyLineHeightMultiple
        // Visual breathing room between consecutive body paragraphs within
        // the same prose group, matching the WebView CSS `p { margin-bottom:
        // 0.6em }`. Inter-group spacing (between prose and a code block,
        // table, etc.) is layered on top by the group view's padding.
        style.paragraphSpacing = 6
        return style.copy() as! NSParagraphStyle
    }()

    /// Level-keyed cached heading paragraph styles. Heading levels differ
    /// only in the `paragraphSpacingBefore` we want between them and the
    /// preceding paragraph — h1/h2 get more breathing room than h4-h6 to
    /// match the WebView CSS (`margin-top: 1em` on all headings, but with
    /// larger font sizes the same `em` is visually larger).
    static let cachedHeadingParagraphStyles: [Int: NSParagraphStyle] = {
        var dict: [Int: NSParagraphStyle] = [:]
        for level in 1...6 {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = headingLineHeightMultiple
            style.paragraphSpacingBefore = level <= 2 ? 12 : 8
            style.paragraphSpacing = 4
            dict[level] = (style.copy() as! NSParagraphStyle)
        }
        return dict
    }()

    static let cachedCodeParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = codeLineHeightMultiple
        style.lineBreakMode = .byClipping
        return style.copy() as! NSParagraphStyle
    }()

    var bodyParagraphStyle: NSParagraphStyle { Self.cachedBodyParagraphStyle }

    static func headingParagraphStyle(forLevel level: Int) -> NSParagraphStyle {
        Self.cachedHeadingParagraphStyles[max(1, min(6, level))] ?? Self.cachedBodyParagraphStyle
    }

    func headingParagraphStyle(forLevel level: Int) -> NSParagraphStyle {
        Self.headingParagraphStyle(forLevel: level)
    }

    var codeParagraphStyle: NSParagraphStyle { Self.cachedCodeParagraphStyle }

    func headingFont(forLevel level: Int) -> NSFont {
        let multiplier = Self.headingSizeMultipliers[level] ?? 1.0
        let size = bodyFont.pointSize * multiplier
        if let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(.bold) as NSFontDescriptor? {
            return NSFont(descriptor: descriptor, size: size) ?? NSFont.boldSystemFont(ofSize: size)
        }
        return NSFont.boldSystemFont(ofSize: size)
    }

    func boldFont() -> NSFont {
        let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: descriptor, size: bodyFont.pointSize) ?? NSFont.boldSystemFont(ofSize: bodyFont.pointSize)
    }

    func italicFont() -> NSFont {
        let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: bodyFont.pointSize) ?? bodyFont
    }

    func boldItalicFont() -> NSFont {
        let descriptor = bodyFont.fontDescriptor.withSymbolicTraits([.bold, .italic])
        return NSFont(descriptor: descriptor, size: bodyFont.pointSize) ?? bodyFont
    }
}

private extension MarkdownTheme {
    static let baseColor = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(srgbRed: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF7 / 255.0, alpha: 1)
        default:
            return NSColor(srgbRed: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x1F / 255.0, alpha: 1)
        }
    }

    static let secondaryColor = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(white: 1.0, alpha: 0.62)
        default:
            return NSColor(white: 0.0, alpha: 0.55)
        }
    }

    static let linkColor = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(srgbRed: 0x4C / 255.0, green: 0xA6 / 255.0, blue: 0xFF / 255.0, alpha: 1)
        default:
            return NSColor(srgbRed: 0x00 / 255.0, green: 0x66 / 255.0, blue: 0xCC / 255.0, alpha: 1)
        }
    }

    static let inlineCodeBackground = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(calibratedHue: 220.0 / 360.0, saturation: 0.13, brightness: 0.20, alpha: 0.96)
        default:
            return NSColor(calibratedHue: 230.0 / 360.0, saturation: 0.01, brightness: 0.96, alpha: 0.96)
        }
    }

    static let inlineCodeBorder = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(white: 1.0, alpha: 0.12)
        default:
            return NSColor(white: 0.0, alpha: 0.10)
        }
    }

    static let blockQuoteBorder = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(white: 1.0, alpha: 0.18)
        default:
            return NSColor(white: 0.0, alpha: 0.18)
        }
    }

    static let blockQuoteText = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(white: 1.0, alpha: 0.72)
        default:
            return NSColor(white: 0.0, alpha: 0.66)
        }
    }
}

private struct MarkdownThemeKey: EnvironmentKey {
    static let defaultValue: MarkdownTheme = .resolved(appFontFamily: "", codeFontFamily: "")
}

extension EnvironmentValues {
    var markdownTheme: MarkdownTheme {
        get { self[MarkdownThemeKey.self] }
        set { self[MarkdownThemeKey.self] = newValue }
    }
}
