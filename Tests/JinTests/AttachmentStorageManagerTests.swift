import XCTest
@testable import Jin

final class AttachmentStorageManagerTests: XCTestCase {
    private var previousRoot: String?
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Jin-AttachmentStorage-\(UUID().uuidString)", isDirectory: true)
        setenv("JIN_APP_SUPPORT_ROOT", temporaryRoot.path, 1)
    }

    override func tearDownWithError() throws {
        if let previousRoot {
            setenv("JIN_APP_SUPPORT_ROOT", previousRoot, 1)
        } else {
            unsetenv("JIN_APP_SUPPORT_ROOT")
        }
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        previousRoot = nil
        try super.tearDownWithError()
    }

    func testFileExtensionNormalizesMIMETypeWhitespaceAndCase() {
        XCTAssertEqual(AttachmentStorageManager.fileExtension(for: " \n IMAGE/JPEG \t "), "jpg")
        XCTAssertEqual(AttachmentStorageManager.fileExtension(for: " audio/X-WAV "), "wav")
        XCTAssertNil(AttachmentStorageManager.fileExtension(for: " application/octet-stream "))
    }

    func testSaveAttachmentUsesNormalizedMIMETypeExtension() async throws {
        let storage = try AttachmentStorageManager()

        let stored = try await storage.saveAttachment(
            data: Data("image".utf8),
            filename: "ignored.bin",
            mimeType: " \n IMAGE/PNG \t "
        )

        XCTAssertEqual(stored.fileURL.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
    }
}
