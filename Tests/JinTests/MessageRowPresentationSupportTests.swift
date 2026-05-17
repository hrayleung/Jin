import CoreGraphics
import XCTest
@testable import Jin

final class MessageRowPresentationSupportTests: XCTestCase {
    func testNormalizedAssistantModelLabelTrimsWhitespaceAndRejectsBlankLabels() {
        XCTAssertEqual(
            MessageRowPresentationSupport.normalizedAssistantModelLabel(" \n GPT-5\t "),
            "GPT-5"
        )
        XCTAssertNil(MessageRowPresentationSupport.normalizedAssistantModelLabel(nil))
        XCTAssertNil(MessageRowPresentationSupport.normalizedAssistantModelLabel(" \n\t "))
    }

    func testNormalizedMCPServerNamesTrimsSkipsBlankNamesAndDeduplicates() {
        XCTAssertEqual(
            MessageRowPresentationSupport.normalizedMCPServerNames([
                " github ",
                " \n ",
                "linear",
                "github",
                "\tfigma\n"
            ]),
            ["github", "linear", "figma"]
        )
    }

    func testTimestampTextUsesTodayYesterdayAndOlderLabels() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 5,
            hour: 12
        ).date)
        let today = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 5,
            hour: 9,
            minute: 30
        ).date)
        let yesterday = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 4,
            hour: 22,
            minute: 15
        ).date)
        let older = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 30,
            hour: 8
        ).date)

        XCTAssertEqual(
            MessageRowPresentationSupport.timestampText(for: today, now: now, calendar: calendar),
            today.formatted(date: .omitted, time: .shortened)
        )
        XCTAssertEqual(
            MessageRowPresentationSupport.timestampText(for: yesterday, now: now, calendar: calendar),
            "Yesterday \(yesterday.formatted(date: .omitted, time: .shortened))"
        )
        XCTAssertEqual(
            MessageRowPresentationSupport.timestampText(for: older, now: now, calendar: calendar),
            "\(older.formatted(.dateTime.month(.abbreviated).day().year())) \(older.formatted(date: .omitted, time: .shortened))"
        )
    }

    func testPresentationDerivesRoleCopyAndWidthState() {
        let item = makeItem(role: .user, copyText: "Hello")
        let presentation = MessageRowPresentationSupport.Presentation(
            item: item,
            maxBubbleWidth: 800,
            providerType: .openai,
            renderMode: .fullWeb,
            editingUserMessageID: item.id
        )

        XCTAssertTrue(presentation.isUser)
        XCTAssertFalse(presentation.isAssistant)
        XCTAssertTrue(presentation.isEditingUserMessage)
        XCTAssertEqual(presentation.copyText, "Hello")
        XCTAssertTrue(presentation.showsCopyButton)
        XCTAssertTrue(presentation.canEditUserMessage)
        XCTAssertTrue(presentation.rendersRow)
        XCTAssertEqual(
            presentation.effectiveMaxBubbleWidth,
            ChatConversationLayoutMetrics.userBubbleMaxWidth(for: 800)
        )
    }

    func testPresentationSanitizesInvalidBubbleWidth() {
        let item = makeItem(role: .assistant, copyText: "Hello")
        let presentation = MessageRowPresentationSupport.Presentation(
            item: item,
            maxBubbleWidth: .nan,
            providerType: nil,
            renderMode: .fullWeb,
            editingUserMessageID: nil
        )

        XCTAssertEqual(presentation.effectiveMaxBubbleWidth, 0)
    }

    func testPresentationFiltersManagedAgentInternalUI() {
        let thinkingBlock = RenderedMessageBlock.content(
            anchorID: "thinking",
            part: .thinking(ThinkingBlock(text: "internal", signature: nil, provider: nil))
        )
        let redactedBlock = RenderedMessageBlock.content(
            anchorID: "redacted",
            part: .redactedThinking(RedactedThinkingBlock(data: "hidden", provider: nil))
        )
        let textBlock = RenderedMessageBlock.content(anchorID: "text", part: .text("visible"))
        let item = makeItem(
            role: .assistant,
            renderedBlocks: [thinkingBlock, redactedBlock, textBlock],
            toolCalls: [ToolCall(id: "tool", name: "weather", arguments: [:])],
            codeExecutionActivities: [CodeExecutionActivity(id: "code", status: .inProgress)]
        )

        let presentation = MessageRowPresentationSupport.Presentation(
            item: item,
            maxBubbleWidth: 800,
            providerType: .claudeManagedAgents,
            renderMode: .fullWeb,
            editingUserMessageID: nil
        )

        XCTAssertTrue(presentation.hidesManagedAgentInternalUI)
        XCTAssertTrue(presentation.visibleToolCalls.isEmpty)
        XCTAssertTrue(presentation.visibleCodeExecutionActivities.isEmpty)
        XCTAssertEqual(presentation.visibleRenderedBlocks.count, 1)
        guard case .content("text", .text("visible")) = presentation.visibleRenderedBlocks[0] else {
            return XCTFail("Expected only the visible text block to remain")
        }
    }

    func testAssistantRowVisibilityRequiresVisiblePresentation() {
        let hiddenOnly = makeItem(
            role: .assistant,
            renderedBlocks: [
                .content(
                    anchorID: "thinking",
                    part: .thinking(ThinkingBlock(text: "internal", signature: nil, provider: nil))
                )
            ]
        )
        let hiddenOnlyPresentation = MessageRowPresentationSupport.Presentation(
            item: hiddenOnly,
            maxBubbleWidth: 800,
            providerType: .claudeManagedAgents,
            renderMode: .fullWeb,
            editingUserMessageID: nil
        )

        XCTAssertFalse(hiddenOnlyPresentation.hasVisibleAssistantPresentation)
        XCTAssertFalse(hiddenOnlyPresentation.rendersRow)

        let withSearchActivity = makeItem(
            role: .assistant,
            renderedBlocks: [],
            searchActivities: [SearchActivity(id: "search", type: "search", status: .completed)]
        )
        let searchPresentation = MessageRowPresentationSupport.Presentation(
            item: withSearchActivity,
            maxBubbleWidth: 800,
            providerType: .claudeManagedAgents,
            renderMode: .fullWeb,
            editingUserMessageID: nil
        )

        XCTAssertTrue(searchPresentation.hasVisibleAssistantPresentation)
        XCTAssertTrue(searchPresentation.rendersRow)
    }

    func testCollapsedPreviewParticipatesInPresentationVisibility() {
        let preview = LightweightMessagePreview(
            headline: "Long answer",
            body: "Summarized",
            lineCount: 20,
            containsCode: false
        )
        let item = makeItem(role: .assistant, renderedBlocks: [], collapsedPreview: preview)

        let collapsedPresentation = MessageRowPresentationSupport.Presentation(
            item: item,
            maxBubbleWidth: 800,
            providerType: nil,
            renderMode: .collapsedPreview,
            editingUserMessageID: nil
        )
        let fullPresentation = MessageRowPresentationSupport.Presentation(
            item: item,
            maxBubbleWidth: 800,
            providerType: nil,
            renderMode: .fullWeb,
            editingUserMessageID: nil
        )

        XCTAssertEqual(collapsedPresentation.collapsedPreview, preview)
        XCTAssertTrue(collapsedPresentation.rendersRow)
        XCTAssertNil(fullPresentation.collapsedPreview)
        XCTAssertFalse(fullPresentation.rendersRow)
    }

    func testTextToSpeechPresentationUsesIdleSpeakState() {
        let presentation = MessageRowPresentationSupport.TextToSpeechPresentation(
            copyText: "Hello",
            isConfigured: true,
            isGenerating: false,
            isPlaying: false,
            isPaused: false
        )

        XCTAssertFalse(presentation.isActive)
        XCTAssertFalse(presentation.isPrimaryDisabled)
        XCTAssertEqual(presentation.primarySystemName, "speaker.wave.2")
        XCTAssertEqual(presentation.helpText, "Speak")
        XCTAssertEqual(presentation.stopHelpText, "Stop playback")
    }

    func testTextToSpeechPresentationDisablesWhenUnconfiguredOrEmpty() {
        let unconfigured = MessageRowPresentationSupport.TextToSpeechPresentation(
            copyText: "Hello",
            isConfigured: false,
            isGenerating: false,
            isPlaying: false,
            isPaused: false
        )
        let emptyText = MessageRowPresentationSupport.TextToSpeechPresentation(
            copyText: "",
            isConfigured: true,
            isGenerating: false,
            isPlaying: false,
            isPaused: false
        )

        XCTAssertTrue(unconfigured.isPrimaryDisabled)
        XCTAssertEqual(
            unconfigured.helpText,
            "Configure Text to Speech in Settings → Plugins → Text to Speech"
        )
        XCTAssertTrue(emptyText.isPrimaryDisabled)
        XCTAssertEqual(emptyText.helpText, "Speak")
    }

    func testTextToSpeechPresentationReflectsGeneratingPlaybackStates() {
        let generating = MessageRowPresentationSupport.TextToSpeechPresentation(
            copyText: "Hello",
            isConfigured: true,
            isGenerating: true,
            isPlaying: false,
            isPaused: false
        )
        let playing = MessageRowPresentationSupport.TextToSpeechPresentation(
            copyText: "Hello",
            isConfigured: true,
            isGenerating: false,
            isPlaying: true,
            isPaused: false
        )
        let paused = MessageRowPresentationSupport.TextToSpeechPresentation(
            copyText: "Hello",
            isConfigured: true,
            isGenerating: false,
            isPlaying: false,
            isPaused: true
        )

        XCTAssertTrue(generating.isActive)
        XCTAssertEqual(generating.primarySystemName, "speaker.wave.2")
        XCTAssertEqual(generating.helpText, "Generating speech...")
        XCTAssertEqual(generating.stopHelpText, "Stop generating speech")

        XCTAssertTrue(playing.isActive)
        XCTAssertEqual(playing.primarySystemName, "pause.circle")
        XCTAssertEqual(playing.helpText, "Pause playback")
        XCTAssertEqual(playing.stopHelpText, "Stop playback")

        XCTAssertTrue(paused.isActive)
        XCTAssertEqual(paused.primarySystemName, "play.circle")
        XCTAssertEqual(paused.helpText, "Resume playback")
        XCTAssertEqual(paused.stopHelpText, "Stop playback")
    }

    func testUserBlockPartitionExtractsImagesAndPreservesRemainingOrder() {
        let firstImage = RenderedContentPart.image(
            RenderedImageContent(
                mimeType: "image/png",
                inlineData: Data([1]),
                url: nil,
                assetDisposition: .managed,
                deferredSource: nil
            )
        )
        let secondImage = RenderedContentPart.image(
            RenderedImageContent(
                mimeType: "image/jpeg",
                inlineData: Data([2]),
                url: nil,
                assetDisposition: .managed,
                deferredSource: nil
            )
        )
        let artifact = RenderedArtifactVersion(
            artifactID: "artifact",
            version: 1,
            title: "Artifact",
            contentType: .html,
            content: "<p>Hello</p>",
            sourceMessageID: UUID(),
            sourceTimestamp: Date(timeIntervalSince1970: 1)
        )
        let partition = MessageRowPresentationSupport.UserBlockPartition(
            blocks: [
                .content(anchorID: "text-1", part: .text("before")),
                .content(anchorID: "image-1", part: firstImage),
                .artifact(artifact),
                .content(anchorID: "image-2", part: secondImage),
                .content(anchorID: "text-2", part: .text("after"))
            ]
        )

        XCTAssertEqual(partition.imageParts.count, 2)
        XCTAssertEqual(partition.remainingBlocks.count, 3)

        guard case .image(let extractedFirst) = partition.imageParts[0],
              case .image(let extractedSecond) = partition.imageParts[1] else {
            return XCTFail("Expected image parts to be extracted in original order")
        }
        XCTAssertEqual(extractedFirst.mimeType, "image/png")
        XCTAssertEqual(extractedSecond.mimeType, "image/jpeg")

        guard case .content("text-1", .text("before")) = partition.remainingBlocks[0],
              case .artifact(let remainingArtifact) = partition.remainingBlocks[1],
              case .content("text-2", .text("after")) = partition.remainingBlocks[2] else {
            return XCTFail("Expected non-image blocks to preserve their relative order")
        }
        XCTAssertEqual(remainingArtifact.id, artifact.id)
    }

    private func makeItem(
        role: MessageRole,
        renderedBlocks: [RenderedMessageBlock] = [.content(anchorID: "anchor-0", part: .text("body"))],
        toolCalls: [ToolCall] = [],
        searchActivities: [SearchActivity] = [],
        codeExecutionActivities: [CodeExecutionActivity] = [],
        copyText: String = "body",
        collapsedPreview: LightweightMessagePreview? = nil
    ) -> MessageRenderItem {
        MessageRenderItem(
            id: UUID(),
            role: role.rawValue,
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: renderedBlocks,
            toolCalls: toolCalls,
            searchActivities: searchActivities,
            codeExecutionActivities: codeExecutionActivities,
            assistantModelLabel: nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: copyText,
            preferredRenderMode: .fullWeb,
            isMemoryIntensiveAssistantContent: true,
            collapsedPreview: collapsedPreview,
            canEditUserMessage: role == .user,
            canDeleteResponse: role == .user,
            perMessageMCPServerNames: []
        )
    }
}
