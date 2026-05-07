import AppKit
import UniformTypeIdentifiers

struct PasteboardTextParseResult: Equatable {
    let fileURLs: [URL]
    let textChunks: [String]
}

enum PasteboardDropSupport {
    static let acceptedDraggedTypes: [NSPasteboard.PasteboardType] =
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + [
            .fileURL,
            .URL,
            .string,
            .tiff,
            .png,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        ]
}
