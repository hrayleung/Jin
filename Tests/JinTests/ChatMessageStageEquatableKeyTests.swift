import XCTest
@testable import Jin

final class ChatMessageStageEquatableKeyTests: XCTestCase {
    func testSingleThreadKeyEqualsForIdenticalInputs() {
        let conversationID = UUID()
        let messageID = UUID()
        let expandedID = UUID()

        let first = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 1,
            renderRevision: 4,
            viewportHeight: 600,
            allMessageCount: 1,
            lastMessageID: messageID,
            toolResultCount: 1,
            entityCount: 1,
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 120,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: [expandedID]
        )

        let second = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 1,
            renderRevision: 4,
            viewportHeight: 600,
            allMessageCount: 1,
            lastMessageID: messageID,
            toolResultCount: 1,
            entityCount: 1,
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 120,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: [expandedID]
        )

        XCTAssertEqual(first, second)
    }

    func testSingleThreadKeyIgnoresWidthOnlyContainerSizeChanges() {
        let conversationID = UUID()
        let messageID = UUID()

        func makeKey(containerSize: CGSize) -> ChatStageEquatableKey {
            ChatMessageStageEquatableKeyBuilder.singleThreadKey(
                conversationID: conversationID,
                conversationMessageCount: 1,
                renderRevision: 1,
                viewportHeight: containerSize.height,
                allMessageCount: 1,
                lastMessageID: messageID,
                toolResultCount: 0,
                entityCount: 0,
                assistantDisplayName: "Assistant",
                providerType: nil,
                providerIconID: nil,
                composerHeight: 80,
                isStreaming: false,
                streamingObjectID: nil,
                streamingModelLabel: nil,
                streamingModelID: nil,
                expandedCollapsedMessageIDs: []
            )
        }

        let base = makeKey(containerSize: CGSize(width: 900, height: 600))
        let afterSidebarToggle = makeKey(containerSize: CGSize(width: 1_200, height: 600))
        let withViewportHeightChange = makeKey(containerSize: CGSize(width: 900, height: 580))

        XCTAssertEqual(base, afterSidebarToggle)
        XCTAssertNotEqual(base, withViewportHeightChange)
    }

    func testSingleThreadKeyChangesForMessageAndComposerChanges() {
        let conversationID = UUID()
        let messageID = UUID()

        let base = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 1,
            renderRevision: 1,
            viewportHeight: 600,
            allMessageCount: 1,
            lastMessageID: messageID,
            toolResultCount: 0,
            entityCount: 0,
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 80,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: []
        )

        let withNewMessage = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 2,
            renderRevision: 2,
            viewportHeight: 600,
            allMessageCount: 2,
            lastMessageID: UUID(),
            toolResultCount: 0,
            entityCount: 0,
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 80,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: []
        )

        let withComposerHeightChange = ChatMessageStageEquatableKeyBuilder.singleThreadKey(
            conversationID: conversationID,
            conversationMessageCount: 1,
            renderRevision: 1,
            viewportHeight: 600,
            allMessageCount: 1,
            lastMessageID: messageID,
            toolResultCount: 0,
            entityCount: 0,
            assistantDisplayName: "Assistant",
            providerType: nil,
            providerIconID: nil,
            composerHeight: 140,
            isStreaming: false,
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil,
            expandedCollapsedMessageIDs: []
        )

        XCTAssertNotEqual(base, withNewMessage)
        XCTAssertNotEqual(base, withComposerHeightChange)
    }

    func testSingleThreadKeyChangesForUserMessageEditingState() {
        let conversationID = UUID()
        let messageID = UUID()
        let editingMessageID = UUID()
        let server = SlashCommandMCPServerItem(id: "server-1", name: "Server One", isSelected: false)
        let chip = SlashCommandMCPServerItem(id: "server-1", name: "Server One", isSelected: true)

        func makeKey(
            editingUserMessageID: UUID? = nil,
            editSlashCommandKey: ChatEditSlashCommandEquatableKey = .inactive
        ) -> ChatStageEquatableKey {
            ChatMessageStageEquatableKeyBuilder.singleThreadKey(
                conversationID: conversationID,
                conversationMessageCount: 1,
                renderRevision: 1,
                viewportHeight: 600,
                allMessageCount: 1,
                lastMessageID: messageID,
                toolResultCount: 0,
                entityCount: 1,
                assistantDisplayName: "Assistant",
                providerType: nil,
                providerIconID: nil,
                composerHeight: 80,
                isStreaming: false,
                streamingObjectID: nil,
                streamingModelLabel: nil,
                streamingModelID: nil,
                editingUserMessageID: editingUserMessageID,
                editSlashCommandKey: editSlashCommandKey,
                expandedCollapsedMessageIDs: []
            )
        }

        let inactive = makeKey()
        let editing = makeKey(editingUserMessageID: editingMessageID)
        let activeSlash = ChatEditSlashCommandEquatableKey(
            context: EditSlashCommandContext(
                servers: [server],
                isActive: true,
                filterText: "ser",
                highlightedIndex: 0,
                perMessageChips: [],
                onSelectServer: { _ in },
                onDismiss: {},
                onRemovePerMessageServer: { _ in },
                onInterceptKeyDown: nil
            )
        )
        let withSelectedServer = ChatEditSlashCommandEquatableKey(
            context: EditSlashCommandContext(
                servers: [],
                isActive: false,
                filterText: "",
                highlightedIndex: 0,
                perMessageChips: [chip],
                onSelectServer: { _ in },
                onDismiss: {},
                onRemovePerMessageServer: { _ in },
                onInterceptKeyDown: nil
            )
        )

        XCTAssertNotEqual(inactive, editing)
        XCTAssertNotEqual(editing, makeKey(editingUserMessageID: editingMessageID, editSlashCommandKey: activeSlash))
        XCTAssertNotEqual(editing, makeKey(editingUserMessageID: editingMessageID, editSlashCommandKey: withSelectedServer))
    }
}
