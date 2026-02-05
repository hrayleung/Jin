import XCTest
@testable import Jin

final class MistralOCRMarkdownTests: XCTestCase {
    func testReferencedImageIDsExtractsLastPathComponent() {
        let markdown = """
        Before ![img](img-0.jpeg) and ![](folder/table-1.png).
        """
        XCTAssertEqual(
            MistralOCRMarkdown.referencedImageIDs(in: markdown),
            ["img-0.jpeg", "table-1.png"]
        )
    }

    func testRemovingImageMarkdownKeepsSurroundingText() {
        let markdown = """
        ![img-0.jpeg](img-0.jpeg)
        Figure 1: Hello
        """
        let stripped = MistralOCRMarkdown.removingImageMarkdown(from: markdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(stripped, "Figure 1: Hello")
    }

    func testReplacingImageMarkdownAllowsCustomPlaceholder() {
        let markdown = "See ![x](img-0.jpeg) here."
        let replaced = MistralOCRMarkdown.replacingImageMarkdown(from: markdown) { id in
            "[Image: \(id)]"
        }
        XCTAssertEqual(replaced, "See [Image: img-0.jpeg] here.")
    }
}

