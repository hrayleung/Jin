import Foundation

enum SearchActivityURLDeduplication {
    static func key(for rawURL: String) -> String {
        guard let trimmed = rawURL.trimmedNonEmpty else { return "" }
        guard var components = URLComponents(string: trimmed) else { return trimmed }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? trimmed
    }
}
