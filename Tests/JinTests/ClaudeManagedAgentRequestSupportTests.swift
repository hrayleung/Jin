import XCTest
@testable import Jin

final class ClaudeManagedAgentRequestSupportTests: XCTestCase {
    func testSystemPromptCombinesOnlyNonEmptySystemTextParts() {
        let messages = [
            Message(
                role: .system,
                content: [
                    .text(" First instruction "),
                    .image(ImageContent(mimeType: "image/png", data: Data([0x01]))),
                    .text("\n"),
                    .text("Second instruction")
                ]
            ),
            Message(role: .user, content: [.text("Hello")])
        ]

        XCTAssertEqual(
            ClaudeManagedAgentRequestSupport.systemPrompt(from: messages),
            "First instruction\nSecond instruction"
        )
    }

    func testSessionStateParsesDirectSessionIDAndRemoteModel() throws {
        let state = try ClaudeManagedAgentRequestSupport.sessionState(from: [
            "id": " sess_123 ",
            "model": [
                "id": " claude-sonnet-4-6 "
            ]
        ])

        XCTAssertEqual(state.remoteSessionID, "sess_123")
        XCTAssertEqual(state.remoteModelID, "claude-sonnet-4-6")
    }

    func testSessionStateParsesNestedSessionIDAndRemoteModel() throws {
        let state = try ClaudeManagedAgentRequestSupport.sessionState(from: [
            "session": [
                "id": " sess_nested ",
                "model": [
                    "id": "claude-opus-4-5"
                ]
            ]
        ])

        XCTAssertEqual(state.remoteSessionID, "sess_nested")
        XCTAssertEqual(state.remoteModelID, "claude-opus-4-5")
    }

    func testSessionStateRejectsMissingSessionID() {
        XCTAssertThrowsError(try ClaudeManagedAgentRequestSupport.sessionState(from: [
            "session": [
                "model": [
                    "id": "claude-sonnet-4-6"
                ]
            ]
        ])) { error in
            guard case LLMError.decodingError(let message) = error else {
                return XCTFail("Expected decoding error, got \(error)")
            }
            XCTAssertTrue(message.contains("did not include an id"))
        }
    }

    func testEventBodiesPreferPendingCustomToolResults() throws {
        var controls = GenerationControls()
        controls.claudeManagedPendingCustomToolResults = [
            ClaudeManagedAgentPendingToolResult(
                eventID: "custom_1",
                toolCallID: "tool_call_1",
                toolName: "lookup",
                content: "  ",
                isError: true,
                sessionThreadID: " thread_1 "
            )
        ]

        let events = try ClaudeManagedAgentRequestSupport.eventBodies(
            messages: [
                Message(role: .user, content: [.text("Ignored while tool result is pending")])
            ],
            controls: controls
        )

        let event = try XCTUnwrap(events.single)
        XCTAssertEqual(event["type"] as? String, "user.custom_tool_result")
        XCTAssertEqual(event["custom_tool_use_id"] as? String, "custom_1")
        XCTAssertEqual(event["is_error"] as? Bool, true)
        XCTAssertEqual(event["session_thread_id"] as? String, "thread_1")

        let content = try XCTUnwrap(event["content"] as? [[String: Any]])
        XCTAssertEqual(content.single?["type"] as? String, "text")
        XCTAssertEqual(content.single?["text"] as? String, "<empty_content>")
    }

    func testEventBodiesBuildUserMessageBlocksForSupportedAndFallbackAttachments() throws {
        let controls = GenerationControls()
        let imageData = Data([0x89, 0x50])
        let pdfData = Data("%PDF-1.7".utf8)
        let message = Message(
            role: .user,
            content: [
                .text("Question"),
                .quote(QuoteContent(quotedText: "quoted text")),
                .image(ImageContent(mimeType: "image/png", data: imageData)),
                .file(FileContent(mimeType: "application/pdf", filename: "report.pdf", data: pdfData)),
                .file(FileContent(mimeType: "text/plain", filename: "notes.txt", data: Data("notes".utf8))),
                .video(VideoContent(mimeType: "video/mp4", data: Data([0x00, 0x01]))),
                .audio(AudioContent(mimeType: "audio/wav", data: Data([0x02]))),
                .thinking(ThinkingBlock(text: "hidden", signature: nil))
            ]
        )

        let events = try ClaudeManagedAgentRequestSupport.eventBodies(
            messages: [message],
            controls: controls
        )

        let event = try XCTUnwrap(events.single)
        XCTAssertEqual(event["type"] as? String, "user.message")

        let content = try XCTUnwrap(event["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 7)
        XCTAssertEqual(content[0]["text"] as? String, "Question")
        XCTAssertEqual(content[1]["text"] as? String, "quoted text")

        XCTAssertEqual(content[2]["type"] as? String, "image")
        let imageSource = try XCTUnwrap(content[2]["source"] as? [String: Any])
        XCTAssertEqual(imageSource["media_type"] as? String, "image/png")
        XCTAssertEqual(imageSource["data"] as? String, imageData.base64EncodedString())

        XCTAssertEqual(content[3]["type"] as? String, "document")
        let documentSource = try XCTUnwrap(content[3]["source"] as? [String: Any])
        XCTAssertEqual(documentSource["media_type"] as? String, "application/pdf")
        XCTAssertEqual(documentSource["data"] as? String, pdfData.base64EncodedString())

        XCTAssertEqual(content[4]["type"] as? String, "text")
        XCTAssertTrue((content[4]["text"] as? String)?.contains("notes.txt") == true)
        XCTAssertTrue((content[5]["text"] as? String)?.contains("Video attachment omitted") == true)
        XCTAssertEqual(content[6]["text"] as? String, "[Audio attachment]")
    }

    func testEventBodiesNormalizesPDFMimeTypeBeforeChoosingDocumentBlock() throws {
        let pdfData = Data("%PDF-1.7".utf8)
        let message = Message(
            role: .user,
            content: [
                .file(FileContent(mimeType: " Application/PDF \n", filename: "report.pdf", data: pdfData))
            ]
        )

        let events = try ClaudeManagedAgentRequestSupport.eventBodies(
            messages: [message],
            controls: GenerationControls()
        )

        let event = try XCTUnwrap(events.single)
        let content = try XCTUnwrap(event["content"] as? [[String: Any]])
        XCTAssertEqual(content.single?["type"] as? String, "document")

        let source = try XCTUnwrap(content.single?["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "application/pdf")
        XCTAssertEqual(source["data"] as? String, pdfData.base64EncodedString())
    }

    func testEventBodiesFallsBackToContinueWhenNoUserContentCanBeSent() throws {
        let events = try ClaudeManagedAgentRequestSupport.eventBodies(
            messages: [
                Message(role: .assistant, content: [.text("Previous answer")])
            ],
            controls: GenerationControls()
        )

        let event = try XCTUnwrap(events.single)
        XCTAssertEqual(event["type"] as? String, "user.message")
        let content = try XCTUnwrap(event["content"] as? [[String: Any]])
        XCTAssertEqual(content.single?["text"] as? String, "Continue.")
    }

    func testSessionEventsBodyWrapsEventsWithoutChangingPayloads() throws {
        let event: [String: Any] = [
            "type": "user.message",
            "content": [["type": "text", "text": "Hello"]]
        ]

        let body = ClaudeManagedAgentRequestSupport.sessionEventsBody(events: [event])

        let events = try XCTUnwrap(body["events"] as? [[String: Any]])
        XCTAssertEqual(events.single?["type"] as? String, "user.message")

        let content = try XCTUnwrap(events.single?["content"] as? [[String: Any]])
        XCTAssertEqual(content.single?["text"] as? String, "Hello")
    }

    func testApprovalEventMapsResponsesToAllowAndDeny() throws {
        let interaction = ManagedAgentInteractionRequest(
            method: "claude_managed_agents/tool_confirmation",
            threadID: "sess_123",
            turnID: "turn_1",
            itemID: "approval_1",
            kind: .commandApproval(ManagedAgentCommandApprovalRequest(command: "shell", cwd: nil, reason: nil, actionSummaries: []))
        )

        let acceptEvent = try ClaudeManagedAgentRequestSupport.approvalEvent(
            from: interaction,
            response: .approval(.acceptForSession)
        )
        XCTAssertEqual(acceptEvent["type"] as? String, "user.tool_confirmation")
        XCTAssertEqual(acceptEvent["tool_use_id"] as? String, "approval_1")
        XCTAssertEqual(acceptEvent["result"] as? String, "allow")

        let declineEvent = try ClaudeManagedAgentRequestSupport.approvalEvent(
            from: interaction,
            response: .approval(.decline)
        )
        XCTAssertEqual(declineEvent["result"] as? String, "deny")

        let cancelledEvent = try ClaudeManagedAgentRequestSupport.approvalEvent(
            from: interaction,
            response: .cancelled(message: nil)
        )
        XCTAssertEqual(cancelledEvent["result"] as? String, "deny")
        XCTAssertNil(cancelledEvent["deny_message"])
    }

    func testApprovalEventIncludesTrimmedCancelMessageForDeniedReply() throws {
        let interaction = ManagedAgentInteractionRequest(
            method: "claude_managed_agents/tool_confirmation",
            threadID: "sess_123",
            turnID: "turn_1",
            itemID: "approval_1",
            kind: .commandApproval(ManagedAgentCommandApprovalRequest(command: "shell", cwd: nil, reason: nil, actionSummaries: []))
        )

        let event = try ClaudeManagedAgentRequestSupport.approvalEvent(
            from: interaction,
            response: .cancelled(message: "  Cancelled by user  ")
        )

        XCTAssertEqual(event["result"] as? String, "deny")
        XCTAssertEqual(event["deny_message"] as? String, "Cancelled by user")
    }

    func testApprovalEventRejectsUserInputResponsesAndMissingItemID() {
        let interaction = ManagedAgentInteractionRequest(
            method: "claude_managed_agents/tool_confirmation",
            threadID: "sess_123",
            turnID: nil,
            itemID: "approval_1",
            kind: .commandApproval(ManagedAgentCommandApprovalRequest(command: nil, cwd: nil, reason: nil, actionSummaries: []))
        )

        XCTAssertThrowsError(try ClaudeManagedAgentRequestSupport.approvalEvent(
            from: interaction,
            response: .userInput([:])
        )) { error in
            guard case LLMError.invalidRequest(let message) = error else {
                return XCTFail("Expected invalid request, got \(error)")
            }
            XCTAssertTrue(message.contains("does not accept free-form user input"))
        }

        let missingItemInteraction = ManagedAgentInteractionRequest(
            method: "claude_managed_agents/tool_confirmation",
            threadID: "sess_123",
            turnID: nil,
            itemID: nil,
            kind: .commandApproval(ManagedAgentCommandApprovalRequest(command: nil, cwd: nil, reason: nil, actionSummaries: []))
        )
        XCTAssertThrowsError(try ClaudeManagedAgentRequestSupport.approvalEvent(
            from: missingItemInteraction,
            response: .approval(.accept)
        )) { error in
            guard case LLMError.invalidRequest(let message) = error else {
                return XCTFail("Expected invalid request, got \(error)")
            }
            XCTAssertTrue(message.contains("missing the required event identifier"))
        }
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
