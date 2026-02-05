import Foundation

enum AttachmentPromptRenderer {
    static func fallbackText(for file: FileContent) -> String {
        let filename = file.filename
        let mimeType = file.mimeType

        let trimmedExtracted = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedExtracted, !trimmedExtracted.isEmpty else {
            return "Attachment: \(filename) (\(mimeType))"
        }

        let header: String
        if mimeType == "application/pdf" {
            header = "PDF: \(filename) (\(mimeType))"
        } else {
            header = "File: \(filename) (\(mimeType))"
        }

        let note: String
        if mimeType == "application/pdf" {
            note = "The following text was extracted from the PDF. Treat it as the PDF’s contents (formatting may be imperfect)."
        } else {
            note = "The following text was extracted from the file. Treat it as the file’s contents (formatting may be imperfect)."
        }

        return "\(header)\n\n\(note)\n\n\(trimmedExtracted)"
    }
}
