import XCTest
@testable import Jin

final class ProviderHostedFileStoreTests: XCTestCase {
    func testPayloadTrimsFilenameAndNormalizesMIMEType() async throws {
        let store = ProviderHostedFileStore()
        let payload = try await store.payload(
            for: FileContent(
                mimeType: " Text/Plain ",
                filename: " \n notes.txt \t ",
                data: Data("notes".utf8)
            )
        )

        XCTAssertEqual(payload?.filename, "notes.txt")
        XCTAssertEqual(payload?.mimeType, "text/plain")
        XCTAssertEqual(payload?.data, Data("notes".utf8))
    }

    func testPayloadUsesFallbackFilenameForBlankFilename() async throws {
        let store = ProviderHostedFileStore()
        let payload = try await store.payload(
            for: FileContent(
                mimeType: "application/pdf",
                filename: " \n\t ",
                data: Data("pdf".utf8)
            )
        )

        XCTAssertEqual(payload?.filename, "Attachment")
    }
}
