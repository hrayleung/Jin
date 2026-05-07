import XCTest
@testable import Jin

final class TextToSpeechTextChunkerTests: XCTestCase {
    func testChunksTrimInputAndDropBlankText() {
        XCTAssertEqual(
            TextToSpeechTextChunker.chunks(for: "  Hello world\n", maxCharacters: 100),
            ["Hello world"]
        )
        XCTAssertEqual(TextToSpeechTextChunker.chunks(for: " \n\t ", maxCharacters: 100), [])
    }

    func testChunksPackParagraphsUntilLimit() {
        let text = """
        One
        Two
        Three
        Four
        """

        XCTAssertEqual(
            TextToSpeechTextChunker.chunks(for: text, maxCharacters: 13),
            [
                "One\nTwo\nThree",
                "Four"
            ]
        )
    }

    func testChunksHardSplitLongParagraphs() {
        XCTAssertEqual(
            TextToSpeechTextChunker.chunks(for: "abcdefg", maxCharacters: 3),
            ["abc", "def", "g"]
        )
    }

    func testChunksPreserveTrimmedTextForInvalidLimit() {
        XCTAssertEqual(
            TextToSpeechTextChunker.chunks(for: "  abcdef  ", maxCharacters: 0),
            ["abcdef"]
        )
    }
}
