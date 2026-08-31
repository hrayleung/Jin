import Foundation
import SwiftData
import XCTest
@testable import Jin

/// End-to-end cover for the one part of chat deletion that removes user files
/// from disk. Every case here is a way to get it wrong destructively.
final class AttachmentGarbageCollectorTests: XCTestCase {

    private var directory: URL!
    private var attachmentsDirectory: URL!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()

        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        attachmentsDirectory = directory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        container = try ModelContainer(
            for: ConversationEntity.self,
            AssistantEntity.self,
            MessageEntity.self,
            MessageHighlightEntity.self,
            ProviderConfigEntity.self,
            MCPServerConfigEntity.self,
            AttachmentEntity.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("test.store"))
        )
    }

    override func tearDownWithError() throws {
        container = nil
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    @MainActor
    func testDeletingAChatRemovesItsOwnFilesButKeepsSharedAndUnrelatedOnes() async throws {
        let context = ModelContext(container)

        let onlyInDoomedChat = try makeFile(named: "\(UUID().uuidString).png")
        let sharedByBothChats = try makeFile(named: "\(UUID().uuidString).png")
        let composerDraft = try makeFile(named: "\(UUID().uuidString).pdf")

        let doomed = makeConversation(title: "Doomed", in: context)
        try appendMessage(referencing: [onlyInDoomedChat, sharedByBothChats], to: doomed, in: context)

        let survivor = makeConversation(title: "Survivor", in: context)
        try appendMessage(referencing: [sharedByBothChats], to: survivor, in: context)
        try context.save()

        let candidates = AttachmentCleanup.candidateFilenames(
            for: [doomed],
            attachmentsDirectory: attachmentsDirectory
        )
        XCTAssertEqual(candidates, [onlyInDoomedChat.lastPathComponent, sharedByBothChats.lastPathComponent])

        context.delete(doomed)
        try context.save()

        let collector = AttachmentGarbageCollector(container: container)
        let removed = await collector.removeUnreferencedFiles(
            candidateFilenames: candidates,
            attachmentsDirectory: attachmentsDirectory
        )

        XCTAssertEqual(removed, [onlyInDoomedChat.lastPathComponent])
        XCTAssertFalse(exists(onlyInDoomedChat))
        XCTAssertTrue(
            exists(sharedByBothChats),
            "The same image can back messages in several chats — deleting one must not break the others."
        )
        XCTAssertTrue(
            exists(composerDraft),
            "A file no deleted message referenced is never a candidate: composer drafts land on disk before their message exists."
        )
    }

    @MainActor
    func testNothingIsRemovedWhenTheChatWasNotActuallyDeleted() async throws {
        let context = ModelContext(container)
        let file = try makeFile(named: "\(UUID().uuidString).png")

        let conversation = makeConversation(title: "Still here", in: context)
        try appendMessage(referencing: [file], to: conversation, in: context)
        try context.save()

        let candidates = AttachmentCleanup.candidateFilenames(
            for: [conversation],
            attachmentsDirectory: attachmentsDirectory
        )

        let collector = AttachmentGarbageCollector(container: container)
        let removed = await collector.removeUnreferencedFiles(
            candidateFilenames: candidates,
            attachmentsDirectory: attachmentsDirectory
        )

        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(exists(file))
    }

    /// The scan pages through messages in batches; a reference living past the
    /// first page must still protect its file.
    @MainActor
    func testReferencesAreFoundBeyondTheFirstFetchBatch() async throws {
        let context = ModelContext(container)
        let shared = try makeFile(named: "\(UUID().uuidString).png")

        let doomed = makeConversation(title: "Doomed", in: context)
        try appendMessage(referencing: [shared], to: doomed, in: context)

        let survivor = makeConversation(title: "Survivor", in: context)
        for _ in 0..<250 {
            try appendMessage(referencing: [], to: survivor, in: context)
        }
        try appendMessage(referencing: [shared], to: survivor, in: context)
        try context.save()

        let candidates = AttachmentCleanup.candidateFilenames(
            for: [doomed],
            attachmentsDirectory: attachmentsDirectory
        )
        context.delete(doomed)
        try context.save()

        let collector = AttachmentGarbageCollector(container: container)
        let removed = await collector.removeUnreferencedFiles(
            candidateFilenames: candidates,
            attachmentsDirectory: attachmentsDirectory
        )

        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(exists(shared))
    }

    @MainActor
    func testAllReferencedFilenamesCoversEveryChat() async throws {
        let context = ModelContext(container)
        let first = try makeFile(named: "\(UUID().uuidString).png")
        let second = try makeFile(named: "\(UUID().uuidString).mp4")
        _ = try makeFile(named: "\(UUID().uuidString).pdf") // unreferenced

        let a = makeConversation(title: "A", in: context)
        try appendMessage(referencing: [first], to: a, in: context)
        let b = makeConversation(title: "B", in: context)
        try appendMessage(referencing: [second], to: b, in: context)
        try context.save()

        let collector = AttachmentGarbageCollector(container: container)
        let referenced = await collector.allReferencedFilenames(attachmentsDirectory: attachmentsDirectory)

        XCTAssertEqual(referenced, [first.lastPathComponent, second.lastPathComponent])
    }

    /// Offset paging is only sound while nothing is removed underneath it: a
    /// message deleted mid-scan shifts later rows down one, so a row can slip
    /// through unread, and an unread row may hold the last reference to a
    /// candidate. The sweep abandons the round rather than guess.
    @MainActor
    func testMessageDeletedMidScanAbandonsTheRound() async throws {
        let context = ModelContext(container)
        let file = try makeFile(named: "\(UUID().uuidString).png")

        let doomed = makeConversation(title: "Doomed", in: context)
        try appendMessage(referencing: [file], to: doomed, in: context)

        // Enough to need more than one batch, so the hook fires mid-scan.
        let survivor = makeConversation(title: "Survivor", in: context)
        for _ in 0..<400 {
            try appendMessage(referencing: [], to: survivor, in: context)
        }
        try context.save()

        let candidates = AttachmentCleanup.candidateFilenames(
            for: [doomed],
            attachmentsDirectory: attachmentsDirectory
        )
        context.delete(doomed)
        try context.save()

        // Stands in for another chat being deleted while the sweep runs. Uses
        // its own context so it doesn't need the main actor the test is on.
        let container = self.container!
        let collector = AttachmentGarbageCollector(container: container) {
            let scratch = ModelContext(container)
            guard let victim = try? scratch.fetch(FetchDescriptor<MessageEntity>()).first else { return }
            scratch.delete(victim)
            try? scratch.save()
        }

        let removed = await collector.removeUnreferencedFiles(
            candidateFilenames: candidates,
            attachmentsDirectory: attachmentsDirectory
        )

        XCTAssertTrue(removed.isEmpty, "A row may have slipped through the shifted paging.")
        XCTAssertTrue(exists(file), "Leaking a file is recoverable; deleting a referenced one is not.")
    }

    /// A filename read back out of the store must never be able to reach
    /// outside the attachments directory.
    func testTraversalCandidatesAreIgnored() async throws {
        let outsider = directory.appendingPathComponent("secret.txt")
        try Data("keep me".utf8).write(to: outsider)

        let collector = AttachmentGarbageCollector(container: container)
        let removed = await collector.removeUnreferencedFiles(
            candidateFilenames: ["../secret.txt"],
            attachmentsDirectory: attachmentsDirectory
        )

        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(exists(outsider))
    }

    // MARK: - Helpers

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func makeFile(named name: String) throws -> URL {
        let url = attachmentsDirectory.appendingPathComponent(name, isDirectory: false)
        try Data("payload".utf8).write(to: url)
        return url
    }

    @MainActor
    private func makeConversation(title: String, in context: ModelContext) -> ConversationEntity {
        let conversation = ConversationEntity(
            title: title,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: Data()
        )
        context.insert(conversation)
        return conversation
    }

    @MainActor
    private func appendMessage(
        referencing files: [URL],
        to conversation: ConversationEntity,
        in context: ModelContext
    ) throws {
        var parts: [ContentPart] = [.text("hello")]
        for file in files {
            parts.append(.image(ImageContent(mimeType: "image/png", url: file)))
        }

        let message = MessageEntity(
            role: "user",
            contentData: try JSONEncoder().encode(parts)
        )
        context.insert(message)
        message.conversation = conversation
        conversation.messages.append(message)
    }
}
