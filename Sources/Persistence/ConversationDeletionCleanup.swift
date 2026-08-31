import Foundation
import SwiftData

/// The disk-side half of deleting a chat.
///
/// `modelContext.delete` only removes rows. Two things survive it, and both
/// are handled here:
///
/// - **Attachment files.** Nothing else in the app deletes them, so images,
///   videos, PDFs and audio outlived every chat that used them.
/// - **Store pages.** SQLite parks a deleted row's pages on its free list;
///   the file neither shrinks nor overwrites the old bytes until a `VACUUM`,
///   which can only run at launch before the container opens.
///
/// Every entry point must call `captureAttachmentCandidates` *before* the
/// delete and `finish` *after* the context is saved.
enum ConversationDeletionCleanup {

    @MainActor
    static func captureAttachmentCandidates(for conversations: [ConversationEntity]) -> Set<String> {
        guard !conversations.isEmpty,
              let directory = try? AppDataLocations.attachmentsDirectoryURL() else { return [] }
        return AttachmentCleanup.candidateFilenames(for: conversations, attachmentsDirectory: directory)
    }

    /// Marks the store for compaction at the next launch and sweeps the
    /// orphaned attachment files in the background.
    ///
    /// Must run after the delete has been **saved**: the sweep reads the
    /// store on its own contexts, and an unsaved delete would still look like
    /// a live reference (which keeps the file — safe, but pointless).
    @MainActor
    static func finish(attachmentCandidates: Set<String>, container: ModelContainer) {
        StoreCompaction.markPending()

        guard !attachmentCandidates.isEmpty,
              let directory = try? AppDataLocations.attachmentsDirectoryURL() else { return }

        Task.detached(priority: .utility) {
            let collector = AttachmentGarbageCollector(container: container)
            let removed = await collector.removeUnreferencedFiles(
                candidateFilenames: attachmentCandidates,
                attachmentsDirectory: directory
            )
            if !removed.isEmpty {
                NSLog("Jin storage: removed %d orphaned attachment file(s).", removed.count)
            }
        }
    }
}
