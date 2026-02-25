import Foundation
import XCTest
@testable import Jin

final class AdapterUtilitiesTests: XCTestCase {
    func testValidatedURLAcceptsSupportedAbsoluteSchemes() throws {
        let httpsURL = try validatedURL("https://api.example.com/v1")
        XCTAssertEqual(httpsURL.scheme, "https")
        XCTAssertEqual(httpsURL.host, "api.example.com")

        let wssURL = try validatedURL("wss://api.example.com/v1")
        XCTAssertEqual(wssURL.scheme, "wss")
        XCTAssertEqual(wssURL.host, "api.example.com")
    }

    func testValidatedURLRejectsRelativeEndpoint() {
        XCTAssertThrowsError(try validatedURL("api.example.com/v1")) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest")
            }
            XCTAssertTrue(message.contains("must be absolute"))
        }
    }

    func testValidatedURLRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try validatedURL("ftp://api.example.com/v1")) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest")
            }
            XCTAssertTrue(message.contains("Invalid URL scheme"))
        }
    }

    func testSplitContentPartsKeepsThinkingUnseparatedWhenVisibleUsesSeparator() {
        let parts: [ContentPart] = [
            .text("visible-a"),
            .text("visible-b"),
            .thinking(ThinkingBlock(text: "think-a")),
            .thinking(ThinkingBlock(text: "think-b"))
        ]

        let split = splitContentParts(parts, separator: "\n")
        XCTAssertEqual(split.visible, "visible-a\nvisible-b")
        XCTAssertEqual(split.thinking, "think-athink-b")
    }

    func testFindConfiguredModelRequiresExactIDMatch() {
        let provider = ProviderConfig(
            id: "p1",
            name: "Provider",
            type: .openaiCompatible,
            models: [
                ModelInfo(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    capabilities: [.streaming],
                    contextWindow: 128_000
                )
            ]
        )

        XCTAssertNotNil(findConfiguredModel(in: provider, for: "gpt-4o"))
        XCTAssertNil(findConfiguredModel(in: provider, for: "GPT-4O"))
    }
}
