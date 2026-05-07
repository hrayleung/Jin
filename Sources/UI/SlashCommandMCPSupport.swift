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
    private static let activeSlashCommandPattern = "(?:^|(?<=\\s))/([^\\s/]*)$"
    private static let slashCommandTokenPattern = "(?:^|(?<=\\s))/[^\\s/]*$"

    static func detectFilter(in text: String) -> String? {
        guard let range = text.range(
            of: activeSlashCommandPattern,
            options: .regularExpression
        ) else {
            return nil
        }

        let matched = String(text[range])
        return String(matched.dropFirst())
    }

    static func removeSlashToken(from text: String) -> String {
        guard let range = text.range(
            of: slashCommandTokenPattern,
            options: .regularExpression
        ) else {
            return text
        }

        var result = text
        result.removeSubrange(range)
        return result
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
}
