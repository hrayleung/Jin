import Foundation

enum SearchURLNormalizer {
    static func normalize(_ rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url.absoluteString
        }
        if let url = URL(string: "https://\(trimmed)"), url.scheme != nil {
            return url.absoluteString
        }

        return nil
    }
}
