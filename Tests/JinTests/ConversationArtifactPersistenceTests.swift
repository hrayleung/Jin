import XCTest
@testable import Jin

final class ConversationArtifactPersistenceTests: XCTestCase {
    func testConversationEntityRoundTripPreservesArtifactsEnabled() throws {
        let conversation = Conversation(
            title: "Artifacts",
            systemPrompt: "System",
            artifactsEnabled: true,
            messages: [Message(role: .assistant, content: [.text("Hello")])],
            modelConfig: ModelConfig(providerID: "openai", modelID: "gpt-5")
        )

        let entity = try ConversationEntity.fromDomain(conversation)
        let roundTrip = try entity.toDomain()

        XCTAssertEqual(entity.artifactsEnabled, true)
        XCTAssertEqual(roundTrip.artifactsEnabled, true)
    }

    func testConversationEntityDefaultsArtifactsEnabledToFalseWhenMissing() throws {
        let entity = ConversationEntity(
            title: "Legacy",
            artifactsEnabled: nil,
            providerID: "openai",
            modelID: "gpt-5",
            modelConfigData: try JSONEncoder().encode(GenerationControls())
        )

        let roundTrip = try entity.toDomain()

        XCTAssertEqual(roundTrip.artifactsEnabled, false)
    }
}
