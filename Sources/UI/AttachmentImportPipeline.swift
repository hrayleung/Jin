import Foundation

/// Static utilities for importing file attachments from various sources.
/// These methods are self-contained and do not depend on view state.
enum AttachmentImportPipeline {
    static func importInBackground(from urls: [URL]) async -> ([DraftAttachment], [String]) {
        var newAttachments: [DraftAttachment] = []
        var errors: [String] = []

        let storage: AttachmentStorageManager
        do {
            storage = try AttachmentStorageManager()
        } catch {
            return ([], ["Failed to initialize attachment storage: \(error.localizedDescription)"])
        }

        for sourceURL in urls {
            let result = await importSingle(from: sourceURL, storage: storage)
            switch result {
            case .success(let attachment):
                newAttachments.append(attachment)
            case .failure(let error):
                errors.append(error.localizedDescription)
            }
        }

        return (newAttachments, errors)
    }

    static func importRecordedAudioClip(_ clip: SpeechToTextManager.RecordedClip) async throws -> DraftAttachment {
        let storage = try AttachmentStorageManager()
        let stored = try await storage.saveAttachment(data: clip.data, filename: clip.filename, mimeType: clip.mimeType)
        return DraftAttachment(
            id: stored.id,
            filename: stored.filename,
            mimeType: stored.mimeType,
            fileURL: stored.fileURL,
            extractedText: nil
        )
    }
}
