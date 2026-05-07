import XCTest
@testable import Jin

final class XAIMediaImageSupportTests: XCTestCase {
    func testImageURLForGenerationPrefersLatestUserImageThenAssistantThenOlderUserImage() throws {
        let latestUserData = Data([0x03])
        let assistantData = Data([0x02])
        let olderUserData = Data([0x01])

        XCTAssertEqual(
            try XAIMediaImageSupport.imageURLForImageGeneration(from: [
                Message(role: .user, content: [.image(ImageContent(mimeType: "image/png", data: olderUserData, url: nil))]),
                Message(role: .assistant, content: [.image(ImageContent(mimeType: "image/png", data: assistantData, url: nil))]),
                Message(role: .user, content: [.image(ImageContent(mimeType: "image/png", data: latestUserData, url: nil))])
            ]),
            "data:image/png;base64,\(latestUserData.base64EncodedString())"
        )

        XCTAssertEqual(
            try XAIMediaImageSupport.imageURLForImageGeneration(from: [
                Message(role: .user, content: [.image(ImageContent(mimeType: "image/png", data: olderUserData, url: nil))]),
                Message(role: .assistant, content: [.image(ImageContent(mimeType: "image/png", data: assistantData, url: nil))]),
                Message(role: .user, content: [.text("Refine this")])
            ]),
            "data:image/png;base64,\(assistantData.base64EncodedString())"
        )

        XCTAssertEqual(
            try XAIMediaImageSupport.imageURLForImageGeneration(from: [
                Message(role: .user, content: [.image(ImageContent(mimeType: "image/png", data: olderUserData, url: nil))])
            ]),
            "data:image/png;base64,\(olderUserData.base64EncodedString())"
        )
    }

    func testImageURLStringHandlesInlineRemoteLocalAndEmptyImages() throws {
        let inline = ImageContent(mimeType: "image/jpeg", data: Data([0x01, 0x02]), url: nil)
        XCTAssertEqual(
            try XAIMediaImageSupport.imageURLString(inline),
            "data:image/jpeg;base64,\(Data([0x01, 0x02]).base64EncodedString())"
        )

        let remoteURL = URL(string: "https://cdn.example.com/input.webp")!
        XCTAssertEqual(
            try XAIMediaImageSupport.imageURLString(ImageContent(mimeType: "image/webp", data: nil, url: remoteURL)),
            remoteURL.absoluteString
        )

        let localURL = URL(fileURLWithPath: "/tmp/input.png")
        XCTAssertEqual(
            try XAIMediaImageSupport.imageURLString(
                ImageContent(mimeType: "image/png", data: nil, url: localURL),
                fileDataResolver: { url in
                    XCTAssertEqual(url, localURL)
                    return Data([0x89, 0x50])
                }
            ),
            "data:image/png;base64,\(Data([0x89, 0x50]).base64EncodedString())"
        )

        XCTAssertNil(try XAIMediaImageSupport.imageURLString(ImageContent(mimeType: "image/png", data: nil, url: nil)))
    }

    func testResolveImageOutputsPrefersBase64ThenURLAndSkipsInvalidItems() {
        let pngData = Data([0x89, 0x50, 0x4e, 0x47])
        let outputs = XAIMediaImageSupport.resolveImageOutputs(from: [
            XAIMediaItem(
                url: nil,
                imageUrl: nil,
                videoUrl: nil,
                resultUrl: nil,
                b64Json: pngData.base64EncodedString(),
                mimeType: nil
            ),
            XAIMediaItem(
                url: "https://cdn.example.com/render.jpg",
                imageUrl: nil,
                videoUrl: nil,
                resultUrl: nil,
                b64Json: nil,
                mimeType: nil
            ),
            XAIMediaItem(
                url: nil,
                imageUrl: "",
                videoUrl: nil,
                resultUrl: nil,
                b64Json: nil,
                mimeType: nil
            )
        ])

        XCTAssertEqual(outputs.count, 2)
        XCTAssertEqual(outputs[0].mimeType, "image/png")
        XCTAssertEqual(outputs[0].data, pngData)
        XCTAssertNil(outputs[0].url)
        XCTAssertEqual(outputs[1].mimeType, "image/jpeg")
        XCTAssertEqual(outputs[1].url?.absoluteString, "https://cdn.example.com/render.jpg")
        XCTAssertEqual(outputs[1].assetDisposition, .managed)
    }

    func testInferImageMIMETypeUsesKnownExtensionsOnly() {
        XCTAssertEqual(XAIMediaImageSupport.inferImageMIMEType(from: URL(string: "https://example.com/a.JPG")!), "image/jpeg")
        XCTAssertEqual(XAIMediaImageSupport.inferImageMIMEType(from: URL(string: "https://example.com/a.png")!), "image/png")
        XCTAssertEqual(XAIMediaImageSupport.inferImageMIMEType(from: URL(string: "https://example.com/a.webp")!), "image/webp")
        XCTAssertEqual(XAIMediaImageSupport.inferImageMIMEType(from: URL(string: "https://example.com/a.gif")!), "image/gif")
        XCTAssertNil(XAIMediaImageSupport.inferImageMIMEType(from: URL(string: "https://example.com/a.bin")!))
    }
}
