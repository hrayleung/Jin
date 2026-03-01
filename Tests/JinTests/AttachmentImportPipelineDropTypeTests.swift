import XCTest
import UniformTypeIdentifiers
@testable import Jin

final class AttachmentImportPipelineDropTypeTests: XCTestCase {
    func testPreferredFileRepresentationTypeIdentifierPrefersFilePromiseType() {
        let identifiers = [
            UTType.fileURL.identifier,
            "com.apple.NSFilesPromisePboardType",
            UTType.data.identifier
        ]

        let result = AttachmentImportPipeline.preferredFileRepresentationTypeIdentifier(from: identifiers)

        XCTAssertEqual(result, "com.apple.NSFilesPromisePboardType")
    }

    func testPreferredFileRepresentationTypeIdentifierSkipsTextAndURLTypes() {
        let identifiers = [
            UTType.url.identifier,
            UTType.utf8PlainText.identifier,
            UTType.pdf.identifier
        ]

        let result = AttachmentImportPipeline.preferredFileRepresentationTypeIdentifier(from: identifiers)

        XCTAssertEqual(result, UTType.pdf.identifier)
    }

    func testPreferredFileRepresentationTypeIdentifierReturnsNilWhenOnlyTextAndURL() {
        let identifiers = [
            UTType.url.identifier,
            UTType.plainText.identifier
        ]

        let result = AttachmentImportPipeline.preferredFileRepresentationTypeIdentifier(from: identifiers)

        XCTAssertNil(result)
    }

    func testPreferredFileRepresentationTypeIdentifierFallsBackToItemType() {
        let identifiers = [
            UTType.item.identifier
        ]

        let result = AttachmentImportPipeline.preferredFileRepresentationTypeIdentifier(from: identifiers)

        XCTAssertEqual(result, UTType.item.identifier)
    }
}
