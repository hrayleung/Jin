import Foundation

/// Rewrites content parts that point at managed attachment files which no longer
/// exist on disk, so a single lost attachment can't abort an entire request.
///
/// When an attachment file referenced by conversation history is deleted or moved,
/// adapters that read its bytes (`resolveFileData(from:)`) throw
/// `LLMError.invalidRequest`, which aborts the whole send and blocks the
/// conversation. This pass runs once, provider-agnostically, before the history is
/// handed to any adapter and replaces only the lost parts with a short text
/// placeholder so the conversation can continue with the model still aware that
/// something was attached.
///
/// A part is considered "lost" only when it carries no inline `data`, references a
/// local `file://` URL, and that file is missing from disk. Inline data, remote
/// URLs, and files that still exist are left untouched.
enum MissingAttachmentSanitizer {
    /// Returns a copy of `messages` with lost-attachment parts replaced by text
    /// placeholders. Messages with no lost attachments are returned unchanged.
    static func sanitize(_ messages: [Message]) -> [Message] {
        messages.map(sanitizeMessage)
    }

    private static func sanitizeMessage(_ message: Message) -> Message {
        var didRewrite = false
        let newContent = message.content.map { part -> ContentPart in
            guard let replacement = replacementForLostAttachment(part) else {
                return part
            }
            didRewrite = true
            return replacement
        }

        guard didRewrite else { return message }

        return Message(
            id: message.id,
            role: message.role,
            content: newContent,
            toolCalls: message.toolCalls,
            toolResults: message.toolResults,
            searchActivities: message.searchActivities,
            codeExecutionActivities: message.codeExecutionActivities,
            timestamp: message.timestamp,
            perMessageMCPServerNames: message.perMessageMCPServerNames
        )
    }

    /// Returns a placeholder content part when `part` references a managed local
    /// file that is missing from disk, or `nil` to keep the part unchanged.
    private static func replacementForLostAttachment(_ part: ContentPart) -> ContentPart? {
        switch part {
        case .image(let image):
            guard isLostManagedFile(data: image.data, url: image.url) else { return nil }
            return .text(omittedNotice(kind: "Image"))

        case .audio(let audio):
            guard isLostManagedFile(data: audio.data, url: audio.url) else { return nil }
            return .text(omittedNotice(kind: "Audio"))

        case .video(let video):
            guard isLostManagedFile(data: video.data, url: video.url) else { return nil }
            return .text(omittedNotice(kind: "Video"))

        case .file(let file):
            guard isLostManagedFile(data: file.data, url: file.url) else { return nil }
            // Reuse the existing fallback renderer: a file's extracted text (e.g. a
            // PDF's OCR output) is stored on `FileContent` independently of the
            // original bytes, so it survives even when the source file is gone.
            return .text(AttachmentPromptRenderer.fallbackText(for: file))

        case .text, .quote, .thinking, .redactedThinking:
            return nil
        }
    }

    /// A managed local attachment is "lost" when it has no inline data, points at a
    /// `file://` URL, and that file no longer exists on disk.
    private static func isLostManagedFile(data: Data?, url: URL?) -> Bool {
        guard data == nil, let url, url.isFileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    private static func omittedNotice(kind: String) -> String {
        "[\(kind) attachment omitted: the file is no longer available.]"
    }
}
