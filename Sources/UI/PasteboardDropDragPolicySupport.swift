import AppKit
import UniformTypeIdentifiers

extension PasteboardDropSupport {
    static func shouldUseDefaultTextDropHandling(for pasteboard: NSPasteboard) -> Bool {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? [])
            .map { $0 as URL }
        return shouldUseDefaultTextDropHandling(fileURLs: urls, types: pasteboard.types ?? [])
    }

    static func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types, !types.isEmpty else { return false }
        return canAcceptDrag(types: types)
    }

    static func canAcceptDrag(types: [NSPasteboard.PasteboardType]) -> Bool {
        let accepted = Set(acceptedDraggedTypes)
        for type in types where accepted.contains(type) {
            return true
        }

        for type in types {
            guard let utType = UTType(type.rawValue) else { continue }
            if utType.conforms(to: .fileURL)
                || utType.conforms(to: .url)
                || utType.conforms(to: .text)
                || utType.conforms(to: .image)
                || utType.conforms(to: .data)
                || utType.conforms(to: .item) {
                return true
            }
        }

        return false
    }

    static func shouldUseDefaultTextDropHandling(
        fileURLs urls: [URL],
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        if urls.contains(where: \.isFileURL) {
            return false
        }

        for type in types {
            let raw = type.rawValue.lowercased()
            if raw.contains("filepromise") || raw.contains("promised-file") || raw.contains("nsfilespromise") {
                return false
            }

            guard let utType = UTType(type.rawValue) else { continue }
            if utType.conforms(to: .image) {
                return false
            }
            if (utType.conforms(to: .data) || utType.conforms(to: .content) || utType.conforms(to: .item))
                && !utType.conforms(to: .text)
                && !utType.conforms(to: .url) {
                return false
            }
        }

        return true
    }
}
