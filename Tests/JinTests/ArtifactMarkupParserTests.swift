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

    // MARK: - Resumable scan

    func testResumableScanMatchesOneShotForPlainText() {
        let input = "Hello there. This is a long-ish reply with no artifacts at all. Just plain text."
        assertResumableMatchesOneShot(input, hidesTrailingIncompleteArtifact: false)
        assertResumableMatchesOneShot(input, hidesTrailingIncompleteArtifact: true)
    }

    func testResumableScanMatchesOneShotForOneArtifact() {
        let input = """
        Intro.
        <jinArtifact artifact_id="a" title="A" contentType="text/html"><b>x</b></jinArtifact>
        Outro.
        """
        assertResumableMatchesOneShot(input, hidesTrailingIncompleteArtifact: false)
        assertResumableMatchesOneShot(input, hidesTrailingIncompleteArtifact: true)
    }

    func testResumableScanMatchesOneShotForTwoArtifacts() {
        let input = """
        before
        <jinArtifact artifact_id="a" title="A" contentType="text/html"><i>1</i></jinArtifact>
        middle
        <jinArtifact artifact_id="b" title="B" contentType="text/html"><i>2</i></jinArtifact>
        after
        """
        assertResumableMatchesOneShot(input, hidesTrailingIncompleteArtifact: false)
        assertResumableMatchesOneShot(input, hidesTrailingIncompleteArtifact: true)
    }

    func testResumableScanMatchesOneShotForUnsupportedContentTypeFallback() {
        let input = "x<jinArtifact artifact_id=\"bad\" title=\"Bad\" contentType=\"application/unknown\">y</jinArtifact>z"
        assertResumableMatchesOneShot(input, hidesTrailingIncompleteArtifact: false)
        assertResumableMatchesOneShot(input, hidesTrailingIncompleteArtifact: true)
    }

    func testResumableScanHidesTrailingIncompleteOpeningAcrossDeltas() {
        let input = "Before<jinArtifact artifact_id=\"demo\" title=\"D\" contentType=\"text/html\"><div>"
        var state = ArtifactMarkupParser.ScanState.initial
        var lastVisible = ""
        for prefix in incrementalPrefixes(of: input) {
            let result = ArtifactMarkupParser.parse(prefix, hidesTrailingIncompleteArtifact: true, state: &state)
            lastVisible = result.visibleText
        }
        XCTAssertEqual(lastVisible, "Before")
    }

    func testResumableScanNeverDoubleEmitsArtifacts() {
        let input = "a<jinArtifact artifact_id=\"x\" title=\"X\" contentType=\"text/html\">payload</jinArtifact>tail"
        var state = ArtifactMarkupParser.ScanState.initial
        var maxSeen = 0
        for prefix in incrementalPrefixes(of: input) {
            let result = ArtifactMarkupParser.parse(prefix, hidesTrailingIncompleteArtifact: true, state: &state)
            maxSeen = max(maxSeen, result.artifacts.count)
            XCTAssertLessThanOrEqual(result.artifacts.count, 1, "duplicate artifacts emitted at prefix length \(prefix.count)")
        }
        XCTAssertEqual(maxSeen, 1)
    }

    func testResumableScanResetsOnShrinkingInput() {
        var state = ArtifactMarkupParser.ScanState.initial
        let long = "Hello this is a long bit of text that exceeds the retention window."
        _ = ArtifactMarkupParser.parse(long, hidesTrailingIncompleteArtifact: true, state: &state)
        let short = "Hi"
        let result = ArtifactMarkupParser.parse(short, hidesTrailingIncompleteArtifact: true, state: &state)
        XCTAssertEqual(result.visibleText, short)
        XCTAssertTrue(result.artifacts.isEmpty)
    }

    func testResumableScanHandlesMidMarkerSplit() {
        // Stream the input one character at a time so the opening marker is
        // split across many "deltas". The retention window should keep us from
        // committing past a partial `<jinArtifact` opener.
        let input = "leading <jinArtifact artifact_id=\"m\" title=\"M\" contentType=\"text/html\">body</jinArtifact> trailing"
        var state = ArtifactMarkupParser.ScanState.initial
        var lastResult: ArtifactParseResult?
        for prefix in incrementalPrefixes(of: input) {
            lastResult = ArtifactMarkupParser.parse(prefix, hidesTrailingIncompleteArtifact: true, state: &state)
        }
        let oneShot = ArtifactMarkupParser.parse(input, hidesTrailingIncompleteArtifact: true)
        XCTAssertEqual(lastResult?.visibleText, oneShot.visibleText)
        XCTAssertEqual(lastResult?.artifacts.map(\.artifactID), oneShot.artifacts.map(\.artifactID))
    }

    // MARK: helpers

    private func assertResumableMatchesOneShot(
        _ input: String,
        hidesTrailingIncompleteArtifact: Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let oneShot = ArtifactMarkupParser.parse(
            input,
            hidesTrailingIncompleteArtifact: hidesTrailingIncompleteArtifact
        )

        var state = ArtifactMarkupParser.ScanState.initial
        var resumable: ArtifactParseResult?
        for prefix in incrementalPrefixes(of: input) {
            resumable = ArtifactMarkupParser.parse(
                prefix,
                hidesTrailingIncompleteArtifact: hidesTrailingIncompleteArtifact,
                state: &state
            )
        }

        XCTAssertEqual(resumable?.visibleText, oneShot.visibleText, "visibleText mismatch", file: file, line: line)
        XCTAssertEqual(
            resumable?.artifacts.map(\.artifactID),
            oneShot.artifacts.map(\.artifactID),
            "artifact id list mismatch",
            file: file,
            line: line
        )
        XCTAssertEqual(
            resumable?.artifacts.map(\.content),
            oneShot.artifacts.map(\.content),
            "artifact content mismatch",
            file: file,
            line: line
        )
        XCTAssertEqual(
            resumable?.hasIncompleteTrailingArtifact,
            oneShot.hasIncompleteTrailingArtifact,
            "hasIncompleteTrailingArtifact mismatch",
            file: file,
            line: line
        )
    }

    private func incrementalPrefixes(of input: String) -> [String] {
        let nsInput = input as NSString
        var out: [String] = []
        var i = 0
        while i < nsInput.length {
            i += 1
            out.append(nsInput.substring(to: i))
        }
        return out
    }
}
