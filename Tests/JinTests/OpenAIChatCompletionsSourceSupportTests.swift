import XCTest
@testable import Jin

final class OpenAIChatCompletionsSourceSupportTests: XCTestCase {
    func testSourcesMarkdownUsesSearchResultsBeforeCitations() {
        let markdown = OpenAIChatCompletionsSourceSupport.sourcesMarkdown(
            citations: [
                "https://fallback.example.com"
            ],
            searchResults: [
                OpenAIChatCompletionsSearchResult(
                    title: "Foo [Docs]",
                    url: "https://foo.example.com",
                    snippet: " Foo\nsnippet "
                ),
                OpenAIChatCompletionsSearchResult(
                    title: "Duplicate",
                    url: "https://foo.example.com",
                    snippet: "Ignored"
                ),
                OpenAIChatCompletionsSearchResult(
                    title: "   ",
                    url: " https://bar.example.com ",
                    snippet: "\n\n"
                )
            ]
        )

        XCTAssertEqual(
            markdown,
            "\n\n---\n\n### Sources\n1. [Foo \\[Docs\\]](<https://foo.example.com>) — Foo snippet\n2. [https://bar.example.com](<https://bar.example.com>)"
        )
    }

    func testSourcesMarkdownFallsBackToDeduplicatedCitations() {
        let markdown = OpenAIChatCompletionsSourceSupport.sourcesMarkdown(
            citations: [
                " https://example.com/a ",
                "Reference note",
                "https://example.com/a",
                "   "
            ],
            searchResults: []
        )

        XCTAssertEqual(
            markdown,
            "\n\n---\n\n### Sources\n1. <https://example.com/a>\n2. Reference note"
        )
    }

    func testSourcesMarkdownReturnsNilWhenNoUsableSourcesExist() {
        let markdown = OpenAIChatCompletionsSourceSupport.sourcesMarkdown(
            citations: [
                "   "
            ],
            searchResults: [
                OpenAIChatCompletionsSearchResult(
                    title: "Missing URL",
                    url: nil,
                    snippet: "Ignored"
                )
            ]
        )

        XCTAssertNil(markdown)
    }
}
