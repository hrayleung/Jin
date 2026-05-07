import XCTest
@testable import Jin

final class CodeExecutionEntrySupportTests: XCTestCase {
    func testVisualStatusMapsExecutionStatusesToExistingBuckets() {
        XCTAssertEqual(CodeExecutionEntrySupport.visualStatus(for: .inProgress), .running)
        XCTAssertEqual(CodeExecutionEntrySupport.visualStatus(for: .writingCode), .running)
        XCTAssertEqual(CodeExecutionEntrySupport.visualStatus(for: .interpreting), .running)
        XCTAssertEqual(CodeExecutionEntrySupport.visualStatus(for: .completed), .success)
        XCTAssertEqual(CodeExecutionEntrySupport.visualStatus(for: .failed), .error)
        XCTAssertEqual(CodeExecutionEntrySupport.visualStatus(for: .incomplete), .error)
        XCTAssertEqual(CodeExecutionEntrySupport.visualStatus(for: .unknown("queued")), .neutral)
    }

    func testVisualStatusMapsToTerminalTimelineNodeGlyphs() {
        XCTAssertEqual(CodeExecVisualStatus.running.timelineNodeGlyph, .running)
        XCTAssertEqual(CodeExecVisualStatus.success.timelineNodeGlyph, .success)
        XCTAssertEqual(CodeExecVisualStatus.error.timelineNodeGlyph, .error)
        XCTAssertEqual(CodeExecVisualStatus.neutral.timelineNodeGlyph, .neutral)
    }

    func testStatusLabelsMatchCodeExecutionEntryCopy() {
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .inProgress), "Starting...")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .writingCode), "Writing...")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .interpreting), "Running...")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .completed), "Done")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .failed), "Failed")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .incomplete), "Incomplete")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .unknown("")), "Unknown")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .unknown(" \n ")), "Unknown")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .unknown("waiting")), "waiting")
        XCTAssertEqual(CodeExecutionEntrySupport.statusLabel(for: .unknown(" waiting \n")), "waiting")
    }

    func testRunningPlaceholderCopyMatchesProviderStatus() {
        XCTAssertEqual(CodeExecutionEntrySupport.statusPlaceholderText(for: .inProgress), "Starting...")
        XCTAssertEqual(CodeExecutionEntrySupport.statusPlaceholderText(for: .writingCode), "Writing code...")
        XCTAssertEqual(CodeExecutionEntrySupport.statusPlaceholderText(for: .interpreting), "Running code...")
        XCTAssertEqual(CodeExecutionEntrySupport.statusPlaceholderText(for: .completed), "")
    }

    func testDisplayableContentRecognizesAllRenderedContentInputs() {
        XCTAssertFalse(CodeExecutionEntrySupport.hasDisplayableContent(activity(status: .completed)))
        XCTAssertFalse(CodeExecutionEntrySupport.hasDisplayableContent(activity(status: .completed, code: "")))

        XCTAssertTrue(CodeExecutionEntrySupport.hasDisplayableContent(activity(status: .completed, code: "print(1)")))
        XCTAssertTrue(CodeExecutionEntrySupport.hasDisplayableContent(activity(status: .completed, stdout: "ok")))
        XCTAssertTrue(CodeExecutionEntrySupport.hasDisplayableContent(activity(status: .completed, stderr: "err")))
        XCTAssertTrue(
            CodeExecutionEntrySupport.hasDisplayableContent(
                activity(status: .completed, outputImages: [.init(url: "https://example.com/image.png")])
            )
        )
        XCTAssertTrue(
            CodeExecutionEntrySupport.hasDisplayableContent(
                activity(status: .completed, outputFiles: [.init(id: "file-1")])
            )
        )
        XCTAssertTrue(CodeExecutionEntrySupport.hasDisplayableContent(activity(status: .completed, containerID: "container")))
    }

    func testReturnCodeVisibilityMatchesTerminalStatuses() {
        XCTAssertFalse(CodeExecutionEntrySupport.shouldShowReturnCode(for: .inProgress))
        XCTAssertFalse(CodeExecutionEntrySupport.shouldShowReturnCode(for: .writingCode))
        XCTAssertFalse(CodeExecutionEntrySupport.shouldShowReturnCode(for: .interpreting))
        XCTAssertTrue(CodeExecutionEntrySupport.shouldShowReturnCode(for: .completed))
        XCTAssertTrue(CodeExecutionEntrySupport.shouldShowReturnCode(for: .failed))
        XCTAssertTrue(CodeExecutionEntrySupport.shouldShowReturnCode(for: .incomplete))
        XCTAssertFalse(CodeExecutionEntrySupport.shouldShowReturnCode(for: .unknown("done")))
    }

    func testCodeLanguageAndBadgeTextUseExistingInferenceButHideGenericBadge() {
        XCTAssertNil(CodeExecutionEntrySupport.codeLanguage(for: activity(status: .completed)))
        XCTAssertEqual(
            CodeExecutionEntrySupport.codeLanguage(
                for: activity(status: .completed, code: "import SwiftUI\nstruct Demo: View {}")
            ),
            .swift
        )
        XCTAssertEqual(CodeExecutionEntrySupport.codeBadgeText(for: .swift), "Swift")
        XCTAssertEqual(CodeExecutionEntrySupport.codeBadgeText(for: .python), "Python")
        XCTAssertNil(CodeExecutionEntrySupport.codeBadgeText(for: .generic))
        XCTAssertNil(CodeExecutionEntrySupport.codeBadgeText(for: nil))
    }

    func testOutputSummaryCopyPluralizesImageAndFileCounts() {
        XCTAssertEqual(CodeExecutionEntrySupport.imageOutputSummary(count: 1), "Generated 1 image output")
        XCTAssertEqual(CodeExecutionEntrySupport.imageOutputSummary(count: 2), "Generated 2 image outputs")
        XCTAssertEqual(CodeExecutionEntrySupport.fileOutputSummary(count: 1), "Generated 1 file output")
        XCTAssertEqual(CodeExecutionEntrySupport.fileOutputSummary(count: 2), "Generated 2 file outputs")
    }

    private func activity(
        status: CodeExecutionStatus,
        code: String? = nil,
        stdout: String? = nil,
        stderr: String? = nil,
        outputImages: [CodeExecutionOutputImage]? = nil,
        outputFiles: [CodeExecutionOutputFile]? = nil,
        containerID: String? = nil
    ) -> CodeExecutionActivity {
        CodeExecutionActivity(
            id: UUID().uuidString,
            status: status,
            code: code,
            stdout: stdout,
            stderr: stderr,
            outputImages: outputImages,
            outputFiles: outputFiles,
            containerID: containerID
        )
    }
}
