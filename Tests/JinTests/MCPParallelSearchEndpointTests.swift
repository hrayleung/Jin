import XCTest
@testable import Jin

final class MCPParallelSearchEndpointTests: XCTestCase {
    func testDetectsOfficialSearchMCPURLs() {
        XCTAssertTrue(MCPParallelSearchEndpoint.isSearchMCP("https://search.parallel.ai/mcp"))
        XCTAssertTrue(MCPParallelSearchEndpoint.isSearchMCP("https://search.parallel.ai/mcp/"))
        XCTAssertTrue(MCPParallelSearchEndpoint.isSearchMCP("https://search.parallel.ai/mcp-oauth"))
        XCTAssertTrue(MCPParallelSearchEndpoint.isSearchMCP("https://search.parallel.ai/mcp-oauth?mode=fast"))
        XCTAssertFalse(MCPParallelSearchEndpoint.isSearchMCP("https://search.parallel.ai/other"))
        XCTAssertFalse(MCPParallelSearchEndpoint.isSearchMCP("https://mcp.tavily.com/mcp"))
    }

    func testOAuthUsesTheOAuthEndpointAndPreservesQuery() {
        XCTAssertEqual(
            MCPParallelSearchEndpoint.aligned(
                "https://search.parallel.ai/mcp",
                to: .oauth
            ),
            MCPParallelSearchEndpoint.oauthURL
        )
        XCTAssertEqual(
            MCPParallelSearchEndpoint.aligned(
                "https://search.parallel.ai/mcp/?mode=fast",
                authentication: .oauth
            ),
            "https://search.parallel.ai/mcp-oauth?mode=fast"
        )
        XCTAssertEqual(
            MCPParallelSearchEndpoint.aligned(
                MCPParallelSearchEndpoint.oauthURL,
                to: .oauth
            ),
            MCPParallelSearchEndpoint.oauthURL
        )
    }

    func testAPIKeyAndAnonymousUseThePublicEndpoint() {
        XCTAssertEqual(
            MCPParallelSearchEndpoint.aligned(
                "https://search.parallel.ai/mcp-oauth",
                to: .none
            ),
            MCPParallelSearchEndpoint.anonymousURL
        )
        XCTAssertEqual(
            MCPParallelSearchEndpoint.aligned(
                "https://search.parallel.ai/mcp-oauth",
                authentication: .bearerToken("key")
            ),
            MCPParallelSearchEndpoint.anonymousURL
        )
        XCTAssertEqual(
            MCPParallelSearchEndpoint.aligned(
                "https://example.com/mcp",
                to: .oauth
            ),
            "https://example.com/mcp"
        )
    }
}
