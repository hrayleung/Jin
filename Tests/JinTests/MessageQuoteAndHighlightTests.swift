import Foundation
import SwiftData
import XCTest
@testable import Jin

final class MessageQuoteAndHighlightTests: XCTestCase {
    func testQuoteContentRoundTrip() throws {
        let original: [ContentPart] = [
            .quote(
                QuoteContent(
                    sourceMessageID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    sourceThreadID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    sourceRole: .assistant,
                    sourceModelName: "gpt-test",
                    quotedText: "Quoted paragraph",
                    prefixContext: "Before",
                    suffixContext: "After",
                    createdAt: Date(timeIntervalSinceReferenceDate: 1234)
                )
            )
        ]

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([ContentPart].self, from: encoded)

        guard case .quote(let quote) = decoded[0] else {
            return XCTFail("Expected quote content")
        }
        XCTAssertEqual(quote.sourceRole, .assistant)
        XCTAssertEqual(quote.sourceModelName, "gpt-test")
        XCTAssertEqual(quote.quotedText, "Quoted paragraph")
        XCTAssertEqual(quote.prefixContext, "Before")
        XCTAssertEqual(quote.suffixContext, "After")
    }

    func testConversationSearchCacheIncludesQuotedText() throws {
        let encoder = JSONEncoder()
        let content: [ContentPart] = [
            .quote(
                QuoteContent(
                    sourceMessageID: UUID(),
                    sourceRole: .assistant,
                    quotedText: "Searchable quote text"
                )
            ),
            .text("Follow-up question")
        ]

        let messages = [
            MessageEntity(role: MessageRole.user.rawValue, contentData: try encoder.encode(content))
        ]

        let text = ConversationSearchCache.extractSearchableText(from: messages)
        XCTAssertTrue(text.contains("Searchable quote text"))
        XCTAssertTrue(text.contains("Follow-up question"))
    }

    func testUpdateUserMessageContentPreservesQuoteParts() throws {
        let quote = QuoteContent(
            sourceMessageID: UUID(),
            sourceRole: .assistant,
            quotedText: "Preserved quote"
        )
        let original = Message(
            role: .user,
            content: [.quote(quote), .text("Original body")]
        )
        let entity = try MessageEntity.fromDomain(original)

        try ChatMessageEditingSupport.updateUserMessageContent(entity, newText: "Updated body")
        let decoded = try JSONDecoder().decode([ContentPart].self, from: entity.contentData)

        XCTAssertEqual(decoded.count, 2)
        guard case .quote(let decodedQuote) = decoded[0] else {
            return XCTFail("Expected quote part to be preserved")
        }
        XCTAssertEqual(decodedQuote.quotedText, "Preserved quote")
        guard case .text(let updatedText) = decoded[1] else {
            return XCTFail("Expected updated text part")
        }
        XCTAssertEqual(updatedText, "Updated body")
    }

    func testMessageHighlightEntityPersistsAndBuildsSnapshots() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-highlight-tests-\(UUID().uuidString)", isDirectory: false)
        let container = try PersistenceContainerFactory.makeContainer(storeURL: storeURL)
        let context = ModelContext(container)

        let conversation = ConversationEntity(
            title: "Test",
            providerID: "openai",
            modelID: "gpt-test",
            modelConfigData: try JSONEncoder().encode(GenerationControls())
        )
        let message = try MessageEntity.fromDomain(
            Message(role: .assistant, content: [.text("Assistant answer")])
        )
        message.conversation = conversation
        conversation.messages.append(message)

        let highlight = MessageHighlightEntity(
            messageID: message.id,
            conversationID: conversation.id,
            contextThreadID: UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
            anchorID: "\(message.id.uuidString):block:0",
            selectedText: "Assistant",
            prefixContext: "",
            suffixContext: " answer",
            startOffset: 0,
            endOffset: 9
        )
        highlight.message = message
        highlight.conversation = conversation
        message.highlights.append(highlight)
        conversation.messageHighlights.append(highlight)

        context.insert(conversation)
        context.insert(message)
        context.insert(highlight)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MessageHighlightEntity>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].snapshot.selectedText, "Assistant")
        XCTAssertEqual(message.highlightSnapshots.first?.anchorID, "\(message.id.uuidString):block:0")
    }
}
