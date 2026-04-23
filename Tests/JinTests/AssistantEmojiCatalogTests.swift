import XCTest
@testable import Jin

final class AssistantEmojiCatalogTests: XCTestCase {
    func testSearchHaystackIncludesUnicodeAnnotationName() {
        let haystack = AssistantEmojiCatalog.searchHaystack(for: "😄")

        XCTAssertTrue(haystack.contains("grinning face with smiling eyes"))
    }

    func testEmojiSearchMatchesAnnotationPrefix() {
        XCTAssertTrue(AssistantEmojiCatalog.matchesSearchQuery("smi", emoji: "😄"))
    }

    func testEmojiSearchMatchesGroupTerms() {
        XCTAssertTrue(AssistantEmojiCatalog.matchesSearchQuery("smile", emoji: "😀"))
    }

    func testEmojiSearchRejectsUnrelatedTerms() {
        XCTAssertFalse(AssistantEmojiCatalog.matchesSearchQuery("banana", emoji: "😀"))
    }
}
