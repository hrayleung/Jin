import AppKit
import os
import SwiftUI

/// Resolved palette + fonts for the native markdown renderer. Mirrors the CSS
/// custom properties in the old `markdown-template.html`. Re-resolved when
/// font preferences or color scheme change.
struct MarkdownTheme: Equatable, @unchecked Sendable {
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

    /// Heading size multipliers relative to `bodyFont.pointSize`. Tuned
    /// to match the GitHub-flavoured-markdown CSS ladder users are
    /// already familiar with from WebView-rendered chat — the previous
    /// 1.6/1.4/1.2/1.1 ladder collapsed h3 and h4 into "looks like
    /// body text", which is why structural section headings stopped
    /// reading as headings at all.
    ///
    /// GitHub reference: h1 = 2em, h2 = 1.5em, h3 = 1.25em, h4 = 1em.
    /// We bump h4 a hair above body so even short side-headings keep
    /// some visual weight.
    static let headingSizeMultipliers: [Int: CGFloat] = [
        1: 2.0,
        2: 1.5,
        3: 1.25,
        4: 1.1,
        5: 1.0,
        6: 0.95,
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

    /// Level-keyed cached heading paragraph styles. Heading levels get
    /// more `paragraphSpacingBefore` than `paragraphSpacing` (after) so
    /// the heading visually "owns" the section below it — matching the
    /// WebView CSS `margin-top` >> `margin-bottom` convention every
    /// markdown reader follows.
    ///
    /// The previous 12/8/4 values made section breaks (h2/h3) feel
    /// glued to the preceding paragraph; bumping the leading spacing
    /// gives the eye a clear "new section starts here" signal.
    static let cachedHeadingParagraphStyles: [Int: NSParagraphStyle] = {
        var dict: [Int: NSParagraphStyle] = [:]
        for level in 1...6 {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = headingLineHeightMultiple
            switch level {
            case 1: style.paragraphSpacingBefore = 24
            case 2: style.paragraphSpacingBefore = 20
            case 3: style.paragraphSpacingBefore = 16
            case 4: style.paragraphSpacingBefore = 12
            default: style.paragraphSpacingBefore = 10
            }
            style.paragraphSpacing = 6
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

    /// Process-wide cache of indent-variant paragraph styles (folded lists,
    /// folded blockquotes). Same rationale as the singletons above: a fresh
    /// `NSMutableParagraphStyle` per render defeats `NSLayoutManager`'s
    /// paragraph-style identity caching. Keyed by the quantized geometry, so
    /// every list item at the same indent level across the whole app shares
    /// one instance. (Immutable `NSParagraphStyle` copies are thread-safe;
    /// the box exists only because the Sendable conformance is unavailable.)
    private struct CachedStyleBox: @unchecked Sendable { let style: NSParagraphStyle }
    private static let indentedStyleCache = OSAllocatedUnfairLock<[String: CachedStyleBox]>(initialState: [:])

    /// Body-based style for folded list items / quote paragraphs: hanging
    /// indent with the item text column at `headIndent`.
    static func listParagraphStyle(
        firstLineHeadIndent: CGFloat,
        headIndent: CGFloat,
        paragraphSpacing: CGFloat
    ) -> NSParagraphStyle {
        let key = "body|\(Int(firstLineHeadIndent))|\(Int(headIndent))|\(Int(paragraphSpacing))"
        let box = indentedStyleCache.withLock { cache -> CachedStyleBox in
            if let cached = cache[key] { return cached }
            let style = (cachedBodyParagraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.firstLineHeadIndent = firstLineHeadIndent
            style.headIndent = headIndent
            style.tabStops = [NSTextTab(textAlignment: .left, location: headIndent)]
            style.defaultTabInterval = 22
            style.paragraphSpacing = paragraphSpacing
            let boxed = CachedStyleBox(style: style.copy() as! NSParagraphStyle)
            cache[key] = boxed
            return boxed
        }
        return box.style
    }

    /// Heading style indented for folded blockquote content.
    static func indentedHeadingParagraphStyle(level: Int, indent: CGFloat) -> NSParagraphStyle {
        let key = "h\(max(1, min(6, level)))|\(Int(indent))"
        let box = indentedStyleCache.withLock { cache -> CachedStyleBox in
            if let cached = cache[key] { return cached }
            let base = headingParagraphStyle(forLevel: level)
            let style = (base.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            let boxed = CachedStyleBox(style: style.copy() as! NSParagraphStyle)
            cache[key] = boxed
            return boxed
        }
        return box.style
    }

    static func headingParagraphStyle(forLevel level: Int) -> NSParagraphStyle {
        Self.cachedHeadingParagraphStyles[max(1, min(6, level))] ?? Self.cachedBodyParagraphStyle
    }

    func headingParagraphStyle(forLevel level: Int) -> NSParagraphStyle {
        Self.headingParagraphStyle(forLevel: level)
    }

    var codeParagraphStyle: NSParagraphStyle { Self.cachedCodeParagraphStyle }

    /// Distance from a TextKit-1 `NSTextView`'s top edge down to the first
    /// text baseline, configured with `textContainerInset = .zero`,
    /// `lineFragmentPadding = 0`, and the paragraph style's
    /// `lineHeightMultiple` set to `M`. Used by
    /// `HStack(alignment: .firstTextBaseline)` to align sibling markers
    /// (list bullets, ordered numbers, task checkboxes) to the prose's
    /// first line.
    ///
    /// **Empirically derived** by feeding a known string through a real
    /// `NSLayoutManager` and reading
    /// `lineFragmentRect.minY + location(forGlyphAt: 0).y`. With
    /// `font = SF Pro 14pt` and `M = 1.3`:
    ///
    /// - `naturalLineHeight = ascender + |descender| + leading = 17pt`
    /// - `lineFragmentRect.height = naturalLineHeight × M = 22.1pt`
    /// - **measured baseline = 19.1pt** (≈ `22.1 − 2.95 = lineFragment − |descender|`)
    ///
    /// Earlier we used `ascender + leading` (13.54pt) on the assumption
    /// that `lineHeightMultiple` only stretched the bottom — that was
    /// wrong: the typesetter does push the baseline down by the
    /// multiplier-induced inflation, which is why bullets were floating
    /// ~5pt above the prose they were supposed to be aligned with.
    ///
    /// The formula below matches AppKit's measured behaviour to within
    /// 0.1pt across the font sizes we care about.
    static func firstLineBaselineFromTop(font: NSFont, lineHeightMultiple: CGFloat) -> CGFloat {
        let descender = abs(font.descender)
        let naturalLineHeight = font.ascender + descender + font.leading
        return naturalLineHeight * lineHeightMultiple - descender
    }

    var firstLineBaselineFromTop: CGFloat {
        Self.firstLineBaselineFromTop(
            font: bodyFont,
            lineHeightMultiple: Self.bodyLineHeightMultiple
        )
    }

    func firstLineBaselineFromTop(forHeading level: Int) -> CGFloat {
        Self.firstLineBaselineFromTop(
            font: headingFont(forLevel: level),
            lineHeightMultiple: Self.headingLineHeightMultiple
        )
    }

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
