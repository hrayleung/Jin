import XCTest
@testable import Jin

final class ChatMessageRenderPipelineBuildStrategyTests: XCTestCase {
    func testLongUserPromptUsesAsynchronousBuildEvenWhenMessageCountIsSmall() throws {
        let messages = try [
            makeMessageEntity(
                role: .user,
                text: String(repeating: "Long prompt line with embedded context.\n", count: 900)
            ),
            makeMessageEntity(
                role: .assistant,
                text: "Short acknowledgement."
            )
        ]

        XCTAssertTrue(ChatMessageRenderPipeline.shouldBuildRenderContextAsynchronously(from: messages))
    }

    func testCodeHeavyConversationUsesAsynchronousBuildBeforeMessageCountThreshold() throws {
        let messages = try (0..<12).map { index in
            try makeMessageEntity(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: """
                ```swift
                \(String(repeating: "let value = \(index)\n", count: 180))
                ```
                """
            )
        }

        XCTAssertTrue(ChatMessageRenderPipeline.shouldBuildRenderContextAsynchronously(from: messages))
    }

    func testSmallConversationKeepsSynchronousBuild() throws {
        let messages = try [
            makeMessageEntity(role: .user, text: "Summarize this."),
            makeMessageEntity(role: .assistant, text: "Here is a short summary.")
        ]

        XCTAssertFalse(ChatMessageRenderPipeline.shouldBuildRenderContextAsynchronously(from: messages))
    }

    private func makeMessageEntity(role: MessageRole, text: String) throws -> MessageEntity {
        try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: role,
                content: [.text(text)],
                timestamp: Date()
            )
        )
    }
}
