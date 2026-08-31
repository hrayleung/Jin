import Foundation
import SwiftData

/// Deletes the attachment files a removed chat left orphaned, off the main
/// thread.
///
/// The scan reads every surviving message's blobs, which on a large library
/// means hundreds of megabytes, so it runs on its own contexts and in
/// batches: each batch gets a fresh `ModelContext` that is dropped with the
/// objects it faulted, keeping peak memory flat regardless of library size.
/// It also stops the moment every candidate has been found referenced.
actor AttachmentGarbageCollector {
    private static let batchSize = 200

    private let container: ModelContainer
    private let fileManager: FileManager
    /// Test seam. The mid-scan guard below is the only thing standing between
    /// a concurrent delete and removing a file a live message points at, and
    /// there is no other way to interleave with a scan this fast.
    private let onBatchScanned: (@Sendable () -> Void)?

    init(
        container: ModelContainer,
        fileManager: FileManager = .default,
        onBatchScanned: (@Sendable () -> Void)? = nil
    ) {
        self.container = container
        self.fileManager = fileManager
        self.onBatchScanned = onBatchScanned
    }

    /// Deletes the candidates no surviving message references.
    /// - Returns: the filenames actually removed.
    @discardableResult
    func removeUnreferencedFiles(
        candidateFilenames: Set<String>,
        attachmentsDirectory: URL
    ) -> [String] {
        let unreferenced = unreferencedFilenames(among: candidateFilenames)
        guard !unreferenced.isEmpty else { return [] }

        var removed: [String] = []
        for filename in unreferenced {
            let url = attachmentsDirectory.appendingPathComponent(filename, isDirectory: false)
            // Re-check containment: `filename` came off a stored URL, and a
            // path component from persisted data must never be able to walk
            // out of the attachments directory.
            guard AttachmentCleanup.isInside(url, directory: attachmentsDirectory),
                  fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
                removed.append(filename)
            } catch {
                continue
            }
        }
        return removed
    }

    /// Every attachment file referenced by any message, for callers that are
    /// about to delete the whole library and can't afford to walk it on the
    /// main thread. The sweep re-verifies each candidate, so a list captured
    /// slightly before the delete is safe.
    func allReferencedFilenames(attachmentsDirectory: URL) -> Set<String> {
        var filenames: Set<String> = []
        var offset = 0

        while true {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<MessageEntity>()
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = offset

            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else { break }
            for message in batch {
                filenames.formUnion(
                    AttachmentCleanup.referencedFilenames(
                        in: message.contentData,
                        attachmentsDirectory: attachmentsDirectory
                    )
                )
            }

            offset += batch.count
            if batch.count < Self.batchSize { break }
        }

        return filenames
    }

    private func unreferencedFilenames(among candidates: Set<String>) -> Set<String> {
        var remaining = candidates
        guard !remaining.isEmpty else { return [] }

        let messageCountBeforeScan = messageCount()
        var offset = 0
        while !remaining.isEmpty {
            // A fresh context per batch: SwiftData keeps every fetched object
            // registered for the life of its context, so reusing one would
            // accumulate the whole message table in memory.
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<MessageEntity>(
                // Explicit ascending order so paging is deterministic, and so
                // messages saved while the scan runs land past the cursor
                // instead of shifting rows underneath it.
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = offset

            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else { break }

            for message in batch {
                remaining.subtract(AttachmentCleanup.filenames(matching: remaining, in: message.contentData))
                if remaining.isEmpty { break }
                remaining.subtract(AttachmentCleanup.filenames(matching: remaining, in: message.toolResultsData))
                remaining.subtract(AttachmentCleanup.filenames(matching: remaining, in: message.toolCallsData))
                if remaining.isEmpty { break }
            }

            offset += batch.count
            onBatchScanned?()
            if batch.count < Self.batchSize { break }
        }

        guard !remaining.isEmpty else { return [] }

        // Offset paging can only be trusted if nothing was removed underneath
        // it. A message deleted mid-scan shifts every later row down one, so a
        // row can slip through unread — and an unread row is indistinguishable
        // from one holding the last reference to a candidate. Leaking a file
        // is recoverable; deleting one a live message points at is not, so a
        // shrinking table abandons this round.
        guard messageCount() >= messageCountBeforeScan else { return [] }
        return remaining
    }

    private func messageCount() -> Int {
        let context = ModelContext(container)
        return (try? context.fetchCount(FetchDescriptor<MessageEntity>())) ?? 0
    }
}
