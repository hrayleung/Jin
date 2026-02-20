import XCTest
@testable import Jin

final class SearchSourcePreviewHTMLParserTests: XCTestCase {
    func testExtractPreviewPrefersOpenGraphDescription() {
        let html = """
        <html>
          <head>
            <meta name="description" content="Fallback description text">
            <meta property="og:description" content="OpenGraph description should win.">
          </head>
        </html>
        """

        XCTAssertEqual(
            SearchSourcePreviewHTMLParser.extractPreview(from: html),
            "OpenGraph description should win."
        )
    }

    func testExtractPreviewDecodesEntitiesAndStripsTags() {
        let html = """
        <html>
          <head>
            <meta name="description" content="AI &amp; ML &quot;daily&quot; &lt;b&gt;summary&lt;/b&gt;">
          </head>
        </html>
        """

        XCTAssertEqual(
            SearchSourcePreviewHTMLParser.extractPreview(from: html),
            "AI & ML \"daily\" summary"
        )
    }

    func testExtractPreviewPrefersLongParagraphWhenMetaIsTooShort() {
        let html = """
        <html>
          <head>
            <meta name="description" content="Home">
          </head>
          <body>
            <p>OpenAI announced broader model availability and improved web search citation behavior in this detailed release update.</p>
          </body>
        </html>
        """

        XCTAssertEqual(
            SearchSourcePreviewHTMLParser.extractPreview(from: html),
            "OpenAI announced broader model availability and improved web search citation behavior in this detailed release update."
        )
    }

    func testExtractPreviewFallsBackToParagraph() {
        let html = """
        <html>
          <body>
            <p>First paragraph with useful article summary text.</p>
          </body>
        </html>
        """

        XCTAssertEqual(
            SearchSourcePreviewHTMLParser.extractPreview(from: html),
            "First paragraph with useful article summary text."
        )
    }

    func testExtractPreviewFallsBackToJSONLDDescription() {
        let html = """
        <html>
          <head>
            <script type="application/ld+json">
              {
                "@context": "https://schema.org",
                "@type": "NewsArticle",
                "headline": "Ignored headline",
                "description": "JSON-LD description should be used when meta tags are absent."
              }
            </script>
          </head>
        </html>
        """

        XCTAssertEqual(
            SearchSourcePreviewHTMLParser.extractPreview(from: html),
            "JSON-LD description should be used when meta tags are absent."
        )
    }

    func testExtractPreviewUsesJSONLDHeadlineWhenDescriptionIsMissing() {
        let html = """
        <html>
          <head>
            <script type="application/ld+json">
              {
                "@context": "https://schema.org",
                "@type": "NewsArticle",
                "headline": "Headline fallback should be used."
              }
            </script>
          </head>
        </html>
        """

        XCTAssertEqual(
            SearchSourcePreviewHTMLParser.extractPreview(from: html),
            "Headline fallback should be used."
        )
    }

    func testExtractPreviewDecodesNumericEntities() {
        let html = """
        <html>
          <head>
            <meta name="description" content="Price dropped to &#36;199 and hex is &#x26;">
          </head>
        </html>
        """

        XCTAssertEqual(
            SearchSourcePreviewHTMLParser.extractPreview(from: html),
            "Price dropped to $199 and hex is &"
        )
    }
}
