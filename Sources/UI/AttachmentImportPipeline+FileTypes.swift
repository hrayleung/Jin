import Foundation
import UniformTypeIdentifiers

extension AttachmentImportPipeline {
    static func isPotentialAttachmentFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return true }
        if ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp" { return true }
        if ["wav", "mp3", "m4a", "aac", "flac", "ogg", "oga", "webm"].contains(ext) { return true }
        if ["mp4", "m4v", "mov", "webm", "avi", "mkv", "mpeg", "mpg", "wmv", "flv", "3gp", "3gpp"].contains(ext) { return true }
        return documentMIMEType(for: url) != nil
    }

    static func extractedTextIfSupported(from sourceURL: URL, mimeType: String) -> String? {
        switch normalizedMIMEType(mimeType) {
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
            return SpreadsheetTextExtractor.extractText(
                fromXLSX: sourceURL,
                maxCharacters: AttachmentConstants.maxSpreadsheetExtractedCharacters
            )
        case "text/plain", "text/markdown", "text/x-markdown",
             "text/csv", "text/tab-separated-values",
             "application/json", "application/xml", "text/xml":
            return readTextFile(
                at: sourceURL,
                maxCharacters: AttachmentConstants.maxSpreadsheetExtractedCharacters
            )
        default:
            return nil
        }
    }

    static func normalizedVideoMIMEType(for type: UTType, sourceURL: URL) -> String? {
        if let raw = type.preferredMIMEType?.lowercased(), raw.hasPrefix("video/") {
            return raw
        }

        switch sourceURL.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "mpeg", "mpg": return "video/mpeg"
        case "wmv": return "video/x-ms-wmv"
        case "flv": return "video/x-flv"
        case "3gp", "3gpp": return "video/3gpp"
        default: return nil
        }
    }

    static func normalizedAudioMIMEType(for type: UTType, sourceURL: URL) -> String? {
        if let raw = type.preferredMIMEType?.lowercased(), raw.hasPrefix("audio/") {
            switch raw {
            case "audio/x-wav": return "audio/wav"
            case "audio/mp4", "audio/x-m4a": return "audio/m4a"
            default: return raw
            }
        }

        switch sourceURL.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/m4a"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "ogg", "oga": return "audio/ogg"
        case "webm": return "audio/webm"
        default: return nil
        }
    }

    static func documentMIMEType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc":  return "application/msword"
        case "odt":  return "application/vnd.oasis.opendocument.text"
        case "rtf":  return "application/rtf"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls":  return "application/vnd.ms-excel"
        case "csv":  return "text/csv"
        case "tsv":  return "text/tab-separated-values"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt":  return "application/vnd.ms-powerpoint"
        case "txt":  return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "json": return "application/json"
        case "html", "htm": return "text/html"
        case "xml":  return "application/xml"
        default:     return nil
        }
    }

    private static func readTextFile(at sourceURL: URL, maxCharacters: Int) -> String? {
        guard let data = try? Data(contentsOf: sourceURL) else { return nil }

        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .ascii,
            .isoLatin1
        ]

        for encoding in encodings {
            guard var text = String(data: data, encoding: encoding) else { continue }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if text.count > maxCharacters {
                text = String(text.prefix(maxCharacters))
                text.append("\n\n[Truncated]")
            }
            return text
        }

        return nil
    }
}
