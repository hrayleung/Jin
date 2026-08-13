import MCP
import XCTest
@testable import Jin

/// Tool results used to keep only `.text`, which threw away an embedded resource's
/// text entirely and made images and audio vanish without the model even learning
/// that something had been returned.
final class MCPToolResultContentTests: XCTestCase {
    private func render(_ contents: [MCP.Tool.Content]) -> String {
        contents.compactMap(MCPClient.line(for:)).joined(separator: "\n")
    }

    func testTextOnlyResultsAreUnchanged() {
        XCTAssertEqual(
            render([
                .text(text: "first", annotations: nil, _meta: nil),
                .text(text: "second", annotations: nil, _meta: nil)
            ]),
            "first\nsecond",
            "Text-only results must render exactly as before"
        )
    }

    func testEmptyResultIsEmpty() {
        XCTAssertEqual(render([]), "")
    }

    func testEmbeddedResourceTextIsRecovered() {
        let content = render([
            .resource(resource: .text("the contents", uri: "file:///notes.txt", mimeType: "text/plain"))
        ])

        XCTAssertEqual(content, "the contents", "Inline resource text is real content that used to be dropped")
    }

    func testEmbeddedResourceWithoutTextFallsBackToADescriptor() {
        let content = render([
            .resource(resource: .binary(Data(), uri: "file:///a.bin", mimeType: "application/octet-stream"))
        ])

        XCTAssertEqual(content, "[resource file:///a.bin — application/octet-stream]")
    }

    func testImageIsAnnouncedRatherThanDroppedSilently() {
        // 1400 base64 chars ≈ 1050 bytes.
        let base64 = String(repeating: "A", count: 1400)

        let content = render([
            .text(text: "here", annotations: nil, _meta: nil),
            .image(data: base64, mimeType: "image/png", annotations: nil, _meta: nil)
        ])

        XCTAssertEqual(content, "here\n[image returned — image/png, 1 KB; not shown]")
    }

    func testAudioIsAnnouncedRatherThanDroppedSilently() {
        let content = render([
            .audio(data: String(repeating: "A", count: 8), mimeType: "audio/wav", annotations: nil, _meta: nil)
        ])

        XCTAssertEqual(content, "[audio returned — audio/wav, 6 B; not shown]")
    }

    func testByteCountFormattingIsLocaleIndependent() {
        XCTAssertEqual(MCPClient.formattedByteCount(base64Length: 0), "0 B")
        XCTAssertEqual(MCPClient.formattedByteCount(base64Length: 4), "3 B")
        XCTAssertEqual(MCPClient.formattedByteCount(base64Length: 1400), "1 KB")
        XCTAssertEqual(MCPClient.formattedByteCount(base64Length: 1_400_000), "1.0 MB")
    }
}
