import XCTest
@testable import Jin

final class ConversationSearchCacheTests: XCTestCase {

    // MARK: - extractSnippet

    func testExtractSnippet_findsMatchAndShowsContext() {
        let text = "The quick brown fox jumps over the lazy dog"
        let snippet = ConversationSearchCache.extractSnippet(from: text, query: "fox")

        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("fox"))
    }

    func testExtractSnippet_returnsNilForNoMatch() {
        let text = "Hello world"
        let snippet = ConversationSearchCache.extractSnippet(from: text, query: "xyz")

        XCTAssertNil(snippet)
    }

    func testExtractSnippet_caseInsensitive() {
        let text = "Hello World"
        let snippet = ConversationSearchCache.extractSnippet(from: text, query: "hello")

        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("Hello"))
    }

    func testExtractSnippet_addsPrefixEllipsisWhenTruncated() {
        let text = String(repeating: "x", count: 50) + "TARGET" + String(repeating: "y", count: 50)
        let snippet = ConversationSearchCache.extractSnippet(from: text, query: "TARGET")

        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.hasPrefix("…"))
    }

    func testExtractSnippet_addsSuffixEllipsisWhenTruncated() {
        let text = "TARGET" + String(repeating: "y", count: 200)
        let snippet = ConversationSearchCache.extractSnippet(from: text, query: "TARGET")

        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.hasSuffix("…"))
    }

    func testExtractSnippet_noEllipsisForShortText() {
        let text = "hello world"
        let snippet = ConversationSearchCache.extractSnippet(from: text, query: "hello")

        XCTAssertEqual(snippet, "hello world")
    }

    func testExtractSnippet_collapsesNewlines() {
        let text = "Hello\nworld\nfoo"
        let snippet = ConversationSearchCache.extractSnippet(from: text, query: "world")

        XCTAssertNotNil(snippet)
        XCTAssertFalse(snippet!.contains("\n"))
        XCTAssertTrue(snippet!.contains("Hello world foo"))
    }

    func testExtractSnippet_handlesCJKText() {
        let text = "这是一段中文测试文本，用于验证搜索功能"
        let snippet = ConversationSearchCache.extractSnippet(from: text, query: "搜索")

        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("搜索"))
    }

    // MARK: - extractSearchableText

    func testExtractSearchableText_extractsUserAndAssistantOnly() throws {
        let encoder = JSONEncoder()

        let messages = [
            MessageEntity(role: "user", contentData: try encoder.encode([ContentPart.text("Hello from user")])),
            MessageEntity(role: "assistant", contentData: try encoder.encode([ContentPart.text("Hello from assistant")])),
            MessageEntity(role: "tool", contentData: try encoder.encode([ContentPart.text("Tool result")])),
            MessageEntity(role: "system", contentData: try encoder.encode([ContentPart.text("System prompt")])),
        ]

        let text = ConversationSearchCache.extractSearchableText(from: messages)

        XCTAssertTrue(text.contains("Hello from user"))
        XCTAssertTrue(text.contains("Hello from assistant"))
        XCTAssertFalse(text.contains("Tool result"))
        XCTAssertFalse(text.contains("System prompt"))
    }

    func testExtractSearchableText_excludesThinkingBlocks() throws {
        let encoder = JSONEncoder()

        let content: [ContentPart] = [
            .text("Visible text"),
            .thinking(ThinkingBlock(text: "Internal reasoning")),
        ]
        let messages = [
            MessageEntity(role: "assistant", contentData: try encoder.encode(content)),
        ]

        let text = ConversationSearchCache.extractSearchableText(from: messages)

        XCTAssertTrue(text.contains("Visible text"))
        XCTAssertFalse(text.contains("Internal reasoning"))
    }

    func testExtractSearchableText_includesFilenames() throws {
        let encoder = JSONEncoder()

        let content: [ContentPart] = [
            .file(FileContent(mimeType: "application/pdf", filename: "report.pdf")),
        ]
        let messages = [
            MessageEntity(role: "user", contentData: try encoder.encode(content)),
        ]

        let text = ConversationSearchCache.extractSearchableText(from: messages)

        XCTAssertTrue(text.contains("report.pdf"))
    }

    func testExtractSearchableText_handlesEmptyMessages() {
        let text = ConversationSearchCache.extractSearchableText(from: [])
        XCTAssertEqual(text, "")
    }

    func testExtractSearchableText_handlesInvalidContentData() {
        let messages = [
            MessageEntity(role: "user", contentData: Data("invalid json".utf8)),
        ]

        let text = ConversationSearchCache.extractSearchableText(from: messages)
        XCTAssertEqual(text, "")
    }

    func testExtractSearchableText_joinsMultipleTextParts() throws {
        let encoder = JSONEncoder()

        let content: [ContentPart] = [
            .text("First part"),
            .text("Second part"),
        ]
        let messages = [
            MessageEntity(role: "user", contentData: try encoder.encode(content)),
        ]

        let text = ConversationSearchCache.extractSearchableText(from: messages)

        XCTAssertTrue(text.contains("First part"))
        XCTAssertTrue(text.contains("Second part"))
    }
}
