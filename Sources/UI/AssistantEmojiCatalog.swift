import Foundation

/// Loads the Unicode RGI emoji set from bundled `emoji-test.txt` (UTS #51), matching the ordering
/// used by Apple’s emoji keyboard on macOS.
enum AssistantEmojiCatalog {
    private static let searchLocale = Locale(identifier: "en_US_POSIX")

    struct Section: Identifiable, Hashable {
        var id: String { title }
        let title: String
        let emojis: [String]
    }

    private static let lock = NSLock()
    private static var didLoad = false
    private static var cachedSections: [Section] = []
    private static var cachedSearch: [String: String] = [:]

    static var sections: [Section] {
        loadIfNeeded()
        return cachedSections
    }

    /// Lowercased English name (from Unicode data) plus the glyph for plain-text search.
    static func searchHaystack(for emoji: String) -> String {
        loadIfNeeded()
        if let s = cachedSearch[emoji] { return s }
        return normalizeSearchText(emoji)
    }

    static func matchesSearchQuery(_ query: String, emoji: String) -> Bool {
        let needle = normalizeSearchText(query)
        guard !needle.isEmpty else { return true }
        return searchHaystack(for: emoji).contains(needle)
    }

    private static func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if didLoad { return }
        didLoad = true
        cachedSections = []
        cachedSearch = [:]

        guard let url = Bundle.module.url(forResource: "emoji-test", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8)
        else {
            return
        }

        var currentGroup = "Emoji"
        var currentSubgroup = ""
        var bucket: [String] = []
        var seenInGroup = Set<String>()
        var sectionsOut: [Section] = []

        func flushBucket() {
            guard !bucket.isEmpty else { return }
            sectionsOut.append(Section(title: currentGroup, emojis: bucket))
            bucket.removeAll(keepingCapacity: true)
            seenInGroup.removeAll(keepingCapacity: true)
        }

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("# group:") {
                flushBucket()
                currentGroup = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
                currentSubgroup = ""
                continue
            }
            if trimmed.hasPrefix("# subgroup:") {
                currentSubgroup = trimmed.dropFirst(11).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.first == "#" || trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: ";", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let status = parts[1].trimmingCharacters(in: .whitespaces)
            guard status.contains("fully-qualified") else { continue }

            let codeField = parts[0].trimmingCharacters(in: .whitespaces)
            guard let emoji = Self.string(fromHexField: codeField) else { continue }

            let comment = parts[1...].joined(separator: ";")
            let name = Self.annotationName(fromComment: comment)

            if seenInGroup.insert(emoji).inserted {
                bucket.append(emoji)
                cachedSearch[emoji] = buildSearchHaystack(
                    name: name,
                    group: currentGroup,
                    subgroup: currentSubgroup,
                    emoji: emoji
                )
            }
        }
        flushBucket()

        cachedSections = sectionsOut
    }

    private static func string(fromHexField field: String) -> String? {
        let tokens = field.split(whereSeparator: \.isWhitespace)
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(tokens.count)
        for t in tokens {
            guard let v = UInt32(t, radix: 16), let s = UnicodeScalar(v) else { return nil }
            scalars.append(s)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func annotationName(fromComment comment: String) -> String {
        guard let hash = comment.firstIndex(of: "#") else {
            return ""
        }
        let tail = comment[comment.index(after: hash)...].trimmingCharacters(in: .whitespaces)
        if let range = tail.range(of: #"E\d+\.\d+\s+"#, options: .regularExpression) {
            return String(tail[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return tail
    }

    private static func buildSearchHaystack(name: String, group: String, subgroup: String, emoji: String) -> String {
        [
            name,
            group,
            subgroup.replacingOccurrences(of: "-", with: " "),
            emoji
        ]
        .map(normalizeSearchText)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private static func normalizeSearchText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: searchLocale)
            .lowercased(with: searchLocale)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
