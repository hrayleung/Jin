import XCTest
@testable import Jin

final class ComposerRemoteVideoURLSupportTests: XCTestCase {
    func testCompactLabelPrefersFileNameThenHost() {
        XCTAssertEqual(
            ComposerRemoteVideoURLSupport.compactLabel(
                for: "https://cdn.example.com/source/input.mp4?token=abc123"
            ),
            "input.mp4"
        )
        XCTAssertEqual(
            ComposerRemoteVideoURLSupport.compactLabel(for: "https://cdn.example.com"),
            "cdn.example.com"
        )
        XCTAssertEqual(
            ComposerRemoteVideoURLSupport.compactLabel(for: "https://cdn.example.com/"),
            "cdn.example.com"
        )
        XCTAssertEqual(
            ComposerRemoteVideoURLSupport.compactLabel(for: "  https://cdn.example.com/a/My%20Clip.mov  "),
            "My Clip.mov"
        )
        XCTAssertEqual(ComposerRemoteVideoURLSupport.compactLabel(for: "not a url"), "not a url")
        XCTAssertEqual(ComposerRemoteVideoURLSupport.compactLabel(for: "   "), "")
        XCTAssertEqual(ComposerRemoteVideoURLSupport.compactLabel(for: ""), "")
    }

    func testCompactLabelClampsVeryLongComponents() {
        let longName = String(repeating: "a", count: 200) + ".mp4"
        let label = ComposerRemoteVideoURLSupport.compactLabel(for: "https://cdn.example.com/\(longName)")

        XCTAssertEqual(label.count, ComposerRemoteVideoURLSupport.maxCompactLabelLength)
        XCTAssertTrue(longName.hasPrefix(label))
    }

    func testValidationAcceptsEmptyAndHTTPSchemesOnly() {
        XCTAssertNil(ComposerRemoteVideoURLSupport.validationErrorMessage(for: ""))
        XCTAssertNil(ComposerRemoteVideoURLSupport.validationErrorMessage(for: "   "))
        XCTAssertNil(
            ComposerRemoteVideoURLSupport.validationErrorMessage(for: "https://cdn.example.com/a.mp4")
        )
        XCTAssertNil(
            ComposerRemoteVideoURLSupport.validationErrorMessage(for: "http://cdn.example.com/a.mp4")
        )

        XCTAssertNotNil(ComposerRemoteVideoURLSupport.validationErrorMessage(for: "file:///tmp/a.mp4"))
        XCTAssertNotNil(ComposerRemoteVideoURLSupport.validationErrorMessage(for: "ftp://cdn.example.com/a.mp4"))
        XCTAssertNotNil(ComposerRemoteVideoURLSupport.validationErrorMessage(for: "cdn.example.com/a.mp4"))
    }

    func testHelpTextSwitchesBetweenEmptyAndSetStates() {
        XCTAssertEqual(
            ComposerRemoteVideoURLSupport.helpText(for: "  "),
            "Add a source video URL"
        )
        XCTAssertEqual(
            ComposerRemoteVideoURLSupport.helpText(for: " https://cdn.example.com/a.mp4 "),
            "Source video: https://cdn.example.com/a.mp4"
        )
    }
}
