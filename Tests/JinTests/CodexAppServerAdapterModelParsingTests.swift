import XCTest
@testable import Jin

final class CodexAppServerAdapterModelParsingTests: XCTestCase {
    func testMakeModelInfoParsesUpgradeAndAvailabilityMetadata() throws {
        let payload: [String: Any] = [
            "id": "gpt-5.3-codex",
            "displayName": "GPT-5.3 Codex",
            "inputModalities": ["text", "image"],
            "supportedReasoningEfforts": [
                ["reasoningEffort": "low", "description": "Fast"],
                ["reasoningEffort": "high", "description": "Deeper"]
            ],
            "defaultReasoningEffort": "high",
            "contextWindow": 400_000,
            "upgradeInfo": [
                "model": "gpt-5.4-codex",
                "upgradeCopy": "Try GPT-5.4 Codex for longer sessions."
            ],
            "availabilityNux": [
                "message": "Limited runs on your current plan."
            ]
        ]

        let object = try TestJSONHelpers.makeJSONObject(payload)
        let modelInfo = try XCTUnwrap(CodexAppServerAdapter.makeModelInfo(from: object))

        XCTAssertEqual(modelInfo.id, "gpt-5.3-codex")
        XCTAssertEqual(modelInfo.name, "GPT-5.3 Codex")
        XCTAssertEqual(modelInfo.contextWindow, 400_000)
        XCTAssertTrue(modelInfo.capabilities.contains(.streaming))
        XCTAssertTrue(modelInfo.capabilities.contains(.vision))
        XCTAssertTrue(modelInfo.capabilities.contains(.reasoning))
        XCTAssertEqual(modelInfo.reasoningConfig?.type, .effort)
        XCTAssertEqual(modelInfo.reasoningConfig?.defaultEffort, .high)
        XCTAssertEqual(modelInfo.catalogMetadata?.upgradeTargetModelID, "gpt-5.4-codex")
        XCTAssertEqual(modelInfo.catalogMetadata?.upgradeMessage, "Try GPT-5.4 Codex for longer sessions.")
        XCTAssertEqual(modelInfo.catalogMetadata?.availabilityMessage, "Limited runs on your current plan.")
    }

    func testMakeModelInfoSupportsLegacyReasoningArrayAndContextLength() throws {
        let payload: [String: Any] = [
            "model": "openai/gpt-5.2-codex",
            "displayName": "GPT-5.2 Codex",
            "supportedReasoningEfforts": ["low", "medium", "medium"],
            "context_length": 123_456
        ]

        let object = try TestJSONHelpers.makeJSONObject(payload)
        let modelInfo = try XCTUnwrap(CodexAppServerAdapter.makeModelInfo(from: object))

        XCTAssertEqual(modelInfo.id, "openai/gpt-5.2-codex")
        XCTAssertEqual(modelInfo.contextWindow, 123_456)
        XCTAssertTrue(modelInfo.capabilities.contains(.reasoning))
        XCTAssertEqual(modelInfo.reasoningConfig?.defaultEffort, .low)
    }

    func testMakeModelInfoReturnsNilWhenNoIdentifierProvided() throws {
        let payload: [String: Any] = [
            "displayName": "Missing ID"
        ]

        let object = try TestJSONHelpers.makeJSONObject(payload)
        XCTAssertNil(CodexAppServerAdapter.makeModelInfo(from: object))
    }
}
