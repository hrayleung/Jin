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

    /// The tooltip promised "videos" for every model, including the many that cannot read
    /// one — the user attached a clip, saw it render in their own bubble, and got told the
    /// model saw nothing. The picker stays permissive (same as audio, and so a clip survives
    /// switching models mid-draft), but the wording no longer claims a capability the
    /// selected model lacks; the adapters substitute an explicit "video attachment omitted"
    /// notice in that case.
    static func fileAttachmentHelpText(
        supportsAudioInput: Bool,
        supportsVideoInput: Bool,
        supportsNativePDF: Bool
    ) -> String {
        var kinds = ["images"]
        if supportsVideoInput {
            kinds.append("videos")
        }
        if supportsAudioInput {
            kinds.append("audio")
        }
        kinds.append("documents")

        let base = "Attach \(kinds.joined(separator: " / "))"
        let pdfNote = supportsNativePDF
            ? "native PDF available"
            : "PDFs may use page images, extraction, or OCR"
        let videoNote = supportsVideoInput ? nil : "this model cannot read video"

        let notes = [pdfNote, videoNote].compactMap { $0 }
        return "\(base) (\(notes.joined(separator: "; ")))"
    }
}
