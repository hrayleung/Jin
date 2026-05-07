import AppKit
import UniformTypeIdentifiers

extension PasteboardDropSupport {
    static func readImages(
        from pasteboard: NSPasteboard,
        usesRawTypeFallback: Bool = true
    ) -> [NSImage] {
        if let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !objects.isEmpty {
            return objects
        }

        var images: [NSImage] = []

        if let image = NSImage(pasteboard: pasteboard) {
            images.append(image)
        }

        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let image = imageFromPasteboardItem(item) {
                    images.append(image)
                }
            }
        } else if usesRawTypeFallback {
            for type in pasteboard.types ?? [] {
                if let image = imageFromPasteboardData(type: type, from: pasteboard) {
                    images.append(image)
                    break
                }
            }
        }

        return images
    }

    static func isImageType(_ type: NSPasteboard.PasteboardType) -> Bool {
        if let utType = UTType(type.rawValue), utType.conforms(to: .image) {
            return true
        }

        return type == .png || type == .tiff
    }

    private static func imageFromPasteboardItem(_ item: NSPasteboardItem) -> NSImage? {
        for type in item.types {
            if let image = imageFromPasteboardData(type: type, from: item) {
                return image
            }
        }
        return nil
    }

    private static func imageFromPasteboardData(
        type: NSPasteboard.PasteboardType,
        from item: NSPasteboardItem
    ) -> NSImage? {
        guard isImageType(type),
              let data = item.data(forType: type),
              let image = NSImage(data: data) else {
            return nil
        }

        return image
    }

    private static func imageFromPasteboardData(
        type: NSPasteboard.PasteboardType,
        from pasteboard: NSPasteboard
    ) -> NSImage? {
        guard isImageType(type),
              let data = pasteboard.data(forType: type),
              let image = NSImage(data: data) else {
            return nil
        }

        return image
    }
}
