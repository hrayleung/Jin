import XCTest
@testable import Jin

final class OpenAIChatCompletionsImageSupportTests: XCTestCase {
    func testImageOutputsParsesBase64DataURLAndUsesPayloadMIMETypeFirst() throws {
        let payloads = try decodedImages([
            [
                "type": "image_url",
                "mime_type": "image/webp",
                "image_url": "data:image/png;base64,AQID"
            ]
        ])

        let images = OpenAIChatCompletionsImageSupport.imageOutputs(payloads)

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].mimeType, "image/webp")
        XCTAssertEqual(images[0].data, Data([0x01, 0x02, 0x03]))
        XCTAssertNil(images[0].url)
    }

    func testImageOutputsParsesDataURLsWithoutExplicitMIMEType() throws {
        let payloads = try decodedImages([
            [
                "type": "image_url",
                "image_url": "data:;base64,BAUG"
            ],
            [
                "type": "image_url",
                "image_url": "data:,hello%20world"
            ]
        ])

        let images = OpenAIChatCompletionsImageSupport.imageOutputs(payloads)

        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0].mimeType, "image/png")
        XCTAssertEqual(images[0].data, Data([0x04, 0x05, 0x06]))
        XCTAssertEqual(images[1].mimeType, "image/png")
        XCTAssertEqual(images[1].data, Data("hello world".utf8))
    }

    func testImageOutputsPreservesHTTPRemoteURLsAndInfersMIMEType() throws {
        let payloads = try decodedImages([
            [
                "type": "image_url",
                "image_url": "https://cdn.example.com/rendered.jpg"
            ],
            [
                "type": "image_url",
                "mime_type": "image/custom",
                "image_url": [
                    "url": "https://cdn.example.com/rendered.bin"
                ]
            ]
        ])

        let images = OpenAIChatCompletionsImageSupport.imageOutputs(payloads)

        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0].mimeType, "image/jpeg")
        XCTAssertEqual(images[0].url?.absoluteString, "https://cdn.example.com/rendered.jpg")
        XCTAssertEqual(images[0].assetDisposition, .managed)
        XCTAssertNil(images[0].data)
        XCTAssertEqual(images[1].mimeType, "image/custom")
        XCTAssertEqual(images[1].url?.absoluteString, "https://cdn.example.com/rendered.bin")
    }

    func testImageOutputsDropsInvalidAndUnsupportedRemoteURLs() throws {
        let payloads = try decodedImages([
            [
                "type": "image_url",
                "image_url": "file:///etc/passwd"
            ],
            [
                "type": "image_url",
                "image_url": "ftp://example.com/image.png"
            ],
            [
                "type": "image_url",
                "image_url": "   "
            ]
        ])

        XCTAssertTrue(OpenAIChatCompletionsImageSupport.imageOutputs(payloads).isEmpty)
    }

    func testImageOutputsPreservesLegacyInvalidBase64FallbackBehavior() throws {
        let payloads = try decodedImages([
            [
                "type": "image_url",
                "image_url": "data:image/png;base64,not-valid-base64"
            ]
        ])

        let images = OpenAIChatCompletionsImageSupport.imageOutputs(payloads)

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].mimeType, "image/png")
        XCTAssertEqual(images[0].data, Data("not-valid-base64".utf8))
    }

    private func decodedImages(
        _ images: [[String: Any]]
    ) throws -> [OpenAIChatCompletionsResponse.GeneratedImage] {
        let payload: [String: Any] = [
            "id": "cmpl_image_support",
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "images": images
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let response = try OpenAIChatCompletionsCore.decodeResponse(data)
        return try XCTUnwrap(response.choices.single?.message.images)
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
