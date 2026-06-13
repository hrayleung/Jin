import XCTest
@testable import Jin

final class CohereAdapterTests: XCTestCase {

    private func baseURL(for configured: String) async -> String {
        let config = ProviderConfig(
            id: "cohere",
            name: "Cohere",
            type: .cohere,
            apiKey: "ignored",
            baseURL: configured
        )
        let adapter = CohereAdapter(providerConfig: config, apiKey: "ignored")
        return await adapter.baseURL
    }

    // Locks in baseURL normalization after fixing the stale-`lower` bug where the
    // `/v2` fast-path was evaluated against the pre-`/chat`-strip snapshot.
    func testBaseURLNormalization() async {
        // /chat is stripped, then the /v2 suffix is recognized (previously this
        // only worked by accident via the path fallback below).
        await assertBaseURL("https://api.cohere.com/v2/chat", equals: "https://api.cohere.com/v2")
        await assertBaseURL("https://api.cohere.com/v2/chat/", equals: "https://api.cohere.com/v2")

        // Already-normalized inputs pass through unchanged.
        await assertBaseURL("https://api.cohere.com/v2", equals: "https://api.cohere.com/v2")
        await assertBaseURL("https://api.cohere.com/v2/", equals: "https://api.cohere.com/v2")

        // Bare host (with or without trailing slash) gets /v2 appended.
        await assertBaseURL("https://api.cohere.com", equals: "https://api.cohere.com/v2")
        await assertBaseURL("https://api.cohere.com/", equals: "https://api.cohere.com/v2")

        // A custom proxy path is preserved verbatim (no /v2 appended).
        await assertBaseURL("https://proxy.example.com/cohere", equals: "https://proxy.example.com/cohere")
    }

    private func assertBaseURL(
        _ configured: String,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let resolved = await baseURL(for: configured)
        XCTAssertEqual(resolved, expected, "baseURL(\(configured))", file: file, line: line)
    }
}
