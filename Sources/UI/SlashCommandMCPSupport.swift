import Foundation

struct SlashCommandMCPServerItem: Identifiable, Equatable {
    let id: String
    let name: String
    let isSelected: Bool

    init(id: String, name: String, isSelected: Bool) {
        self.id = id
        self.name = name.trimmedNonEmpty ?? id.trimmedNonEmpty ?? "MCP Server"
        self.isSelected = isSelected
    }
}

enum SlashCommandDetection {
    /// Maximum number of characters scanned backward from end-of-string when
    /// looking for the start of an active slash-command token. Keeps the
    /// per-keystroke precheck and detection bounded by trailing-token length
    /// rather than full message length.
    private static let activeTokenLookbackLimit = 256

    static func detectFilter(in text: String) -> String? {
        guard let slashIndex = activeSlashIndex(in: text) else { return nil }
        let filterStart = text.index(after: slashIndex)
        return String(text[filterStart..<text.endIndex])
    }

    static func removeSlashToken(from text: String) -> String {
        guard let slashIndex = activeSlashIndex(in: text) else { return text }
        var result = text
        result.removeSubrange(slashIndex..<text.endIndex)
        return result
    }

    /// Cheap precheck: returns false only when we're certain no active
    /// slash-command token exists at end-of-string. Walks back from the end
    /// until it either sees a `/` (possible token), whitespace (definitely no
    /// active token), or hits the lookback limit. False positives are fine —
    /// they just fall through to the full detection.
    static func mayContainActiveToken(in text: String) -> Bool {
        var index = text.endIndex
        var stepsRemaining = activeTokenLookbackLimit
        while index > text.startIndex, stepsRemaining > 0 {
            let prev = text.index(before: index)
            let char = text[prev]
            if char == "/" { return true }
            if char.isWhitespace { return false }
            index = prev
            stepsRemaining -= 1
        }
        return false
    }

    static func highlightedServerID(
        servers: [SlashCommandMCPServerItem],
        filterText: String,
        highlightedIndex: Int
    ) -> String? {
        let filtered = filteredServers(servers: servers, filterText: filterText)
        guard !filtered.isEmpty else { return nil }

        let clamped = max(0, min(highlightedIndex, filtered.count - 1))
        return filtered[clamped].id
    }

    static func filteredServers(
        servers: [SlashCommandMCPServerItem],
        filterText: String
    ) -> [SlashCommandMCPServerItem] {
        guard let query = filterText.trimmedNonEmpty else { return servers }
        return servers.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    static func filteredCount(
        servers: [SlashCommandMCPServerItem],
        filterText: String
    ) -> Int {
        filteredServers(servers: servers, filterText: filterText).count
    }

    /// Locates the `/` that anchors the active slash-command token at
    /// end-of-string, or nil when no such token exists. The token rule
    /// mirrors the prior regex `(?:^|(?<=\s))/[^\s/]*$`:
    /// - the trailing run from this `/` to end-of-string contains no
    ///   whitespace and no further `/`
    /// - the `/` itself sits at start-of-string or immediately after
    ///   whitespace
    private static func activeSlashIndex(in text: String) -> String.Index? {
        var index = text.endIndex
        while index > text.startIndex {
            let prev = text.index(before: index)
            let char = text[prev]
            if char == "/" {
                if prev == text.startIndex { return prev }
                let beforeSlash = text.index(before: prev)
                return text[beforeSlash].isWhitespace ? prev : nil
            }
            if char.isWhitespace { return nil }
            index = prev
        }
        return nil
    }
}
