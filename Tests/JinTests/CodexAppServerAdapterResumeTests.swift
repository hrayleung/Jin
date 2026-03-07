import XCTest
@testable import Jin

final class CodexAppServerAdapterResumeTests: XCTestCase {
    func testResumedTurnInputWithImagesUsesOnlyLatestUserTurn() throws {
        let messages = [
            Message(role: .user, content: [.text("Earlier question")]),
            Message(role: .assistant, content: [.text("Earlier answer")]),
            Message(
                role: .user,
                content: [
                    .text("Please inspect this image"),
                    .image(ImageContent(mimeType: "image/png", url: URL(fileURLWithPath: "/tmp/reference.png")))
                ]
            )
        ]

        let inputItems = CodexAppServerAdapter.makeTurnInput(from: messages, resumeExistingThread: true)

        XCTAssertEqual(inputItems.count, 2)

        let textItem = try XCTUnwrap(inputItems[0] as? [String: Any])
        let text = try XCTUnwrap(textItem["text"] as? String)
        XCTAssertEqual(text, "Please inspect this image")
        XCTAssertFalse(text.contains("Earlier question"))
        XCTAssertFalse(text.contains("Earlier answer"))

        let imageItem = try XCTUnwrap(inputItems[1] as? [String: Any])
        XCTAssertEqual(imageItem["type"] as? String, "localImage")
        XCTAssertEqual(imageItem["path"] as? String, "/tmp/reference.png")
    }

    func testResumedTurnInputWithOnlyImagesUsesContinuePlaceholder() throws {
        let messages = [
            Message(role: .assistant, content: [.text("Show me the screenshot")]),
            Message(
                role: .user,
                content: [
                    .image(ImageContent(mimeType: "image/png", url: URL(fileURLWithPath: "/tmp/reference.png")))
                ]
            )
        ]

        let inputItems = CodexAppServerAdapter.makeTurnInput(from: messages, resumeExistingThread: true)

        XCTAssertEqual(inputItems.count, 2)

        let textItem = try XCTUnwrap(inputItems[0] as? [String: Any])
        XCTAssertEqual(textItem["text"] as? String, "Continue.")

        let imageItem = try XCTUnwrap(inputItems[1] as? [String: Any])
        XCTAssertEqual(imageItem["type"] as? String, "localImage")
        XCTAssertEqual(imageItem["path"] as? String, "/tmp/reference.png")
    }

    func testShouldFallbackToFreshThreadOnlyForMissingThreadErrors() {
        XCTAssertFalse(
            CodexAppServerAdapter.shouldFallbackToFreshThread(
                LLMError.providerError(code: "-32602", message: "Missing required property persistExtendedHistory")
            )
        )
        XCTAssertTrue(
            CodexAppServerAdapter.shouldFallbackToFreshThread(
                LLMError.providerError(code: "-32001", message: "Unknown thread remote-thread-123")
            )
        )
        XCTAssertTrue(
            CodexAppServerAdapter.shouldFallbackToFreshThread(
                LLMError.providerError(code: "-32602", message: "Missing thread remote-thread-123")
            )
        )
    }
}
