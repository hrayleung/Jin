import XCTest
@testable import Jin

final class XAIMediaPromptSupportTests: XCTestCase {
    func testUserTextPromptsCollectsTrimmedUserTextOnly() {
        let prompts = XAIMediaPromptSupport.userTextPrompts(from: [
            Message(role: .system, content: [.text("Ignore this")]),
            Message(role: .user, content: [
                .text("  first line  "),
                .image(ImageContent(mimeType: "image/png", data: Data([0x01]), url: nil)),
                .text("\nsecond line\n")
            ]),
            Message(role: .assistant, content: [.text("Ignore assistant")]),
            Message(role: .user, content: [.text("   ")])
        ])

        XCTAssertEqual(prompts, ["first line\n\nsecond line"])
    }

    func testPromptRequiresUserText() {
        XCTAssertThrowsError(
            try XAIMediaPromptSupport.prompt(
                from: [Message(role: .user, content: [.image(ImageContent(mimeType: "image/png", data: Data([0x01]), url: nil))])],
                mode: .none
            )
        ) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, "xAI media generation requires a text prompt.")
        }
    }

    func testPromptWithoutEditModeReturnsLatestPrompt() throws {
        let prompt = try XAIMediaPromptSupport.prompt(
            from: [
                Message(role: .user, content: [.text("Original")]),
                Message(role: .user, content: [.text("Latest")])
            ],
            mode: .none
        )

        XCTAssertEqual(prompt, "Latest")
    }

    func testSingleImageEditPromptReturnsLatestInstructionWithoutContinuityWrapper() throws {
        let prompt = try XAIMediaPromptSupport.prompt(
            from: [Message(role: .user, content: [.text("Make this dreamy")])],
            mode: .image
        )

        XCTAssertEqual(prompt, "Make this dreamy")
    }

    func testImageEditPromptRetainsOriginalPriorEditsAndLatestInstruction() throws {
        let prompt = try XAIMediaPromptSupport.prompt(
            from: [
                Message(role: .user, content: [.text("girl sleeping with a cat")]),
                Message(role: .user, content: [.text("japan style")]),
                Message(role: .user, content: [.text("more realistic")])
            ],
            mode: .image
        )

        XCTAssertTrue(prompt.contains("Edit the provided input image."))
        XCTAssertTrue(prompt.contains("Keep the main subject, composition, and scene continuity unless explicitly changed."))
        XCTAssertTrue(prompt.contains("Original request:\ngirl sleeping with a cat"))
        XCTAssertTrue(prompt.contains("Edits already applied:\n1. japan style"))
        XCTAssertTrue(prompt.contains("Apply this new edit now:\nmore realistic"))
    }

    func testVideoEditPromptUsesVideoContinuityWrapper() throws {
        let prompt = try XAIMediaPromptSupport.prompt(
            from: [
                Message(role: .user, content: [.text("Use this public video URL as source: https://cdn.example.com/input.mp4")]),
                Message(role: .user, content: [.text("Make it anime style with stronger camera motion.")])
            ],
            mode: .video
        )

        XCTAssertTrue(prompt.contains("Edit the provided input video."))
        XCTAssertTrue(prompt.contains("Keep the main subject, composition, camera motion, and timing continuity unless explicitly changed."))
        XCTAssertTrue(prompt.contains("Original request:\nUse this public video URL as source: https://cdn.example.com/input.mp4"))
        XCTAssertTrue(prompt.contains("Apply this new edit now:\nMake it anime style with stronger camera motion."))
    }
}
