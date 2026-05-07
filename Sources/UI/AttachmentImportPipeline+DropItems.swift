import Foundation
import UniformTypeIdentifiers

extension AttachmentImportPipeline {
    static func parseDroppedString(_ text: String) -> (fileURLs: [URL], textChunks: [String]) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var fileURLs: [URL] = []
        var textChunks: [String] = []

        for line in lines {
            if line.hasPrefix("file://"), let url = URL(string: line), url.isFileURL {
                fileURLs.append(url)
                continue
            }

            let expanded = (line as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                let url = URL(fileURLWithPath: expanded)
                if isPotentialAttachmentFile(url) {
                    fileURLs.append(url)
                    continue
                }
            }

            textChunks.append(line)
        }

        return (fileURLs: fileURLs, textChunks: textChunks)
    }

    static func urlFromItemProviderItem(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        if let string = item as? NSString { return URL(string: string as String) }
        return nil
    }

    /// Select a type identifier that is most likely to expose a dropped file
    /// through `NSItemProvider.loadFileRepresentation`.
    static func preferredFileRepresentationTypeIdentifier(from identifiers: [String]) -> String? {
        guard !identifiers.isEmpty else { return nil }

        if let promiseIdentifier = identifiers.first(where: { identifier in
            let lower = identifier.lowercased()
            return lower.contains("filepromise")
                || lower.contains("promised-file")
                || lower.contains("nsfilespromise")
        }) {
            return promiseIdentifier
        }

        for identifier in identifiers {
            guard let type = UTType(identifier) else { continue }
            if type.conforms(to: .text) || type.conforms(to: .url) { continue }
            if type.conforms(to: .data) || type.conforms(to: .content) {
                return identifier
            }
        }

        for identifier in identifiers {
            guard let type = UTType(identifier) else { continue }
            if type.conforms(to: .text) || type.conforms(to: .url) { continue }
            if type.conforms(to: .item) {
                return identifier
            }
        }

        return nil
    }

    nonisolated static func completionNotificationPreview(from parts: [ContentPart]) -> String? {
        let text = parts.compactMap { part -> String? in
            if case .text(let value) = part {
                return value
            }
            return nil
        }
        .joined(separator: " ")

        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(180))
    }
}
