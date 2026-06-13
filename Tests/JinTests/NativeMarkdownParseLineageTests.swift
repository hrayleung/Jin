import XCTest
@testable import Jin

/// Guards the recycled-cell stale-parse fix: a `NativeMarkdownView` may reuse a
/// retained parse only when it belongs to the current content lineage, never
/// for a different message that recycled into its preserved `@State`.
final class NativeMarkdownParseLineageTests: XCTestCase {

    private func key(
        _ text: String,
        streaming: Bool = false,
        plain: Bool = false,
        appFont: String = "system",
        codeFont: String = "mono"
    ) -> NativeMarkdownCache.Key {
        NativeMarkdownCache.Key(
            markdownText: text,
            isStreaming: streaming,
            renderPlainText: plain,
            appFontFamily: appFont,
            codeFontFamily: codeFont
        )
    }

    func testNilRetainedNeverMatches() {
        XCTAssertFalse(NativeMarkdownParseLineage.matches(current: key("hello"), retained: nil))
    }

    func testIdenticalKeyMatches() {
        XCTAssertTrue(NativeMarkdownParseLineage.matches(current: key("hello"), retained: key("hello")))
    }

    func testStreamingGrowthMatches() {
        // Same message growing across flushes (key grows but text is a prefix).
        let earlier = key("The user wants", streaming: true)
        let later = key("The user wants an interactive dashboard", streaming: true)
        XCTAssertTrue(NativeMarkdownParseLineage.matches(current: later, retained: earlier))
    }

    func testStreamingToPersistedSwapMatches() {
        // Final streaming parse standing in for the persisted (non-streaming)
        // render of the same text — must not flash the placeholder.
        let streamed = key("final answer text", streaming: true)
        let persisted = key("final answer text", streaming: false)
        XCTAssertTrue(NativeMarkdownParseLineage.matches(current: persisted, retained: streamed))
    }

    func testDifferentMessageDoesNotMatch() {
        // The recycled-cell case: a wholly different message must fall back to
        // the placeholder, not show the retained parse.
        let other = key("Completely different message about chemistry")
        let current = key("Here is some Swift code")
        XCTAssertFalse(NativeMarkdownParseLineage.matches(current: current, retained: other))
    }

    func testFontChangeDoesNotMatch() {
        // A retained parse from a different font must not be reused (the
        // re-parse with the new font wins).
        let oldFont = key("hello", appFont: "system")
        let newFont = key("hello", appFont: "Menlo")
        XCTAssertFalse(NativeMarkdownParseLineage.matches(current: newFont, retained: oldFont))
    }

    func testRenderModeChangeDoesNotMatch() {
        let rich = key("hello", plain: false)
        let plain = key("hello", plain: true)
        XCTAssertFalse(NativeMarkdownParseLineage.matches(current: plain, retained: rich))
    }

    func testEmptyRetainedTextDoesNotMatchNonEmpty() {
        // An empty parse is a prefix of everything; don't let it stand in for a
        // real message.
        let empty = key("", streaming: true)
        let real = key("a real message", streaming: true)
        XCTAssertFalse(NativeMarkdownParseLineage.matches(current: real, retained: empty))
    }
}
