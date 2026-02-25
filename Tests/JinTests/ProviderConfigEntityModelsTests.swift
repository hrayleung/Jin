import XCTest
@testable import Jin

final class ProviderConfigEntityModelsTests: XCTestCase {
    func testEnabledModelsFiltersDisabledEntries() throws {
        let models = [
            ModelInfo(id: "a", name: "A", capabilities: [.streaming], contextWindow: 1024, isEnabled: true),
            ModelInfo(id: "b", name: "B", capabilities: [.streaming], contextWindow: 1024, isEnabled: false),
        ]
        let data = try JSONEncoder().encode(models)
        let provider = ProviderConfigEntity(
            id: "provider-a",
            name: "Provider A",
            typeRaw: ProviderType.openai.rawValue,
            modelsData: data
        )

        XCTAssertEqual(provider.allModels.count, 2)
        XCTAssertEqual(provider.enabledModels.count, 1)
        XCTAssertEqual(provider.enabledModels.first?.id, "a")
    }

    func testAllModelsCacheInvalidatesAfterModelsDataChange() throws {
        let initialModels = [
            ModelInfo(id: "old-model", name: "Old", capabilities: [.streaming], contextWindow: 1024, isEnabled: true),
        ]
        let updatedModels = [
            ModelInfo(id: "new-model", name: "New", capabilities: [.streaming], contextWindow: 2048, isEnabled: false),
        ]

        let provider = ProviderConfigEntity(
            id: "provider-b",
            name: "Provider B",
            typeRaw: ProviderType.openai.rawValue,
            modelsData: try JSONEncoder().encode(initialModels)
        )

        XCTAssertEqual(provider.allModels.first?.id, "old-model")
        XCTAssertEqual(provider.enabledModels.count, 1)

        provider.modelsData = try JSONEncoder().encode(updatedModels)

        XCTAssertEqual(provider.allModels.first?.id, "new-model")
        XCTAssertEqual(provider.enabledModels.count, 0)
    }
}
