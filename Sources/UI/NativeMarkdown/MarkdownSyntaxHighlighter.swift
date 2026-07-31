import AppKit
import Foundation
import Highlighter
import os

/// Classification produced by `LanguageTokenizer`. Each enum case maps to a
/// theme color set by `MarkdownTheme.SyntaxPalette`.
enum SyntaxClassification: Hashable {
    case keyword
    case type
    case string
    case number
    case comment
    case function
    case property
    case `operator`
    case punctuation
    case literal
    case attribute
    case tag
    case selector
}

/// Pattern + classification pair. Patterns are applied in order; later
/// patterns can overwrite earlier ones, so put more-specific patterns last
/// (e.g., strings before regex, comments last so they override everything).
struct SyntaxPattern {
    let regex: NSRegularExpression
    let classification: SyntaxClassification
    let captureGroup: Int

    init?(_ pattern: String, classification: SyntaxClassification, captureGroup: Int = 0, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        self.regex = regex
        self.classification = classification
        self.captureGroup = captureGroup
    }
}

/// Common protocol for per-language tokenizers.
protocol LanguageTokenizer {
    var patterns: [SyntaxPattern] { get }
}

/// Process-wide code highlighter dispatch. Prefer Highlight.js via
/// HighlighterSwift for finished, known-language code blocks; fall back to
/// the local tokenizer for streaming, unsupported languages, and failure
/// cases where readability matters more than perfect token coverage.
enum MarkdownSyntaxHighlighter {
    /// Hard cap to keep visible code blocks from monopolizing the render path.
    /// Large blocks stay readable as plain monospace text and can still be copied.
    static let maxHighlightLength = 50_000
    private static let highlightJSRenderer = HighlightJSRenderer()
    /// Count-capped AND byte-capped: entries retain the source (in the key)
    /// plus the fully-attributed result, so 192 blocks near the 50 KB source
    /// ceiling would otherwise hold tens of MB.
    private static let highlightCache = OSAllocatedUnfairLock<HighlightCacheStorage>(
        initialState: HighlightCacheStorage(capacity: 192, costBudget: 8 * 1024 * 1024)
    )

    /// Full purge for memory-pressure response. Highlights re-run off-main on
    /// the next render, so the refill is invisible.
    static func purgeCacheForMemoryPressure() {
        highlightCache.withLock { $0.removeAll() }
    }

    static func highlight(
        _ source: String,
        language: String?,
        theme: MarkdownTheme,
        isDarkMode: Bool? = nil,
        useFastFallback: Bool = false
    ) -> NSAttributedString {
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.codeFont,
            .foregroundColor: theme.baseColor,
        ]
        guard !source.isEmpty else { return NSAttributedString(string: "", attributes: baseAttrs) }
        guard source.count <= maxHighlightLength else {
            return NSAttributedString(string: source, attributes: baseAttrs)
        }

        let normalized = LanguageAliases.normalize(language)
        let darkMode = resolvedDarkMode(isDarkMode)
        let cacheKey = HighlightCacheKey(
            source: source,
            language: normalized,
            fontName: theme.codeFont.fontName,
            fontSize: theme.codeFont.pointSize,
            isDarkMode: darkMode,
            useFastFallback: useFastFallback
        )
        if let cached = highlightCache.withLock({ $0.lookup(cacheKey) }) {
            return cached.value
        }

        let result: NSAttributedString
        if !useFastFallback,
           let normalized,
           let highlighted = highlightJSRenderer.highlight(
                source,
                language: normalized,
                theme: theme,
                isDarkMode: darkMode
           ) {
            if tokenizer(for: normalized) != nil {
                result = fallbackHighlight(source, language: normalized, theme: theme, base: highlighted)
            } else {
                result = highlighted
            }
        } else {
            result = fallbackHighlight(source, language: normalized, theme: theme)
        }

        let resultBox = HighlightCacheBox(result)
        highlightCache.withLock { $0.insert(resultBox, for: cacheKey) }
        return result
    }

    static func highlightJSThemeName(isDarkMode: Bool) -> String {
        isDarkMode ? "github-dark" : "github"
    }

    private static func fallbackHighlight(
        _ source: String,
        language: String?,
        theme: MarkdownTheme,
        base: NSAttributedString? = nil
    ) -> NSAttributedString {
        let palette = SyntaxPalette.resolved()
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.codeFont,
            .foregroundColor: theme.baseColor,
        ]
        let attributed = base.map(NSMutableAttributedString.init(attributedString:)) ??
            NSMutableAttributedString(string: source, attributes: baseAttrs)
        guard let tokenizer = tokenizer(for: language) else { return attributed }

        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        for pattern in tokenizer.patterns {
            let matches = pattern.regex.matches(in: source, options: [], range: fullRange)
            for match in matches {
                let group = pattern.captureGroup
                let range = group < match.numberOfRanges ? match.range(at: group) : match.range
                guard range.location != NSNotFound else { continue }
                attributed.addAttribute(
                    .foregroundColor,
                    value: palette.color(for: pattern.classification),
                    range: range
                )
            }
        }
        return attributed
    }

    private static func resolvedDarkMode(_ explicitValue: Bool?) -> Bool {
        if let explicitValue { return explicitValue }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func tokenizer(for language: String?) -> LanguageTokenizer? {
        guard let language else { return nil }
        switch language {
        case "swift": return SwiftTokenizer()
        case "python": return PythonTokenizer()
        case "javascript": return JavaScriptTokenizer()
        case "typescript": return TypeScriptTokenizer()
        case "bash": return BashTokenizer()
        case "json": return JSONTokenizer()
        case "yaml": return YAMLTokenizer()
        case "html": return HTMLTokenizer()
        case "css": return CSSTokenizer()
        case "go": return GoTokenizer()
        case "rust": return RustTokenizer()
        case "sql": return SQLTokenizer()
        case "zig": return ZigTokenizer()
        default: return nil
        }
    }
}

private struct HighlightCacheKey: Hashable, Sendable {
    let source: String
    let language: String?
    let fontName: String
    let fontSize: CGFloat
    let isDarkMode: Bool
    let useFastFallback: Bool
    let sourceFingerprint: UInt64
    let sourceByteCount: Int

    init(
        source: String,
        language: String?,
        fontName: String,
        fontSize: CGFloat,
        isDarkMode: Bool,
        useFastFallback: Bool
    ) {
        self.source = source
        self.language = language
        self.fontName = fontName
        self.fontSize = fontSize
        self.isDarkMode = isDarkMode
        self.useFastFallback = useFastFallback
        var fingerprint = FNVHasher()
        fingerprint.combine(source)
        self.sourceFingerprint = fingerprint.value
        self.sourceByteCount = source.utf8.count
    }

    static func == (lhs: HighlightCacheKey, rhs: HighlightCacheKey) -> Bool {
        lhs.sourceFingerprint == rhs.sourceFingerprint
            && lhs.sourceByteCount == rhs.sourceByteCount
            && lhs.language == rhs.language
            && lhs.fontName == rhs.fontName
            && lhs.fontSize == rhs.fontSize
            && lhs.isDarkMode == rhs.isDarkMode
            && lhs.useFastFallback == rhs.useFastFallback
            && lhs.source == rhs.source
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sourceFingerprint)
        hasher.combine(sourceByteCount)
        hasher.combine(language)
        hasher.combine(fontName)
        hasher.combine(fontSize)
        hasher.combine(isDarkMode)
        hasher.combine(useFastFallback)
    }
}

private final class HighlightCacheBox: @unchecked Sendable {
    let value: NSAttributedString

    init(_ value: NSAttributedString) {
        self.value = value
    }
}

private struct HighlightCacheStorage: @unchecked Sendable {
    private struct Entry {
        let box: HighlightCacheBox
        let cost: Int
        var lastAccess: UInt64
    }

    private var entries: [HighlightCacheKey: Entry] = [:]
    private var accessClock: UInt64 = 0
    private var totalCost = 0
    let capacity: Int
    let costBudget: Int

    init(capacity: Int, costBudget: Int) {
        self.capacity = capacity
        self.costBudget = costBudget
    }

    mutating func lookup(_ key: HighlightCacheKey) -> HighlightCacheBox? {
        guard var entry = entries[key] else { return nil }
        accessClock &+= 1
        entry.lastAccess = accessClock
        entries[key] = entry
        return entry.box
    }

    mutating func insert(_ box: HighlightCacheBox, for key: HighlightCacheKey) {
        accessClock &+= 1
        // ~3× source bytes: the source retained by the key, the UTF-16
        // backing of the attributed result, and its attribute-run table.
        let cost = 256 + key.sourceByteCount * 3
        if let replaced = entries[key] {
            totalCost -= replaced.cost
        }
        entries[key] = Entry(box: box, cost: cost, lastAccess: accessClock)
        totalCost += cost
        while entries.count > capacity || totalCost > costBudget {
            guard entries.count > 1, let oldest = entries.min(by: {
                $0.value.lastAccess < $1.value.lastAccess
            }) else { break }
            totalCost -= oldest.value.cost
            entries[oldest.key] = nil
        }
    }

    mutating func removeAll() {
        entries.removeAll()
        totalCost = 0
    }
}

private final class HighlightJSRenderer {
    private let lock = NSLock()
    private var highlighter: Highlighter?
    private var supportedLanguages: Set<String>?
    private var configuredThemeName: String?
    private var configuredFontName: String?
    private var configuredFontSize: CGFloat?

    func highlight(
        _ source: String,
        language: String,
        theme: MarkdownTheme,
        isDarkMode: Bool
    ) -> NSAttributedString? {
        lock.lock()
        defer { lock.unlock() }

        guard let highlighter = highlighterInstance() else { return nil }
        guard supports(language: language, highlighter: highlighter) else { return nil }
        guard configure(highlighter: highlighter, theme: theme, isDarkMode: isDarkMode) else {
            return nil
        }

        highlighter.ignoreIllegals = true
        guard let highlighted = highlighter.highlight(source, as: language, doFastRender: true) else {
            return nil
        }
        let normalized = normalize(highlighted, theme: theme)
        return hasMeaningfulHighlight(in: normalized) ? normalized : nil
    }

    private func highlighterInstance() -> Highlighter? {
        if let highlighter { return highlighter }
        guard let highlighter = Highlighter() else { return nil }
        self.highlighter = highlighter
        return highlighter
    }

    private func supports(language: String, highlighter: Highlighter) -> Bool {
        if supportedLanguages == nil {
            supportedLanguages = Set(highlighter.supportedLanguages())
        }
        return supportedLanguages?.contains(language) == true
    }

    private func configure(
        highlighter: Highlighter,
        theme: MarkdownTheme,
        isDarkMode: Bool
    ) -> Bool {
        let themeName = MarkdownSyntaxHighlighter.highlightJSThemeName(isDarkMode: isDarkMode)
        let fontName = theme.codeFont.fontName
        let fontSize = theme.codeFont.pointSize
        guard configuredThemeName != themeName ||
              configuredFontName != fontName ||
              configuredFontSize != fontSize else {
            return true
        }

        guard highlighter.setTheme(themeName, withFont: fontName, ofSize: fontSize) else {
            return false
        }
        configuredThemeName = themeName
        configuredFontName = fontName
        configuredFontSize = fontSize
        return true
    }

    private func normalize(_ highlighted: NSAttributedString, theme: MarkdownTheme) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: highlighted)
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else { return mutable }

        mutable.addAttribute(.paragraphStyle, value: theme.codeParagraphStyle, range: fullRange)
        mutable.removeAttribute(.backgroundColor, range: fullRange)

        var fontUpdates: [(NSRange, NSFont)] = []
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            fontUpdates.append((range, codeFont(matching: value as? NSFont, baseFont: theme.codeFont)))
        }
        for (range, font) in fontUpdates {
            mutable.addAttribute(.font, value: font, range: range)
        }

        var missingColorRanges: [NSRange] = []
        mutable.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil {
                missingColorRanges.append(range)
            }
        }
        for range in missingColorRanges {
            mutable.addAttribute(.foregroundColor, value: theme.baseColor, range: range)
        }
        return mutable
    }

    private func hasMeaningfulHighlight(in attributed: NSAttributedString) -> Bool {
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return false }

        let baseColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let baseFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let baseTraits = syntaxTraits(baseFont)

        var hasDistinctStyle = false
        attributed.enumerateAttributes(in: fullRange) { attributes, _, stop in
            let color = attributes[.foregroundColor] as? NSColor
            let font = attributes[.font] as? NSFont
            if !colorsEqual(color, baseColor) || syntaxTraits(font) != baseTraits {
                hasDistinctStyle = true
                stop.pointee = true
            }
        }
        return hasDistinctStyle
    }

    private func codeFont(matching sourceFont: NSFont?, baseFont: NSFont) -> NSFont {
        guard let sourceFont else { return baseFont }
        let sourceTraits = sourceFont.fontDescriptor.symbolicTraits
        let wantedTraits = sourceTraits.intersection([.bold, .italic])
        guard !wantedTraits.isEmpty else {
            return baseFont
        }
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(wantedTraits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    private func syntaxTraits(_ font: NSFont?) -> NSFontDescriptor.SymbolicTraits {
        font?.fontDescriptor.symbolicTraits.intersection([.bold, .italic]) ?? []
    }

    private func colorsEqual(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return lhs.isEqual(rhs)
        default:
            return false
        }
    }
}

/// Normalizes fence language strings (`ts` → `typescript`, `sh` → `bash`,
/// etc.) so the tokenizer dispatch is straightforward.
enum LanguageAliases {
    static func normalize(_ language: String?) -> String? {
        guard let raw = language?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw {
        case "js", "jsx", "node", "nodejs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "sh", "shell", "zsh", "ksh": return "bash"
        case "py", "python3", "py3": return "python"
        case "yml": return "yaml"
        case "rs": return "rust"
        case "golang": return "go"
        case "html5", "xhtml": return "html"
        case "scss", "less", "sass": return "css"
        case "psql", "mysql", "postgres", "postgresql", "sqlite": return "sql"
        default: return raw
        }
    }
}

/// Palette resolved per appearance — values mirror the Prism "one-light" /
/// "one-dark" tones used in the JS bundle.
private struct SyntaxPalette {
    let keyword: NSColor
    let type: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let function: NSColor
    let property: NSColor
    let `operator`: NSColor
    let punctuation: NSColor
    let literal: NSColor
    let attribute: NSColor
    let tag: NSColor
    let selector: NSColor

    func color(for classification: SyntaxClassification) -> NSColor {
        switch classification {
        case .keyword: return keyword
        case .type: return type
        case .string: return string
        case .number: return number
        case .comment: return comment
        case .function: return function
        case .property: return property
        case .operator: return `operator`
        case .punctuation: return punctuation
        case .literal: return literal
        case .attribute: return attribute
        case .tag: return tag
        case .selector: return selector
        }
    }

    static func resolved() -> SyntaxPalette {
        SyntaxPalette(
            keyword: dynamic(light: 0xA626A4, dark: 0xC678DD),
            type: dynamic(light: 0xC18401, dark: 0xE5C07B),
            string: dynamic(light: 0x50A14F, dark: 0x98C379),
            number: dynamic(light: 0x986801, dark: 0xD19A66),
            comment: dynamic(light: 0xA0A1A7, dark: 0x7F848E),
            function: dynamic(light: 0x4078F2, dark: 0x61AFEF),
            property: dynamic(light: 0xE45649, dark: 0xE06C75),
            operator: dynamic(light: 0x0184BC, dark: 0x56B6C2),
            punctuation: dynamic(light: 0x383A42, dark: 0xABB2BF),
            literal: dynamic(light: 0x986801, dark: 0xD19A66),
            attribute: dynamic(light: 0xC18401, dark: 0xE5C07B),
            tag: dynamic(light: 0xE45649, dark: 0xE06C75),
            selector: dynamic(light: 0xE45649, dark: 0xE06C75)
        )
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }
}
