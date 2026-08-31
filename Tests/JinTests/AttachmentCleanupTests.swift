import XCTest
@testable import Jin

final class AttachmentCleanupTests: XCTestCase {

    private let attachmentsDirectory = URL(fileURLWithPath: "/tmp/jin-test/Attachments", isDirectory: true)

    private func encode(_ parts: [ContentPart]) throws -> Data {
        try JSONEncoder().encode(parts)
    }

    private func attachment(_ filename: String) -> URL {
        attachmentsDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: - Reference extraction

    func testReferencedFilenamesCoversEveryMediaKind() throws {
        let data = try encode([
            .text("hello"),
            .image(ImageContent(mimeType: "image/png", url: attachment("image.png"))),
            .video(VideoContent(mimeType: "video/mp4", url: attachment("clip.mp4"))),
            .file(FileContent(mimeType: "application/pdf", filename: "paper.pdf", url: attachment("doc.pdf"))),
            .audio(AudioContent(mimeType: "audio/wav", url: attachment("voice.wav")))
        ])

        XCTAssertEqual(
            AttachmentCleanup.referencedFilenames(in: data, attachmentsDirectory: attachmentsDirectory),
            ["image.png", "clip.mp4", "doc.pdf", "voice.wav"]
        )
    }

    /// A file the user attached from their own Documents folder is referenced
    /// by the message but is not Jin's to delete.
    func testReferencedFilenamesIgnoresFilesOutsideTheAttachmentsDirectory() throws {
        let data = try encode([
            .file(FileContent(
                mimeType: "application/pdf",
                filename: "contract.pdf",
                url: URL(fileURLWithPath: "/Users/someone/Documents/contract.pdf")
            ))
        ])

        XCTAssertTrue(
            AttachmentCleanup.referencedFilenames(in: data, attachmentsDirectory: attachmentsDirectory).isEmpty
        )
    }

    func testReferencedFilenamesIgnoresRemoteURLs() throws {
        let data = try encode([
            .image(ImageContent(mimeType: "image/png", url: URL(string: "https://example.com/image.png")))
        ])

        XCTAssertTrue(
            AttachmentCleanup.referencedFilenames(in: data, attachmentsDirectory: attachmentsDirectory).isEmpty
        )
    }

    func testReferencedFilenamesToleratesUndecodableContent() {
        XCTAssertTrue(
            AttachmentCleanup.referencedFilenames(
                in: Data("not json".utf8),
                attachmentsDirectory: attachmentsDirectory
            ).isEmpty
        )
    }

    /// Attachment filenames are UUIDs or hex digests, so the encoded file URL
    /// carries them verbatim — that's what makes the raw byte scan valid.
    func testEncodedURLKeepsTheFilenameVerbatim() throws {
        let filename = "\(UUID().uuidString).png"
        let data = try encode([.image(ImageContent(mimeType: "image/png", url: attachment(filename)))])

        XCTAssertNotNil(data.range(of: Data(filename.utf8)))
    }

    // MARK: - Blob scanning

    func testFilenamesMatchingFindsOnlyPresentReferences() throws {
        let present = "\(UUID().uuidString).png"
        let absent = "\(UUID().uuidString).png"
        let blob = try encode([.image(ImageContent(mimeType: "image/png", url: attachment(present)))])

        XCTAssertEqual(
            AttachmentCleanup.filenames(matching: [present, absent], in: blob),
            [present]
        )
    }

    func testFilenamesMatchingHandlesEmptyInputs() throws {
        let blob = try encode([.text("hi")])
        XCTAssertTrue(AttachmentCleanup.filenames(matching: [], in: blob).isEmpty)
        XCTAssertTrue(AttachmentCleanup.filenames(matching: ["a.png"], in: nil).isEmpty)
        XCTAssertTrue(AttachmentCleanup.filenames(matching: ["a.png"], in: Data()).isEmpty)
    }

    // MARK: - Containment

    func testIsInsideAcceptsOnlyRealChildren() {
        XCTAssertTrue(AttachmentCleanup.isInside(attachment("a.png"), directory: attachmentsDirectory))

        // The directory itself is never a deletable file.
        XCTAssertFalse(AttachmentCleanup.isInside(attachmentsDirectory, directory: attachmentsDirectory))

        // Sibling directory that merely shares a prefix.
        XCTAssertFalse(AttachmentCleanup.isInside(
            URL(fileURLWithPath: "/tmp/jin-test/AttachmentsBackup/a.png"),
            directory: attachmentsDirectory
        ))

        // Traversal out of the directory.
        XCTAssertFalse(AttachmentCleanup.isInside(
            attachmentsDirectory.appendingPathComponent("../../etc/passwd"),
            directory: attachmentsDirectory
        ))

        // Remote URLs are not files.
        XCTAssertFalse(AttachmentCleanup.isInside(
            URL(string: "https://example.com/a.png")!,
            directory: attachmentsDirectory
        ))
    }
}
