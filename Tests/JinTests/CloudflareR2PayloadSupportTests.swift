import XCTest
@testable import Jin

final class CloudflareR2PayloadSupportTests: XCTestCase {
    func testDataURLParsesBase64PayloadWithMIMEType() throws {
        let encoded = Data("video-data".utf8).base64EncodedString()

        let parsed = try CloudflareR2DataURL("data:video/mp4;base64,\(encoded)")

        XCTAssertEqual(parsed.mimeType, "video/mp4")
        XCTAssertEqual(parsed.data, Data("video-data".utf8))
    }

    func testDataURLParsesPercentEncodedPayload() throws {
        let parsed = try CloudflareR2DataURL("data:text/plain;charset=utf-8,hello%20world")

        XCTAssertEqual(parsed.mimeType, "text/plain")
        XCTAssertEqual(parsed.data, Data("hello world".utf8))
    }

    func testMalformedDataURLThrowsUploaderError() {
        XCTAssertThrowsError(try CloudflareR2DataURL("data:video/mp4;base64,%%%%")) { error in
            guard case CloudflareR2UploaderError.malformedDataURL = error else {
                XCTFail("Expected malformedDataURL, got \(error)")
                return
            }
        }
    }

    func testVideoMetadataFallsBackFromFileExtension() {
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.videoMimeType("", fallbackURL: URL(fileURLWithPath: "/tmp/input.mov")),
            "video/quicktime"
        )
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.videoMimeType("   ", fallbackURL: URL(fileURLWithPath: "/tmp/input.webm")),
            "video/webm"
        )
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.videoMimeType("", fallbackURL: URL(fileURLWithPath: "/tmp/input.unknown")),
            "video/mp4"
        )
    }

    func testVideoFileExtensionUsesMIMETypeBeforeFallbackURL() {
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.videoFileExtension(
                for: "video/webm",
                fallbackURL: URL(fileURLWithPath: "/tmp/input.mov")
            ),
            "webm"
        )
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.videoFileExtension(
                for: "video/custom",
                fallbackURL: URL(fileURLWithPath: "/tmp/input.CustomExt")
            ),
            "customext"
        )
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.videoFileExtension(for: "video/custom", fallbackURL: nil),
            "mp4"
        )
    }

    func testFileMetadataFallsBackToPDFOrOctetStream() {
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.fileMimeType("", fallbackURL: URL(fileURLWithPath: "/tmp/report.pdf")),
            "application/pdf"
        )
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.fileMimeType("", fallbackURL: URL(fileURLWithPath: "/tmp/archive.zip")),
            "application/octet-stream"
        )
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.fileMimeType("  Application/PDF  ", fallbackURL: nil),
            "application/pdf"
        )
    }

    func testFileExtensionFallsBackToPDFURLOrBinary() {
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.fileExtension(for: "", fallbackURL: URL(fileURLWithPath: "/tmp/report.pdf")),
            "pdf"
        )
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.fileExtension(for: "", fallbackURL: URL(fileURLWithPath: "/tmp/archive.CustomExt")),
            "customext"
        )
        XCTAssertEqual(
            CloudflareR2PayloadMetadata.fileExtension(for: "", fallbackURL: nil),
            "bin"
        )
    }
}
