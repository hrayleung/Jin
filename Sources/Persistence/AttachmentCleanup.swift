import Foundation

/// Works out which files under `Attachments/` a deleted chat was the last
/// user of.
///
/// Attachment files are referenced only by URL inside `MessageEntity`'s JSON
/// blobs, and `MessageMediaAssetPersistenceSupport.persistImageToDisk` names
/// images by the SHA-256 of their bytes and reuses an existing file — so one
/// file on disk can back messages in several different chats. Deleting a chat
/// therefore can't delete its files outright; each one has to be proven
/// unreferenced first.
///
/// Only files the deleted messages actually pointed at are ever candidates. A
/// blanket sweep of the directory would delete the composer's draft
/// attachments, which are written to disk *before* the message that
/// references them exists.
enum AttachmentCleanup {

    /// Attachment filenames referenced by these conversations. Call before
    /// deleting them — afterwards the messages are gone.
    static func candidateFilenames(
        for conversations: [ConversationEntity],
        attachmentsDirectory: URL
    ) -> Set<String> {
        var candidates: Set<String> = []
        for conversation in conversations {
            for message in conversation.messages {
                candidates.formUnion(
                    referencedFilenames(in: message.contentData, attachmentsDirectory: attachmentsDirectory)
                )
            }
        }
        return candidates
    }

    static func referencedFilenames(in contentData: Data, attachmentsDirectory: URL) -> Set<String> {
        guard let parts = try? JSONDecoder().decode([ContentPart].self, from: contentData) else { return [] }

        var filenames: Set<String> = []
        for part in parts {
            guard let url = localFileURL(in: part),
                  isInside(url, directory: attachmentsDirectory) else { continue }
            filenames.insert(url.lastPathComponent)
        }
        return filenames
    }

    /// Which of `filenames` appear anywhere in `blob`.
    ///
    /// A raw byte search rather than a JSON decode: the scan runs over every
    /// surviving message, and those blobs can carry inline base64 media.
    /// Attachment filenames are a UUID or a hex digest plus an extension, so
    /// they never pick up percent-encoding and appear verbatim in the encoded
    /// URL. Matching too eagerly only means keeping a file — the direction
    /// that can't lose data.
    static func filenames(matching filenames: Set<String>, in blob: Data?) -> Set<String> {
        guard let blob, !blob.isEmpty, !filenames.isEmpty else { return [] }

        var found: Set<String> = []
        for filename in filenames where blob.range(of: Data(filename.utf8)) != nil {
            found.insert(filename)
        }
        return found
    }

    static func isInside(_ url: URL, directory: URL) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        // Strict prefix: the directory itself is never a deletable file.
        return path.hasPrefix(directoryPath + "/")
    }

    private static func localFileURL(in part: ContentPart) -> URL? {
        let url: URL?
        switch part {
        case .image(let image):
            url = image.url
        case .video(let video):
            url = video.url
        case .file(let file):
            url = file.url
        case .audio(let audio):
            url = audio.url
        case .text, .quote, .thinking, .redactedThinking:
            url = nil
        }
        guard let url, url.isFileURL else { return nil }
        return url
    }
}
