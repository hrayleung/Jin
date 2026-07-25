import Foundation

/// Recognises the `<br>` family of raw-HTML tags.
///
/// Raw HTML is otherwise rendered literally by policy (see `HTMLBlockView`),
/// but `<br>` is not markup the user wants to *read* — it is the only way to
/// put a hard line break inside a GFM table cell, so models emit it constantly
/// in tables and headings. Rendering it verbatim showed the literal text
/// `<br>` in an inline-code chip where a line break belonged.
///
/// Accepted spellings: `<br>`, `<br/>`, `<br />`, any capitalisation, and the
/// stray `</br>` (invalid HTML, but browsers parse it as a break too).
/// Anything carrying attributes — `<br class="x">` — is left literal.
enum MarkdownHTMLLineBreak {
    /// True when `rawHTML` is exactly one `<br>`-family tag.
    static func isBreakTag(_ rawHTML: some StringProtocol) -> Bool {
        var rest = Substring(rawHTML)
        guard rest.first == "<" else { return false }
        rest = rest.dropFirst()
        if rest.first == "/" { rest = rest.dropFirst() }
        guard let b = rest.first, b == "b" || b == "B" else { return false }
        rest = rest.dropFirst()
        guard let r = rest.first, r == "r" || r == "R" else { return false }
        rest = rest.dropFirst()
        rest = rest.drop(while: \.isWhitespace)
        if rest.first == "/" { rest = rest.dropFirst() }
        return rest == ">"
    }

    /// True when an HTML *block* contains nothing but `<br>` tags and
    /// whitespace — i.e. it is vertical spacing rather than content, and
    /// should not surface as a literal code box.
    ///
    /// Deliberately strict: a CommonMark type-7 HTML block runs to the next
    /// blank line, so `<br>\ntext` is one block whose text must still render.
    static func isBreakOnlyBlock(_ rawHTML: some StringProtocol) -> Bool {
        var rest = Substring(rawHTML).drop(while: \.isWhitespace)
        var sawBreak = false
        while !rest.isEmpty {
            guard rest.first == "<", let close = rest.firstIndex(of: ">") else { return false }
            guard isBreakTag(rest[rest.startIndex...close]) else { return false }
            sawBreak = true
            rest = rest[rest.index(after: close)...].drop(while: \.isWhitespace)
        }
        return sawBreak
    }
}
