import XCTest
@testable import Jin

final class BuiltinSearchTinyFishPayloadTests: XCTestCase {

    func testTinyFishSearchURLIncludesQueryAndOmitsDefaultPage() throws {
        let url = try XCTUnwrap(
            BuiltinSearchToolHub.makeTinyFishSearchURL(
                query: "swift concurrency",
                location: nil,
                language: nil,
                includeDomains: [],
                excludeDomains: [],
                recencyDays: nil,
                domainType: nil,
                page: 0
            )
        )

        let items = queryItems(from: url)
        XCTAssertEqual(items["query"], "swift concurrency")
        XCTAssertNil(items["page"])
        XCTAssertNil(items["domain_type"])
        XCTAssertNil(items["recency_minutes"])
    }

    func testTinyFishSearchURLEmitsGeoLanguageAndDomainFilters() throws {
        let url = try XCTUnwrap(
            BuiltinSearchToolHub.makeTinyFishSearchURL(
                query: "swift",
                location: "US",
                language: "en",
                includeDomains: ["swift.org", "apple.com"],
                excludeDomains: ["pinterest.com"],
                recencyDays: 7,
                domainType: .news,
                page: 2
            )
        )

        let items = queryItems(from: url)
        XCTAssertEqual(items["location"], "US")
        XCTAssertEqual(items["language"], "en")
        XCTAssertEqual(items["include_domains"], "swift.org,apple.com")
        XCTAssertEqual(items["exclude_domains"], "pinterest.com")
        XCTAssertEqual(items["domain_type"], "news")
        XCTAssertEqual(items["recency_minutes"], "10080")
        XCTAssertEqual(items["page"], "2")
    }

    func testTinyFishSearchURLOmitsRecencyForResearchPapers() throws {
        let url = try XCTUnwrap(
            BuiltinSearchToolHub.makeTinyFishSearchURL(
                query: "attention is all you need",
                location: nil,
                language: nil,
                includeDomains: [],
                excludeDomains: [],
                recencyDays: 30,
                domainType: .researchPaper,
                page: 0
            )
        )

        let items = queryItems(from: url)
        XCTAssertEqual(items["domain_type"], "research_paper")
        XCTAssertNil(items["recency_minutes"])
        XCTAssertNil(items["after_date"])
        XCTAssertNil(items["before_date"])
    }

    func testTinyFishSearchURLOmitsWebDomainType() throws {
        let url = try XCTUnwrap(
            BuiltinSearchToolHub.makeTinyFishSearchURL(
                query: "swift",
                location: nil,
                language: nil,
                includeDomains: [],
                excludeDomains: [],
                recencyDays: nil,
                domainType: .web,
                page: 0
            )
        )

        XCTAssertNil(queryItems(from: url)["domain_type"])
    }

    func testTinyFishFetchBodyCapsAtTenURLsAndRequestsMarkdown() {
        let urls = (1...12).map { "https://example.com/\($0)" }
        let body = BuiltinSearchToolHub.makeTinyFishFetchBody(urls: urls)

        XCTAssertEqual(body["format"] as? String, "markdown")
        XCTAssertEqual((body["urls"] as? [String])?.count, 10)
        XCTAssertEqual((body["urls"] as? [String])?.first, "https://example.com/1")
    }

    func testTinyFishRowsEnrichNewsAndResearchFields() {
        let rows = BuiltinSearchToolHub.makeTinyFishRows(
            from: [
                [
                    "title": "AI regulation",
                    "url": "https://news.example.com/ai",
                    "snippet": "Lawmakers advanced a draft bill.",
                    "date": "2026-06-18",
                    "publisher": "Example News",
                    "site_name": "news.example.com"
                ],
                [
                    "title": "Attention Is All You Need",
                    "url": "https://arxiv.org/abs/1706.03762",
                    "snippet": "We propose a new simple network architecture.",
                    "authors": ["Ashish Vaswani", "Noam Shazeer"],
                    "venue": "NeurIPS",
                    "year": 2017,
                    "cited_by_count": 100_000,
                    "pdf_url": "https://arxiv.org/pdf/1706.03762"
                ]
            ],
            maxResults: 8
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].source, "Example News")
        XCTAssertEqual(rows[0].publishedAt, "2026-06-18")
        XCTAssertEqual(rows[1].publishedAt, "2017")
        XCTAssertTrue(rows[1].snippet?.contains("Authors: Ashish Vaswani, Noam Shazeer") == true)
        XCTAssertTrue(rows[1].snippet?.contains("Cited by 100000") == true)
        XCTAssertTrue(rows[1].snippet?.contains("PDF: https://arxiv.org/pdf/1706.03762") == true)
    }

    func testTinyFishRowsFallBackToPDFURLAndDeduplicate() {
        let rows = BuiltinSearchToolHub.makeTinyFishRows(
            from: [
                ["title": "Paper", "pdf_url": "https://arxiv.org/pdf/1706.03762"],
                ["title": "Duplicate", "url": "https://arxiv.org/pdf/1706.03762"]
            ],
            maxResults: 5
        )

        XCTAssertEqual(rows.map(\.url), ["https://arxiv.org/pdf/1706.03762"])
    }

    func testTinyFishMergePrefersFetchedMarkdownAndKeepsUnfetchedSnippets() {
        let rows = [
            SearchCitationRow(
                title: "TinyFish",
                url: "https://tinyfish.ai",
                snippet: "short",
                publishedAt: nil,
                source: "tinyfish.ai"
            ),
            SearchCitationRow(
                title: "Docs",
                url: "https://docs.tinyfish.ai",
                snippet: "keep me",
                publishedAt: nil,
                source: "docs.tinyfish.ai"
            )
        ]

        let merged = BuiltinSearchToolHub.mergeTinyFishFetchedContent(
            rows: rows,
            fetchResults: [
                [
                    "url": "https://tinyfish.ai",
                    "final_url": "https://www.tinyfish.ai/",
                    "text": String(repeating: "a", count: 9_000)
                ]
            ]
        )

        XCTAssertEqual(merged[0].snippet?.count, 8_000)
        XCTAssertEqual(merged[1].snippet, "keep me")
    }

    func testTinyFishDomainTypeResolvesAliases() {
        XCTAssertEqual(TinyFishDomainType.resolved(from: "news"), .news)
        XCTAssertEqual(TinyFishDomainType.resolved(from: "research paper"), .researchPaper)
        XCTAssertEqual(TinyFishDomainType.resolved(from: "research_paper"), .researchPaper)
        XCTAssertNil(TinyFishDomainType.resolved(from: " "))
    }

    private func queryItems(from url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var result: [String: String] = [:]
        for item in items {
            result[item.name] = item.value
        }
        return result
    }
}
