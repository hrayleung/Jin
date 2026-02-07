import XCTest
@testable import Jin

final class ConversationTitleGeneratorTests: XCTestCase {
    func testNormalizeTitleTrimsQuotesAndPrefixAndNewline() {
        let raw = "\n\"Title:  深度学习 入门\n第二行\"\n"
        let normalized = ConversationTitleGenerator.normalizeTitle(raw, maxCharacters: 50)
        XCTAssertEqual(normalized, "深度学习 入门")
    }

    func testNormalizeTitleHandlesChineseTitlePrefix() {
        let raw = "标题:   Swift 并发实践"
        let normalized = ConversationTitleGenerator.normalizeTitle(raw, maxCharacters: 50)
        XCTAssertEqual(normalized, "Swift 并发实践")
    }

    func testNormalizeTitleCollapsesSpacesAndCapsLength() {
        let raw = "  This    is    a     very long chat title  "
        let normalized = ConversationTitleGenerator.normalizeTitle(raw, maxCharacters: 12)
        XCTAssertEqual(normalized, "This is a ve")
    }
}
