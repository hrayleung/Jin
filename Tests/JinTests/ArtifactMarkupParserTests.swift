import XCTest
@testable import Jin

final class ArtifactMarkupParserTests: XCTestCase {
    func testParseExtractsVisibleTextAndArtifact() {
        let input = """
        Intro text.
        <jinArtifact artifact_id="demo-card" title="Demo Card" contentType="text/html">
        <div>Hello</div>
        </jinArtifact>
        Outro text.
        """

        let result = ArtifactMarkupParser.parse(input)

        XCTAssertEqual(result.artifacts.count, 1)
        XCTAssertEqual(result.artifacts.first?.artifactID, "demo-card")
        XCTAssertEqual(result.artifacts.first?.title, "Demo Card")
        XCTAssertEqual(result.artifacts.first?.contentType, .html)
        XCTAssertEqual(result.artifacts.first?.content, "<div>Hello</div>")
        XCTAssertTrue(result.visibleText.contains("Intro text."))
        XCTAssertTrue(result.visibleText.contains("Outro text."))
        XCTAssertFalse(result.visibleText.contains("<jinArtifact"))
    }

    func testParseTrimsArtifactAttributesAndContent() throws {
        let input = """
        <jinArtifact artifact_id=" demo-card " title=" Demo Card " contentType=" text/html ">

          <div>Hello</div>

        </jinArtifact>
        """

        let artifact = try XCTUnwrap(ArtifactMarkupParser.parse(input).artifacts.first)

        XCTAssertEqual(artifact.artifactID, "demo-card")
        XCTAssertEqual(artifact.title, "Demo Card")
        XCTAssertEqual(artifact.contentType, .html)
        XCTAssertEqual(artifact.content, "<div>Hello</div>")
    }

    func testParseUsesTrimmedArtifactIDWhenTitleIsBlank() throws {
        let input = #"<jinArtifact artifact_id=" demo-card " title="  " contentType="text/html">x</jinArtifact>"#

        let artifact = try XCTUnwrap(ArtifactMarkupParser.parse(input).artifacts.first)

        XCTAssertEqual(artifact.title, "demo-card")
    }

    func testParseFallsBackToRawTextForUnsupportedContentType() {
        let input = "<jinArtifact artifact_id=\"bad\" title=\"Bad\" contentType=\"application/unknown\">x</jinArtifact>"

        let result = ArtifactMarkupParser.parse(input)

        XCTAssertTrue(result.artifacts.isEmpty)
        XCTAssertEqual(result.visibleText, input)
    }

    func testParseCanHideTrailingIncompleteArtifactDuringStreaming() {
        let input = "Before<jinArtifact artifact_id=\"demo\" title=\"Demo\" contentType=\"text/html\"><div>"

        let result = ArtifactMarkupParser.parse(input, hidesTrailingIncompleteArtifact: true)

        XCTAssertEqual(result.visibleText, "Before")
        XCTAssertTrue(result.hasIncompleteTrailingArtifact)
    }

    func testAppendsInstructionsWhenArtifactsEnabled() {
        let prompt = ArtifactMarkupParser.appendingInstructions(to: " \n Base prompt. \t ", enabled: true)

        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt?.contains("<jinArtifact") == true)
        XCTAssertTrue(prompt?.contains("application/vnd.jin.react") == true)
        XCTAssertTrue(prompt?.contains("Base prompt.") == true)
    }

    func testAppendingInstructionsTrimsDisabledPromptAndDropsBlankPrompt() {
        XCTAssertEqual(
            ArtifactMarkupParser.appendingInstructions(to: " \n Base prompt. \t ", enabled: false),
            "Base prompt."
        )
        XCTAssertNil(ArtifactMarkupParser.appendingInstructions(to: " \n\t ", enabled: false))
    }
}
