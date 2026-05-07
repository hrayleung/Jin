import UniformTypeIdentifiers

extension ChatComposerSupport {
    static var supportedAttachmentDocumentExtensions: [String] {
        [
            "docx", "doc", "odt", "rtf",
            "xlsx", "xls", "csv", "tsv",
            "pptx", "ppt",
            "txt", "md", "markdown",
            "json", "html", "htm", "xml"
        ]
    }

    static var supportedAttachmentImportTypes: [UTType] {
        var types: [UTType] = []
        var seen: Set<String> = []

        func append(_ type: UTType?) {
            guard let type, seen.insert(type.identifier).inserted else { return }
            types.append(type)
        }

        append(.image)
        append(.movie)
        append(.audio)
        append(.pdf)

        for ext in supportedAttachmentDocumentExtensions {
            append(UTType(filenameExtension: ext))
        }

        return types
    }

    static func fileAttachmentHelpText(supportsAudioInput: Bool, supportsNativePDF: Bool) -> String {
        let base = supportsAudioInput
            ? "Attach images / videos / audio / documents"
            : "Attach images / videos / documents"
        return supportsNativePDF ? "\(base) (native PDF available)" : "\(base) (PDFs may use extraction/OCR)"
    }
}
