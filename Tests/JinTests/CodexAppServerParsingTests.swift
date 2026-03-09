import XCTest
@testable import Jin

final class CodexAppServerParsingTests: XCTestCase {
    func testParseDynamicToolCallOutputPartsMarksRemoteImageAsExternalReference() throws {
        let item: [String: JSONValue] = [
            "contentItems": .array([
                .object([
                    "type": .string("input_image"),
                    "image_url": .string("https://example.com/reference.png")
                ])
            ])
        ]

        let parts = CodexAppServerAdapter.parseDynamicToolCallOutputParts(from: item)
        XCTAssertEqual(parts.count, 1)

        guard case .image(let image) = parts[0] else {
            return XCTFail("Expected image content")
        }

        XCTAssertEqual(image.assetDisposition, MediaAssetDisposition.externalReference)
        XCTAssertEqual(image.remoteURL?.absoluteString, "https://example.com/reference.png")
    }
}
