import Foundation
import PDFKit

/// Extracts text from project documents based on file type.
enum ProjectDocumentTextExtractor {
    /// Maximum characters to extract from a single document.
    static let maxCharactersPerDocument = 500_000

    /// Supported file extensions for text-based extraction.
    private static let textFileExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "csv", "tsv",
        "swift", "py", "js", "ts", "jsx", "tsx",
        "java", "kt", "go", "rs", "c", "cpp", "h", "hpp",
        "rb", "php", "sh", "bash", "zsh",
        "html", "htm", "css", "scss", "less",
        "xml", "yaml", "yml", "toml", "ini", "cfg",
        "sql", "graphql", "proto",
        "r", "R", "m", "mm",
        "log", "env", "gitignore", "dockerignore",
        "dockerfile", "makefile"
    ]

    /// Extract text from a document at the given URL.
    /// Returns the extracted text, or nil if extraction fails.
    static func extractText(from fileURL: URL) -> String? {
        let ext = fileURL.pathExtension.lowercased()

        if ext == "pdf" {
            return extractPDFText(from: fileURL)
        }

        if isTextFile(extension: ext) {
            return extractPlainText(from: fileURL)
        }

        // Try plain text extraction as fallback for unknown types
        return extractPlainText(from: fileURL)
    }

    /// Determine the MIME type for common document extensions.
    static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf":
            return "application/pdf"
        case "txt", "log", "env", "gitignore", "dockerignore":
            return "text/plain"
        case "md", "markdown":
            return "text/markdown"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        case "html", "htm":
            return "text/html"
        case "xml":
            return "application/xml"
        case "yaml", "yml":
            return "text/yaml"
        default:
            return "text/plain"
        }
    }

    // MARK: - Private

    private static func extractPDFText(from url: URL) -> String? {
        PDFKitTextExtractor.extractText(from: url, maxCharacters: maxCharactersPerDocument)
    }

    private static func extractPlainText(from url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count > maxCharactersPerDocument {
            let prefix = trimmed.prefix(maxCharactersPerDocument)
            return "\(prefix)\n\n[Truncated]"
        }

        return trimmed
    }

    private static func isTextFile(extension ext: String) -> Bool {
        textFileExtensions.contains(ext)
    }
}
