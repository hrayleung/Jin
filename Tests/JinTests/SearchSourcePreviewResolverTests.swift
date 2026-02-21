import XCTest
@testable import Jin

final class SearchSourcePreviewResolverTests: XCTestCase {
    func testCanonicalXStatusURLIfNeededNormalizesProfileStatusURL() {
        let url = URL(string: "https://twitter.com/Interior/status/463440424141459456?s=20")!

        XCTAssertEqual(
            SearchSourcePreviewResolver.canonicalXStatusURLIfNeeded(for: url)?.absoluteString,
            "https://x.com/Interior/status/463440424141459456"
        )
    }

    func testCanonicalXStatusURLIfNeededNormalizesIWebStatusURL() {
        let url = URL(string: "https://x.com/i/web/status/463440424141459456?t=abc")!

        XCTAssertEqual(
            SearchSourcePreviewResolver.canonicalXStatusURLIfNeeded(for: url)?.absoluteString,
            "https://x.com/i/web/status/463440424141459456"
        )
    }

    func testCanonicalXStatusURLIfNeededRejectsNonStatusPath() {
        let url = URL(string: "https://x.com/explore")!
        XCTAssertNil(SearchSourcePreviewResolver.canonicalXStatusURLIfNeeded(for: url))
    }

    func testExtractXPostPreviewFromOEmbedPayloadUsesTweetHTML() throws {
        let payload: [String: Any] = [
            "html": #"<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">AI &amp; ML updates from <a href=\"https://x.com\">x.com</a></p>&mdash; Team (@team)</blockquote>"#
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertEqual(
            SearchSourcePreviewResolver.extractXPostPreview(fromOEmbedPayload: data),
            "AI & ML updates from x.com"
        )
    }

    func testExtractXPostPreviewFromOEmbedPayloadFallsBackToTitle() throws {
        let payload: [String: Any] = [
            "title": "  Embedded preview fallback title  "
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertEqual(
            SearchSourcePreviewResolver.extractXPostPreview(fromOEmbedPayload: data),
            "Embedded preview fallback title"
        )
    }
}
