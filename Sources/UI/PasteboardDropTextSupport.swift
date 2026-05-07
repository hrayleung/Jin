import AppKit
import Collections
import UniformTypeIdentifiers

extension PasteboardDropSupport {
    static func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] ?? []).map { $0 as URL }
    }

    static func readFileURLsFromURLAndTextRepresentations(from pasteboard: NSPasteboard) -> [URL] {
        var resultByPath: OrderedDictionary<String, URL> = [:]

        func append(_ url: URL) {
            guard url.isFileURL else { return }
            let key = url.standardizedFileURL.path
            if resultByPath[key] == nil {
                resultByPath[key] = url
            }
        }

        let allURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? [])
            .map { $0 as URL }
        for url in allURLs {
            append(url)
        }

        for value in textValues(from: pasteboard) {
            let parsed = AttachmentImportPipeline.parseDroppedString(value)
            for url in parsed.fileURLs {
                append(url)
            }
        }

        return Array(resultByPath.values)
    }

    static func parseTextValues(from pasteboard: NSPasteboard) -> PasteboardTextParseResult {
        var fileURLsByPath: OrderedDictionary<String, URL> = [:]
        var textChunks = OrderedSet<String>()

        func appendFileURL(_ url: URL) {
            guard url.isFileURL else { return }
            let key = url.standardizedFileURL.path
            if fileURLsByPath[key] == nil {
                fileURLsByPath[key] = url
            }
        }

        for value in textValues(from: pasteboard) {
            let parsed = AttachmentImportPipeline.parseDroppedString(value)
            for url in parsed.fileURLs {
                appendFileURL(url)
            }
            for text in parsed.textChunks {
                textChunks.append(text)
            }
        }

        let rawURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? [])
            .map { $0 as URL }
        for url in rawURLs {
            appendFileURL(url)
        }

        return PasteboardTextParseResult(
            fileURLs: Array(fileURLsByPath.values),
            textChunks: Array(textChunks)
        )
    }

    static func textValues(from pasteboard: NSPasteboard) -> [String] {
        var values: [String] = []

        if let value = pasteboard.string(forType: .string) {
            values.append(value)
        }
        if let value = pasteboard.string(forType: .URL) {
            values.append(value)
        }
        if let value = pasteboard.string(forType: .fileURL) {
            values.append(value)
        }

        if let items = pasteboard.pasteboardItems {
            for item in items {
                for type in item.types {
                    guard let utType = UTType(type.rawValue),
                          utType.conforms(to: .text),
                          let text = item.string(forType: type) else { continue }
                    values.append(text)
                }
            }
        }

        return values
    }
}
