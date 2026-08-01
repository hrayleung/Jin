import SwiftUI
import XCTest
@testable import Jin

/// The epoch gates the same-IDs reconcile: equal epochs skip the wholesale
/// visible-cell re-push. Every stored field must therefore flip equality —
/// a field silently dropped during a refactor would freeze that input's
/// on-screen updates (the gate fails closed only for fields that exist).
@MainActor
final class ChatTimelineContentEpochTests: XCTestCase {

    func testIdenticalInputsCompareEqual() {
        XCTAssertEqual(makeEpoch(), makeEpoch())
    }

    func testEveryFieldParticipatesInEquality() {
        let streamingState = StreamingMessageState()
        XCTAssertNotEqual(makeEpoch(), makeEpoch(renderRevision: 9))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(hiddenCount: 12))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(eagerCodeHighlightStartIndex: 3))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(layoutCenterOffsetBucket: 2))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(assistantDisplayName: "Renamed"))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(providerType: .anthropic))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(providerIconID: "icon"))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(toolResultContent: "changed"))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(entityCount: 5))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(editingUserMessageID: UUID()))
        XCTAssertNotEqual(
            makeEpoch(),
            makeEpoch(editSlashCommandKey: ChatEditSlashCommandEquatableKey(
                context: EditSlashCommandContext(
                    servers: [],
                    isActive: true,
                    filterText: "f",
                    highlightedIndex: 0,
                    perMessageChips: [],
                    onSelectServer: { _ in },
                    onDismiss: {},
                    onRemovePerMessageServer: { _ in },
                    onInterceptKeyDown: nil
                )
            ))
        )
        XCTAssertNotEqual(makeEpoch(), makeEpoch(textToSpeechEnabled: true))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(textToSpeechConfigured: true))
        XCTAssertNotEqual(
            makeEpoch(),
            makeEpoch(textToSpeechPlaybackState: .generating(messageID: UUID()))
        )
        XCTAssertNotEqual(makeEpoch(), makeEpoch(expandedCollapsedMessageIDs: [UUID()]))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(colorScheme: .dark))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(appFontFamily: "Avenir"))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(codeFontFamily: "Menlo"))
        XCTAssertNotEqual(
            makeEpoch(),
            makeEpoch(streamingObjectID: ObjectIdentifier(streamingState))
        )
        XCTAssertNotEqual(makeEpoch(), makeEpoch(streamingModelLabel: "GPT"))
        XCTAssertNotEqual(makeEpoch(), makeEpoch(streamingModelID: "gpt-x"))
    }

    private func makeEpoch(
        renderRevision: Int = 1,
        hiddenCount: Int = 0,
        eagerCodeHighlightStartIndex: Int = 0,
        layoutCenterOffsetBucket: Int = 0,
        assistantDisplayName: String = "Assistant",
        providerType: ProviderType? = nil,
        providerIconID: String? = nil,
        toolResultContent: String = "done",
        entityCount: Int = 1,
        editingUserMessageID: UUID? = nil,
        editSlashCommandKey: ChatEditSlashCommandEquatableKey = .inactive,
        textToSpeechEnabled: Bool = false,
        textToSpeechConfigured: Bool = false,
        textToSpeechPlaybackState: TextToSpeechPlaybackManager.State = .idle,
        expandedCollapsedMessageIDs: Set<UUID> = [],
        colorScheme: ColorScheme = .light,
        appFontFamily: String = "System",
        codeFontFamily: String = "System",
        streamingObjectID: ObjectIdentifier? = nil,
        streamingModelLabel: String? = nil,
        streamingModelID: String? = nil
    ) -> ChatTimelineContentEpoch {
        ChatTimelineContentEpoch(
            renderRevision: renderRevision,
            hiddenCount: hiddenCount,
            eagerCodeHighlightStartIndex: eagerCodeHighlightStartIndex,
            layoutCenterOffsetBucket: layoutCenterOffsetBucket,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: providerIconID,
            toolResultsByCallID: [
                "call_1": ToolResult(
                    id: "result_1",
                    toolCallID: "call_1",
                    toolName: "lookup",
                    content: toolResultContent,
                    isError: false
                ),
            ],
            entityCount: entityCount,
            editingUserMessageID: editingUserMessageID,
            editSlashCommandKey: editSlashCommandKey,
            textToSpeechEnabled: textToSpeechEnabled,
            textToSpeechConfigured: textToSpeechConfigured,
            textToSpeechPlaybackState: textToSpeechPlaybackState,
            expandedCollapsedMessageIDs: expandedCollapsedMessageIDs,
            colorScheme: colorScheme,
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily,
            streamingObjectID: streamingObjectID,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID
        )
    }
}
