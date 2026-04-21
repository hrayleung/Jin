import XCTest
@testable import Jin

final class ChatModelSelectionSupportTests: XCTestCase {
    func testPreferredFireworksModelIDPrefersKimiK26BeforeGLM5AndMiniMax() {
        let models = [
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
}
