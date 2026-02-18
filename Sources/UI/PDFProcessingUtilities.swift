import Foundation

/// Static utilities for PDF and OCR content processing.
/// These methods do not depend on view state.
enum PDFProcessingUtilities {

    /// Unwrap a DeepSeek OCR response that may be wrapped in markdown fences.
    static func normalizedDeepSeekOCRMarkdown(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        let fenceCount = trimmed.components(separatedBy: "```").count - 1
        guard fenceCount == 2 else { return trimmed }

        guard let firstNewline = trimmed.firstIndex(of: "\n"),
              let closingRange = trimmed.range(of: "```", options: [.backwards]) else {
            return trimmed
        }

        let openingLine = String(trimmed[..<firstNewline]).trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedOpening = openingLine == "```" || openingLine == "```markdown" || openingLine == "```md"
        guard allowedOpening else { return trimmed }

        let contentStart = trimmed.index(after: firstNewline)
        guard closingRange.lowerBound > contentStart else { return trimmed }

        let content = trimmed[contentStart..<closingRange.lowerBound]
        return String(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode a Mistral OCR inline image from base64 or data URI.
    static func decodeMistralOCRImageBase64(_ raw: String, imageID: String) -> ImageContent? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("data:"),
           let commaIndex = trimmed.range(of: ","),
           let headerRange = trimmed.range(of: "data:") {
            let header = String(trimmed[headerRange.upperBound..<commaIndex.lowerBound])
            let base64 = String(trimmed[commaIndex.upperBound...])
            let mimeType = header.split(separator: ";").first.map(String.init)
                ?? mimeTypeForMistralImageID(imageID)
                ?? "image/png"
            guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else { return nil }
            return ImageContent(mimeType: mimeType, data: data, url: nil)
        }

        guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]) else { return nil }
        let mimeType = mimeTypeForMistralImageID(imageID) ?? sniffImageMimeType(from: data) ?? "image/png"
        return ImageContent(mimeType: mimeType, data: data, url: nil)
    }

    /// Infer MIME type from a Mistral OCR image ID based on file extension.
    static func mimeTypeForMistralImageID(_ imageID: String) -> String? {
        let lower = imageID.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        return nil
    }

    /// Sniff the MIME type of an image from its magic bytes.
    static func sniffImageMimeType(from data: Data) -> String? {
        if data.count >= 3, data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.count >= 8, data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if data.count >= 12 {
            let riff = data.prefix(4)
            let webp = data.dropFirst(8).prefix(4)
            if riff == Data([0x52, 0x49, 0x46, 0x46]) && webp == Data([0x57, 0x45, 0x42, 0x50]) {
                return "image/webp"
            }
        }
        return nil
    }
}
