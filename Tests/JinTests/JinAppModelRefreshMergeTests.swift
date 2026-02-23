import XCTest
@testable import Jin

final class JinAppModelRefreshMergeTests: XCTestCase {
    func testMergeRefreshedModelsUsesLatestPersistedDuplicateForUserPreferences() {
        let existingModels = [
            ModelInfo(
                id: "gpt-4.1",
                name: "GPT-4.1 old",
                capabilities: [.streaming],
                contextWindow: 128_000,
                overrides: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "gpt-4.1",
                name: "GPT-4.1 newer",
                capabilities: [.streaming],
                contextWindow: 128_000,
                overrides: ModelOverrides(contextWindow: 64_000),
                isEnabled: false
            ),
        ]

        let latestModels = [
            ModelInfo(
                id: "gpt-4.1",
                name: "GPT-4.1 refreshed",
                capabilities: [.streaming, .toolCalling],
                contextWindow: 256_000
            ),
        ]

        let merged = JinApp.mergeRefreshedModels(latestModels: latestModels, existingModels: existingModels)
        XCTAssertEqual(merged.count, 1)

        guard let model = merged.first else {
            return XCTFail("Expected one merged model")
        }
        XCTAssertEqual(model.name, "GPT-4.1 refreshed")
        XCTAssertEqual(model.contextWindow, 256_000)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.overrides?.contextWindow, 64_000)
    }

    func testMergeRefreshedModelsDeduplicatesLatestProviderPayload() {
        let latestModels = [
            ModelInfo(
                id: "duplicate-model",
                name: "First",
                capabilities: [.streaming],
                contextWindow: 4_096
            ),
            ModelInfo(
                id: "duplicate-model",
                name: "Second",
                capabilities: [.toolCalling],
                contextWindow: 8_192
            ),
            ModelInfo(
                id: "new-model",
                name: "New Model",
                capabilities: [.reasoning],
                contextWindow: 32_768
            ),
        ]

        let merged = JinApp.mergeRefreshedModels(latestModels: latestModels, existingModels: [])
        XCTAssertEqual(merged.map(\.id), ["duplicate-model", "new-model"])

        let duplicate = merged[0]
        XCTAssertEqual(duplicate.name, "First")
        XCTAssertEqual(duplicate.contextWindow, 4_096)
        XCTAssertTrue(duplicate.isEnabled)
    }
}
