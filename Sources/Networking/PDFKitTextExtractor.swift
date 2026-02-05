import Foundation
import PDFKit

enum PDFKitTextExtractor {
    static func extractText(from url: URL, maxCharacters: Int) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }

        var pieces: [String] = []
        pieces.reserveCapacity(min(16, document.pageCount))

        for index in 0..<document.pageCount {
            if let pageText = document.page(at: index)?.string, !pageText.isEmpty {
                pieces.append(pageText)
            }
        }

        let combined = pieces.joined(separator: "\n\n")
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count > maxCharacters {
            let prefix = trimmed.prefix(maxCharacters)
            return "\(prefix)\n\n[Truncated]"
        }

        return trimmed
    }
}

