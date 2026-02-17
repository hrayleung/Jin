import XCTest
@testable import Jin

final class ProviderParamsJSONSyncTests: XCTestCase {
    func testVertexGemini3ProImageDraftOmitsThinkingConfigWhenReasoningConfigured() throws {
        let controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))

        let draft = ProviderParamsJSONSync.makeDraft(
            providerType: .vertexai,
            modelID: "gemini-3-pro-image-preview",
            controls: controls
        )

        if let generationConfig = draft["generationConfig"]?.value as? [String: Any] {
            XCTAssertNil(generationConfig["thinkingConfig"])
        } else {
            XCTAssertNil(draft["generationConfig"])
        }
    }

    func testVertexGemini3ProDraftKeepsThinkingLevelWhenEffortConfigured() throws {
        let controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))

        let draft = ProviderParamsJSONSync.makeDraft(
            providerType: .vertexai,
            modelID: "gemini-3-pro-preview",
            controls: controls
        )

        let generationConfig = try XCTUnwrap(draft["generationConfig"]?.value as? [String: Any])
        let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["includeThoughts"] as? Bool, true)
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "HIGH")
    }
}
