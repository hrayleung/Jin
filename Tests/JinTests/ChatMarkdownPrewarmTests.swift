import XCTest
@testable import Jin

final class ChatMarkdownPrewarmTests: XCTestCase {
    func testRichAssistantTextProducesExactRichCacheKeyInput() {
        let markdown = """
        ### 方案

        - **VS Code Remote-SSH**：适合多机切换

        | 方案 | Scala 支持 |
        | --- | --- |
        | VS Code | ★★★★★ |
        """
        let message = Message(role: .assistant, content: [.text(markdown)])

        let items = ChatMessageRenderPipeline.markdownPrewarmItems(
            for: message,
            artifactsEnabled: false
        )

        XCTAssertEqual(items, [
            NativeMarkdownCache.PrewarmItem(
                markdownText: markdown,
                renderPlainText: false
            )
        ])
    }

    func testSimpleAssistantTextUsesPersistedRowsPlainMode() {
        let message = Message(role: .assistant, content: [.text("A short plain answer.")])

        let items = ChatMessageRenderPipeline.markdownPrewarmItems(
            for: message,
            artifactsEnabled: false
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.markdownText, "A short plain answer.")
        XCTAssertEqual(items.first?.renderPlainText, true)
    }

    func testArtifactMarkupWarmsOnlyVisibleTextSegments() {
        let message = Message(
            role: .assistant,
            content: [.text(
                """
                Intro
                <jinArtifact artifact_id="demo" title="Demo" contentType="text/html"><div>demo</div></jinArtifact>
                Outro
                """
            )]
        )

        let items = ChatMessageRenderPipeline.markdownPrewarmItems(
            for: message,
            artifactsEnabled: true
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].markdownText.contains("Intro"))
        XCTAssertTrue(items[1].markdownText.contains("Outro"))
        XCTAssertTrue(items.allSatisfy { !$0.markdownText.contains("jinArtifact") })
        XCTAssertTrue(items.allSatisfy { !$0.renderPlainText })
    }
}
