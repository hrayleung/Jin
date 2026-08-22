import XCTest
@testable import Jin

final class ChatMessagePreparationUtilitiesTests: XCTestCase {
    func testResolvedSystemPromptTrimsPromptsAndPrefersConversationPrompt() {
        let assistant = AssistantEntity(
            id: "assistant",
            name: "Assistant",
            systemInstruction: "  Assistant prompt  ",
            replyLanguage: "  Spanish  "
        )

        XCTAssertEqual(
            ChatMessagePreparationSupport.resolvedSystemPrompt(
                conversationSystemPrompt: "  Conversation prompt  ",
                assistant: assistant
            ),
            "Conversation prompt\n\nAlways reply in Spanish."
        )
    }

    func testResolvedSystemPromptFallsBackToAssistantAndLanguageOnlyPrompt() {
        let assistant = AssistantEntity(
            id: "assistant",
            name: "Assistant",
            systemInstruction: "  Assistant prompt  ",
            replyLanguage: " \n "
        )

        XCTAssertEqual(
            ChatMessagePreparationSupport.resolvedSystemPrompt(
                conversationSystemPrompt: " \n ",
                assistant: assistant
            ),
            "Assistant prompt"
        )

        assistant.systemInstruction = " \n "
        assistant.replyLanguage = "  Japanese  "

        XCTAssertEqual(
            ChatMessagePreparationSupport.resolvedSystemPrompt(
                conversationSystemPrompt: nil,
                assistant: assistant
            ),
            "Always reply in Japanese."
        )
    }

    func testMakeConversationTitleTrimsFirstLineAndFallsBackForBlankText() {
        XCTAssertEqual(
            ChatMessagePreparationSupport.makeConversationTitle(from: "  Quarterly planning  \nIgnored"),
            "Quarterly planning"
        )
        XCTAssertEqual(
            ChatMessagePreparationSupport.makeConversationTitle(from: " \nIgnored"),
            "New Chat"
        )
    }

    func testHasTextualPromptChecksTrimmedMessageAndQuotes() {
        XCTAssertFalse(
            ChatMessagePreparationSupport.hasTextualPrompt(
                messageText: " \n ",
                quoteContents: [QuoteContent(quotedText: "\t")]
            )
        )
        XCTAssertTrue(
            ChatMessagePreparationSupport.hasTextualPrompt(
                messageText: "  Generate a diagram  ",
                quoteContents: []
            )
        )
        XCTAssertTrue(
            ChatMessagePreparationSupport.hasTextualPrompt(
                messageText: " \n ",
                quoteContents: [QuoteContent(quotedText: "  Use this source  ")]
            )
        )
    }

    func testFallbackTitleUsesFirstNonEmptyTextQuoteFileOrImagePart() {
        let textMessage = Message(role: .user, content: [.text(" \n "), .quote(QuoteContent(quotedText: "  Source quote  "))])
        XCTAssertEqual(ChatMessagePreparationSupport.fallbackTitleFromMessage(textMessage), "Source quote")

        let fileMessage = Message(
            role: .user,
            content: [
                .file(FileContent(mimeType: "application/pdf", filename: "  roadmap.pdf"))
            ]
        )
        XCTAssertEqual(ChatMessagePreparationSupport.fallbackTitleFromMessage(fileMessage), "roadmap")

        let imageMessage = Message(role: .user, content: [.image(ImageContent(mimeType: "image/png", data: Data()))])
        XCTAssertEqual(ChatMessagePreparationSupport.fallbackTitleFromMessage(imageMessage), "Image")
    }

    func testEditableUserTextTrimsAndJoinsOnlyTextParts() {
        let message = Message(
            role: .user,
            content: [
                .text("  First  "),
                .image(ImageContent(mimeType: "image/png", data: Data())),
                .text(" \n "),
                .text("Second")
            ]
        )

        XCTAssertEqual(ChatMessageRenderPipeline.editableUserText(from: message), "First\n\nSecond")
    }

    func testEditableUserTextFromRenderedBlocksIgnoresNonText() {
        let blocks: [RenderedMessageBlock] = [
            .content(anchorID: "q", part: .quote(QuoteContent(sourceRole: .assistant, quotedText: "Quoted"))),
            .content(anchorID: "t0", part: .text("  First  ")),
            .content(anchorID: "img", part: .image(RenderedImageContent(
                mimeType: "image/png",
                inlineData: nil,
                url: nil,
                assetDisposition: .managed,
                deferredSource: nil
            ))),
            .content(anchorID: "t1", part: .text("Second")),
        ]

        XCTAssertEqual(
            ChatMessageEditingSupport.editableUserText(fromRenderedBlocks: blocks),
            "First\n\nSecond"
        )
    }

    func testResolvedRemoteVideoInputURLReturnsNilWhenExplicitInputUnsupported() throws {
        XCTAssertNil(
            try ChatMessagePreparationSupport.resolvedRemoteVideoInputURL(
                from: "https://cdn.example.com/a.mp4",
                supportsExplicitRemoteVideoURLInput: false
            )
        )

        XCTAssertEqual(
            try ChatMessagePreparationSupport.resolvedRemoteVideoInputURL(
                from: "https://cdn.example.com/a.mp4",
                supportsExplicitRemoteVideoURLInput: true
            ),
            URL(string: "https://cdn.example.com/a.mp4")
        )

        XCTAssertThrowsError(
            try ChatMessagePreparationSupport.resolvedRemoteVideoInputURL(
                from: "file:///tmp/a.mp4",
                supportsExplicitRemoteVideoURLInput: true
            )
        )
    }
}
