import XCTest
@testable import Jin

final class ChatModelSelectionSupportTests: XCTestCase {
    func testPreferredFireworksModelIDPrefersKimiK26AcrossFireworksTopCandidates() {
        let models = [
            ModelInfo(
                id: "accounts/fireworks/models/qwen3p6-plus",
                name: "Qwen3.6 Plus",
                capabilities: [.streaming],
                contextWindow: 128_000,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "accounts/fireworks/models/deepseek-v3p2",
                name: "DeepSeek V3.2",
                capabilities: [.streaming],
                contextWindow: 163_800,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "accounts/fireworks/models/kimi-k2-instruct-0905",
                name: "Kimi K2 Instruct 0905",
                capabilities: [.streaming],
                contextWindow: 262_100,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "accounts/fireworks/models/glm-5",
                name: "GLM-5",
                capabilities: [.streaming],
                contextWindow: 202_800,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "accounts/fireworks/models/minimax-m2p5",
                name: "MiniMax M2.5",
                capabilities: [.streaming],
                contextWindow: 196_600,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "fireworks/kimi-k2p6",
                name: "Kimi K2.6",
                capabilities: [.streaming],
                contextWindow: 262_100,
                reasoningConfig: nil,
                isEnabled: true
            )
        ]

        XCTAssertEqual(
            ChatModelSelectionSupport.preferredFireworksModelID(in: models),
            "fireworks/kimi-k2p6"
        )
    }

    func testPreferredFireworksModelIDUsesVerifiedDeepSeekV4ProBeforeV32() {
        let models = [
            ModelInfo(
                id: "accounts/fireworks/models/deepseek-v3p2",
                name: "DeepSeek V3.2",
                capabilities: [.streaming],
                contextWindow: 163_800,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "fireworks/deepseek-v4-pro",
                name: "DeepSeek V4 Pro",
                capabilities: [.streaming],
                contextWindow: 128_000,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "deepseek-ai/deepseek-v4-pro",
                name: "DeepSeek V4 Pro",
                capabilities: [.streaming],
                contextWindow: 1_048_600,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
                isEnabled: true
            ),
            ModelInfo(
                id: "accounts/fireworks/models/deepseek-v4-pro",
                name: "DeepSeek V4 Pro",
                capabilities: [.streaming],
                contextWindow: 1_048_600,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
                isEnabled: true
            )
        ]

        XCTAssertEqual(
            ChatModelSelectionSupport.preferredFireworksModelID(in: models),
            "accounts/fireworks/models/deepseek-v4-pro"
        )

        XCTAssertEqual(
            ChatModelSelectionSupport.preferredFireworksModelID(in: Array(models.prefix(2))),
            "accounts/fireworks/models/deepseek-v3p2"
        )
    }

    func testPreferredModelIDPrefersLatestDeepInfraExactModels() {
        let models = [
            ModelInfo(
                id: "Qwen/Qwen3.6-35B-A3B",
                name: "Qwen3.6 35B A3B",
                capabilities: [.streaming],
                contextWindow: 262_144,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "zai-org/GLM-5.1",
                name: "GLM-5.1",
                capabilities: [.streaming],
                contextWindow: 202_752,
                reasoningConfig: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "zai-org/GLM-5",
                name: "GLM-5",
                capabilities: [.streaming],
                contextWindow: 202_752,
                reasoningConfig: nil,
                isEnabled: true
            )
        ]

        let provider = ProviderConfigEntity(
            id: "deepinfra",
            name: "DeepInfra",
            typeRaw: ProviderType.deepinfra.rawValue,
            modelsData: try! JSONEncoder().encode(models)
        )

        XCTAssertEqual(
            ChatModelSelectionSupport.preferredModelID(
                in: models,
                providerID: "deepinfra",
                providers: [provider],
                geminiPreferredModelOrder: []
            ),
            "zai-org/GLM-5.1"
        )
    }
}
