import Foundation

enum SearchActivityURLDeduplication {
    static func key(for rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard var components = URLComponents(string: trimmed) else { return trimmed }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? trimmed
    }
}
